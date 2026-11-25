import Foundation
import Observation
import SwiftUI

/// What every model is told before it reads the conversation. The same text goes to Claude,
/// ChatGPT, Gemini and local models, which is what lets them share one picture of the Space.
@MainActor
enum AIContext {
    static func systemPrompt(space: SpaceModel, store: Store, ai: AIStore, account: Account, model: AIModelRef,
                             threadID: UUID, skill: AISkill?, mcpTools: [AIToolSpec]) -> String {
        var out = """
        You are \(model.label), working inside Tether, a macOS notes app. The user keeps notes ("nodes"), files and plans here, grouped into Spaces and categories, and talks to several AI models in the same place: Claude, ChatGPT, Gemini and local models. All of them share what is below — the Space, its nodes, the conversations and a common memory — so that any one of them can pick up where another left off.

        Earlier assistant messages in this conversation may have been written by a different model; each starts with its author in square brackets. Treat that work as a colleague's: build on it, and say so plainly when you disagree with it. Do not start your own replies with a bracketed name.

        How to work here:
        - Reply in the language the user writes in.
        - The list of nodes below only has titles. Read a node with read_node before you describe it, quote it or change it.
        - When the user asks you to change or add to their notes, do it with the tools instead of only describing the change, then say in a sentence what you changed and where. Keep each edit as small as the request: prefer append_to_node and replace_in_node, and never retype a whole node to change part of it.
        - Every edit can be undone by the user with ⌘Z.

        """
        switch ai.settings.permission {
        case .ask: out += "- The user is asked to approve each edit before it happens. If one is declined, do not try it again; ask what they would prefer.\n"
        case .auto: out += "- Edits apply immediately, without the user confirming each one, so make only the changes that were asked for.\n"
        case .readOnly: out += "- In this conversation you can read but not edit. If a change is needed, write out exactly what you would change.\n"
        }
        out += """
        - When you learn something that will matter in later conversations (a preference, a decision, a fact about the user's projects), save it with remember so the other models know it too.
        - Your answer is shown in a narrow side panel: be direct, and keep formatting light (short paragraphs, simple lists, **bold** for the few words that matter).

        ## This Space
        Name: \(space.info.name)

        """
        if !space.info.subtitle.isEmpty { out += "Subtitle: \(space.info.subtitle)\n" }
        if !space.info.about.isEmpty { out += "About: \(space.info.about)\n" }
        let siblings = store.spaces(of: account.id).filter { $0 !== space }.map(\.info.name)
        if !siblings.isEmpty { out += "Other Spaces of this account (readable with the `space` argument): " + siblings.joined(separator: ", ") + "\n" }
        if !space.categories.isEmpty { out += "Categories: " + space.categories.map(\.name).joined(separator: ", ") + "\n" }
        out += "\nNodes (\(space.nodes.count)):\n"
        out += space.nodes.isEmpty ? "(none yet)\n" : space.nodes.prefix(200).map { "- " + NodeReader.line(for: $0, in: space) }.joined(separator: "\n") + "\n"

        if ai.settings.includeOpenNode, let open = space.activeNode {
            out += "\n## The node the user has open right now\n"
            out += NodeReader.text(of: open, in: space, store: store, limit: 9_000) + "\n"
        } else if space.activeNode == nil {
            out += "\nThe user is on the Space's home page; no node is open.\n"
        }

        let memory = ai.memory(for: account.id)
        out += "\n## Shared memory (saved by the user or by any model)\n"
        out += memory.isEmpty ? "(empty)\n" : memory.map { "- \($0.text)" + ($0.author.isEmpty ? "" : " — saved by \($0.author)") }.joined(separator: "\n") + "\n"

        let others = ai.threads(in: space.id).filter { $0.id != threadID && !$0.messages.isEmpty }.prefix(15)
        if !others.isEmpty {
            out += "\n## Other conversations in this Space (read one with read_chat)\n"
            out += others.map { thread in
                let models = Set(thread.messages.compactMap { $0.model?.provider.title }).sorted().joined(separator: ", ")
                return "- [\(NodeReader.shortID(thread.id))] \(thread.title.isEmpty ? "Untitled" : thread.title)" + (models.isEmpty ? "" : " — with \(models)")
            }.joined(separator: "\n") + "\n"
        }

        if !ai.settings.skills.isEmpty {
            out += "\n## The user's skills\nReusable instructions the user has set up. When a request matches one, load it with use_skill and follow it.\n"
            out += ai.settings.skills.map { "- \($0.name): \($0.summary)" }.joined(separator: "\n") + "\n"
        }
        if !mcpTools.isEmpty {
            out += "\n## Connected MCP servers\nTools whose names start with mcp__ come from servers the user connected. They reach outside Tether, so use them only when the request calls for it.\n"
        }
        if let skill {
            out += "\n## Skill chosen for this message: \(skill.name)\n\(skill.instructions)\n"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        out += "\nToday is \(formatter.string(from: Date()))."
        return out
    }

    /// Earlier messages as plain text. Each assistant message names the model that wrote it and
    /// what it did, so a different model reading it later knows whose work it is.
    static func history(_ messages: [ChatMessage]) -> [AITurn] {
        var turns: [AITurn] = []
        for message in messages {
            switch message.role {
            case .user:
                turns.append(AITurn(role: .user, text: message.text))
            case .assistant:
                var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let done = message.activity.filter { $0.status == .done }.map(\.summary)
                if !done.isEmpty { text += (text.isEmpty ? "" : "\n\n") + "(Actions taken: " + done.joined(separator: "; ") + ")" }
                guard !text.isEmpty else { continue }
                turns.append(AITurn(role: .assistant, text: "[\(message.model?.label ?? "Assistant")] " + text))
            }
        }
        // Keep what fits comfortably: the latest messages, up to a generous size.
        var kept: [AITurn] = []
        var size = 0
        for turn in turns.reversed() {
            size += turn.text.count
            if kept.count >= 80 || (size > 120_000 && !kept.isEmpty) { break }
            kept.insert(turn, at: 0)
        }
        return kept
    }
}

/// Runs a message through a model: sends the shared context, streams the reply into the
/// conversation, carries out the tool calls the model makes, and repeats until it is done.
@MainActor
@Observable
final class AIEngine {
    enum Answer { case allow, allowAll, deny }

    struct PendingApproval: Identifiable, Equatable {
        var id = UUID()
        var thread: UUID
        var title: String
        var detail: String
    }

    @ObservationIgnored let store: Store
    @ObservationIgnored let ai: AIStore
    @ObservationIgnored let mcp: MCPHub

    /// Conversations with a reply in progress.
    var busy: Set<UUID> = []
    /// The message being written, per conversation.
    var streaming: [UUID: UUID] = [:]
    /// An edit waiting for the user's yes or no.
    var approval: PendingApproval?

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var waiting: CheckedContinuation<Answer, Never>?
    /// Conversations where the user chose "always allow" (until the app quits).
    @ObservationIgnored private var trusted: Set<UUID> = []
    /// Called when a reply has finished (used by the scripted checks).
    @ObservationIgnored var onFinish: ((UUID) -> Void)?

    init(store: Store, ai: AIStore, mcp: MCPHub) {
        self.store = store
        self.ai = ai
        self.mcp = mcp
    }

    /// Sends a message in the Space's current conversation (starting one if there is none).
    @discardableResult
    func send(_ text: String, skill: AISkill? = nil, in space: SpaceModel) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let model = ai.activeModel, let account = store.owner(of: space.id) else { return nil }
        let thread = ai.activeThread(in: space.id) ?? ai.newThread(in: space.id)
        guard !busy.contains(thread.id) else { return nil }

        let earlier = thread.messages
        let question = ChatMessage(role: .user, text: trimmed, nodeID: space.activeTab, skill: skill?.name)
        let reply = ChatMessage(role: .assistant, text: "", model: model)
        ai.updateThread(thread.id, in: space.id) { thread in
            thread.messages.append(contentsOf: [question, reply])
            if thread.title.isEmpty { thread.title = String(trimmed.split(whereSeparator: \.isNewline).first?.prefix(60) ?? "") }
            thread.updatedAt = Date()
        }
        ai.saveChats(space.id)
        busy.insert(thread.id)
        streaming[thread.id] = reply.id

        let threadID = thread.id, spaceID = space.id, replyID = reply.id
        tasks[threadID] = Task { [weak self] in
            guard let self else { return }
            await self.run(history: earlier + [question], replyID: replyID, threadID: threadID, space: space, account: account, model: model, skill: skill)
            self.busy.remove(threadID)
            self.streaming[threadID] = nil
            self.tasks[threadID] = nil
            self.ai.updateThread(threadID, in: spaceID) { $0.updatedAt = Date() }
            self.ai.saveChats(spaceID)
            self.onFinish?(threadID)
        }
        return threadID
    }

    func stop(_ threadID: UUID) {
        tasks[threadID]?.cancel()
        if approval?.thread == threadID { answer(.deny) }
    }

    func answer(_ answer: Answer) {
        guard let pending = approval else { return }
        if answer == .allowAll { trusted.insert(pending.thread) }
        withAnimation(Motion.snappy) { approval = nil }
        waiting?.resume(returning: answer)
        waiting = nil
    }

    private func ask(_ call: AIToolCall, toolbox: AIToolbox, thread: UUID) async -> Answer {
        await withCheckedContinuation { continuation in
            waiting = continuation
            withAnimation(Motion.spring) {
                approval = PendingApproval(thread: thread, title: toolbox.summary(of: call), detail: toolbox.detail(of: call))
            }
        }
    }

    private func run(history: [ChatMessage], replyID: UUID, threadID: UUID, space: SpaceModel, account: Account,
                     model: AIModelRef, skill: AISkill?) async {
        func edit(_ change: (inout ChatMessage) -> Void) {
            ai.updateMessage(replyID, thread: threadID, in: space.id, change)
        }
        await mcp.sync(with: ai.settings.servers)
        let toolbox = AIToolbox(space: space, store: store, ai: ai, account: account, threadID: threadID, model: model, mcp: mcp)
        let request = AIRequest(model: model,
                                system: AIContext.systemPrompt(space: space, store: store, ai: ai, account: account, model: model,
                                                               threadID: threadID, skill: skill, mcpTools: mcp.tools),
                                history: AIContext.history(history),
                                tools: toolbox.specs())
        let provider = ai.provider(model.provider)
        var rounds: [AIRound] = []
        do {
            loop: for _ in 0..<24 {
                let step = try await provider.step(request, rounds: rounds) { delta in
                    edit { $0.text += delta }
                }
                switch step.stop {
                case .tools:
                    var results: [AIToolResult] = []
                    for call in step.calls {
                        try Task.checkCancellation()
                        if toolbox.needsApproval(call), !trusted.contains(threadID) {
                            let answer = await ask(call, toolbox: toolbox, thread: threadID)
                            try Task.checkCancellation()
                            if answer == .deny {
                                results.append(AIToolResult(callID: call.id, name: call.name,
                                                            text: "The user declined this action. Do not try it again; ask what they would like instead.", isError: true))
                                edit { $0.activity.append(ToolActivity(tool: call.name, summary: toolbox.summary(of: call), status: .denied)) }
                                continue
                            }
                        }
                        let (result, activity) = await toolbox.run(call)
                        results.append(result)
                        withAnimation(Motion.snappy) { edit { $0.activity.append(activity) } }
                    }
                    rounds.append(AIRound(raw: step.raw, calls: step.calls, results: results))
                    edit { if !$0.text.isEmpty, !$0.text.hasSuffix("\n\n") { $0.text += "\n\n" } }
                case .maxTokens:
                    edit { $0.error = L("The reply was cut off at the length limit.", "답변이 길이 제한에서 끊겼어요.") }
                    break loop
                case .refusal(let why):
                    edit { $0.error = L("The model declined this request.", "모델이 이 요청을 거절했어요.") + (why.isEmpty ? "" : " (\(why))") }
                    break loop
                case .end:
                    break loop
                }
            }
        } catch {
            let stopped = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
            edit { $0.error = stopped ? L("Stopped.", "중지했어요.") : AIError.describe(error) }
        }
        edit { message in
            message.text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = "[\(model.label)]"
            if message.text.hasPrefix(label) { message.text = String(message.text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces) }
            if message.text.isEmpty, message.activity.isEmpty, message.error == nil {
                message.error = L("The model sent an empty reply.", "모델이 빈 답변을 보냈어요.")
            }
        }
    }
}
