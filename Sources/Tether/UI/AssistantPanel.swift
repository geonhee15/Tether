import SwiftUI

/// Round mark for a model's service.
struct ProviderBadge: View {
    var provider: AIProviderKind
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [provider.color, provider.color.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
    }
}

/// The assistant beside the page: one conversation that any connected model can continue,
/// with the Space, its nodes and a common memory shared between them.
struct AssistantPanel: View {
    let space: SpaceModel

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(AIStore.self) private var ai
    @Environment(AIEngine.self) private var engine
    @Environment(\.colorScheme) private var scheme
    @State private var draft = ""
    @State private var skill: AISkill?
    @State private var showMemory = false
    @FocusState private var composing: Bool

    static let width: CGFloat = 352

    private var thread: ChatThread? { ai.activeThread(in: space.id) }
    private var isBusy: Bool { thread.map { engine.busy.contains($0.id) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header
            modelBar
            Rectangle().fill(Theme.cardStroke(scheme)).frame(height: 1)
            if let thread, !thread.messages.isEmpty {
                transcript(thread)
            } else {
                emptyState
            }
            if let pending = engine.approval, pending.thread == thread?.id {
                ApprovalCard(pending: pending)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer
        }
        .frame(width: Self.width)
        .glass(radius: 20, frost: 0.72)
        .padding(.trailing, 10)
        .padding(.bottom, 4)
        .onAppear {
            ai.refreshAll()
            composing = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                let threads = ai.threads(in: space.id).filter { !$0.messages.isEmpty }
                if threads.isEmpty {
                    Text(L("No conversations yet", "아직 대화가 없어요"))
                }
                ForEach(threads) { item in
                    Button {
                        ai.selectThread(item.id, in: space.id)
                    } label: {
                        if item.id == thread?.id {
                            Label(item.title.isEmpty ? L("Untitled", "제목 없음") : item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title.isEmpty ? L("Untitled", "제목 없음") : item.title)
                        }
                    }
                }
                if let thread, !thread.messages.isEmpty {
                    Divider()
                    Button(L("Delete This Conversation", "이 대화 삭제"), role: .destructive) {
                        engine.stop(thread.id)
                        withAnimation(Motion.spring) { ai.deleteThread(thread.id, in: space.id) }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(thread.flatMap { $0.title.isEmpty ? nil : $0.title } ?? L("New conversation", "새 대화"))
                        .font(.app(13, .semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(L("Conversations in this Space", "이 Space의 대화"))
            Spacer(minLength: 4)
            IconButton(symbol: "brain", size: 12, active: showMemory, help: L("Shared memory — what every model knows", "공유 메모리 — 모든 모델이 함께 아는 것")) {
                showMemory.toggle()
            }
            .popover(isPresented: $showMemory, arrowEdge: .bottom) {
                if let account = store.owner(of: space.id) { MemoryList(accountID: account.id) }
            }
            IconButton(symbol: "square.and.pencil", size: 12, help: L("New conversation", "새 대화")) {
                withAnimation(Motion.spring) { _ = ai.newThread(in: space.id) }
                composing = true
            }
            IconButton(symbol: "xmark", size: 11, help: L("Close  ⌘J", "닫기  ⌘J")) {
                withAnimation(Motion.spring) { ai.settings.panelOpen = false }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.top, 8)
    }

    /// Which model answers next. Switching it mid-conversation is the point: the next model
    /// reads everything said so far.
    private var modelBar: some View {
        let active = ai.activeModel
        return HStack(spacing: 6) {
            Menu {
                ForEach(AIProviderKind.allCases) { kind in
                    let models = ai.models[kind] ?? []
                    Section(kind.title) {
                        if ai.isReady(kind) {
                            ForEach(models.prefix(24)) { model in
                                Button {
                                    ai.settings.selected = model
                                } label: {
                                    if model.id == active?.id { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                                }
                            }
                        } else {
                            Button(L("Connect \(kind.title)…", "\(kind.title) 연결하기…")) { ui.showSettings(.ai) }
                        }
                    }
                }
                Divider()
                Button(L("AI Settings…", "AI 설정…")) { ui.showSettings(.ai) }
            } label: {
                HStack(spacing: 7) {
                    if let active {
                        ProviderBadge(provider: active.provider, size: 18)
                        Text(active.label).font(.app(12, .medium)).lineLimit(1)
                    } else {
                        Image(systemName: "bolt.horizontal.circle").font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(L("No model connected", "연결된 모델 없음")).font(.app(12, .medium)).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chipFill(scheme)))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Choose the model that answers next", "다음 답변을 맡을 모델 선택"))
            Spacer(minLength: 0)
            permissionMenu
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var permissionMenu: some View {
        let current = ai.settings.permission
        return Menu {
            ForEach(AIPermission.allCases) { option in
                Button {
                    ai.settings.permission = option
                } label: {
                    if option == current { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current.symbol).font(.system(size: 10, weight: .semibold))
                Text(current.shortTitle).font(.app(11, .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("What models may do to your nodes", "모델이 노드에 할 수 있는 일"))
    }

    // MARK: Transcript

    private func transcript(_ thread: ChatThread) -> some View {
        let streaming = engine.streaming[thread.id]
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(thread.messages) { message in
                        MessageView(message: message, space: space, streaming: message.id == streaming)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.messages.last?.text.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.messages.last?.activity.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.messages.count) { _, _ in withAnimation(Motion.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: thread.id) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: engine.approval) { _, _ in withAnimation(Motion.smooth) { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                if ai.readyProviders.isEmpty {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                        .padding(.top, 30)
                    Text(L("Connect a model", "모델을 연결하세요")).font(.app(15, .bold))
                    Text(L("Claude, ChatGPT, Gemini or a local model on this Mac. They share this Space, its nodes and one memory, so you can switch between them in the same conversation.",
                           "Claude, ChatGPT, Gemini 또는 이 Mac의 로컬 모델을 연결하세요. 이 Space와 노드, 하나의 메모리를 함께 쓰기 때문에 같은 대화 안에서 모델을 바꿔 가며 이야기할 수 있어요."))
                        .font(.app(12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { ui.showSettings(.ai) } label: {
                        Label(L("Connect…", "연결하기…"), systemImage: "link")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    HStack(spacing: -6) {
                        ForEach(ai.readyProviders) { ProviderBadge(provider: $0, size: 30).overlay(Circle().strokeBorder(.background.opacity(0.6), lineWidth: 1.5)) }
                    }
                    .padding(.top, 26)
                    Text(L("Work on this Space together", "이 Space를 함께 다듬어요")).font(.app(15, .bold))
                    Text(L("Ask about your nodes, or have them changed for you. Whichever model answers sees the same nodes, conversations and memory.",
                           "노드에 대해 묻거나 대신 고쳐 달라고 해 보세요. 어떤 모델이 답하든 같은 노드와 대화, 메모리를 봐요."))
                        .font(.app(12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 6) {
                        ForEach(ai.settings.skills.prefix(4)) { item in
                            Button {
                                engine.send(L("Run the skill “\(item.name)”.", "‘\(item.name)’ 스킬을 실행해 줘."), skill: item, in: space)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).font(.app(12.5, .semibold))
                                        Text(item.summary).font(.app(11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .card(radius: 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hoverLift(1.015)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let node = space.activeNode {
                    let included = ai.settings.includeOpenNode
                    Button {
                        ai.settings.includeOpenNode.toggle()
                    } label: {
                        Chip(text: node.displayTitle, symbol: included ? node.symbol : "eye.slash", tint: included ? Theme.accent : nil)
                    }
                    .buttonStyle(.plain)
                    .help(included ? L("The open node is sent with your message. Click to leave it out.", "열린 노드가 메시지와 함께 전달돼요. 누르면 빼요.")
                                   : L("The open node is not sent. Click to include it.", "열린 노드는 전달되지 않아요. 누르면 포함해요."))
                }
                if let skill {
                    Button { self.skill = nil } label: {
                        Chip(text: skill.name, symbol: "wand.and.stars", tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help(L("Click to remove the skill", "누르면 스킬을 빼요"))
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    if ai.settings.skills.isEmpty { Text(L("No skills yet", "아직 스킬이 없어요")) }
                    ForEach(ai.settings.skills) { item in
                        Button(item.name) { skill = item }
                    }
                    Divider()
                    Button(L("Edit Skills…", "스킬 편집…")) { ui.showSettings(.ai) }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(skill == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                        .frame(width: 30, height: 34)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Use a skill for this message", "이 메시지에 스킬 사용"))

                TextField(ai.activeModel.map { L("Message \($0.provider.title)…", "\($0.provider.title)에게 메시지…") } ?? L("Connect a model to start", "모델을 연결하면 시작할 수 있어요"),
                          text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(13))
                    .lineLimit(1...7)
                    .focused($composing)
                    .onSubmit(send)
                    .padding(.vertical, 8)
                    .disabled(ai.activeModel == nil)

                if isBusy, let thread {
                    Button { engine.stop(thread.id) } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Stop", "중지"))
                    .padding(.bottom, 3)
                } else {
                    let ready = ai.activeModel != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(ready ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary.opacity(0.35))))
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready)
                    .help(L("Send  ↩", "보내기  ↩"))
                    .padding(.bottom, 3)
                }
            }
            .padding(.leading, 2)
            .padding(.trailing, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.fieldFill(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(composing ? Theme.accent.opacity(0.6) : Theme.cardStroke(scheme), lineWidth: composing ? 1.5 : 1))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(Motion.snappy, value: skill)
    }

    private func send() {
        guard !isBusy, engine.send(draft, skill: skill, in: space) != nil else { return }
        draft = ""
        skill = nil
    }
}

extension AIPermission {
    @MainActor var title: String {
        switch self {
        case .readOnly: return L("Read only — models can't change nodes", "읽기만 — 모델이 노드를 바꾸지 못해요")
        case .ask: return L("Ask before each edit", "수정하기 전에 매번 물어보기")
        case .auto: return L("Edit freely (⌘Z still undoes)", "바로 수정 (⌘Z로 되돌릴 수 있어요)")
        }
    }

    @MainActor var shortTitle: String {
        switch self {
        case .readOnly: return L("Read only", "읽기만")
        case .ask: return L("Ask first", "수정 전 확인")
        case .auto: return L("Edits freely", "바로 수정")
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: return "eye"
        case .ask: return "hand.raised"
        case .auto: return "bolt"
        }
    }
}

// MARK: Messages

private struct MessageView: View {
    let message: ChatMessage
    let space: SpaceModel
    var streaming: Bool

    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .font(.app(13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(scheme == .dark ? 0.28 : 0.15)))
                    .frame(maxWidth: 270, alignment: .trailing)
                if let skill = message.skill {
                    Label(skill, systemImage: "wand.and.stars").font(.app(10.5)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if let model = message.model { ProviderBadge(provider: model.provider, size: 16) }
                    Text(message.model?.label ?? L("Assistant", "어시스턴트")).font(.app(11, .semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if hovering, !streaming, !message.text.isEmpty { actions.transition(.opacity) }
                }
                .frame(height: 18)
                if !message.text.isEmpty {
                    MarkdownText(text: message.text)
                }
                if streaming, message.text.isEmpty, message.activity.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("Thinking…", "생각하는 중…")).font(.app(12)).foregroundStyle(.secondary)
                    }
                }
                if !message.activity.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.activity) { activity in ActivityRow(activity: activity, space: space) }
                    }
                    .padding(.top, 1)
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(11.5))
                        .foregroundStyle(Theme.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(Motion.snappy, value: hovering)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if let node = space.activeNode {
                IconButton(symbol: "text.append", size: 10.5, side: 20,
                           help: L("Add this reply to “\(node.displayTitle)”", "이 답변을 “\(node.displayTitle)”에 추가")) {
                    if NodeReader.append(message.text, to: node) {
                        ui.flash(L("Added to the node", "노드에 추가했어요"), symbol: "text.append")
                    }
                }
            }
            IconButton(symbol: copied ? "checkmark" : "doc.on.doc", size: 10.5, side: 20, help: L("Copy", "복사")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            }
        }
    }
}

/// One thing a model did, with a way to go and look at it.
private struct ActivityRow: View {
    let activity: ToolActivity
    let space: SpaceModel
    @Environment(\.colorScheme) private var scheme

    private var symbol: String {
        switch activity.status {
        case .failed: return "exclamationmark.circle"
        case .denied: return "hand.raised.slash"
        case .done: return activity.changedContent ? "pencil.line" : (activity.tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "eye")
        }
    }

    var body: some View {
        let target = activity.nodeID.flatMap { space.node($0) }
        Button {
            if let target { withAnimation(Motion.spring) { space.open(target.id) } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activity.status == .done && activity.changedContent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 14)
                Text(activity.summary + (activity.status == .denied ? L(" — declined", " — 거절함") : activity.status == .failed ? L(" — failed", " — 실패") : ""))
                    .font(.app(11.5))
                    .foregroundStyle(activity.status == .done ? .secondary : .tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if target != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.chipFill(scheme)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .help(target == nil ? "" : L("Open the node", "노드 열기"))
    }
}

/// A model wants to change something and the user allows one edit at a time.
private struct ApprovalCard: View {
    let pending: AIEngine.PendingApproval
    @Environment(AIEngine.self) private var engine
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("Allow this edit?", "이 수정을 허용할까요?"), systemImage: "hand.raised.fill")
                .font(.app(11, .semibold)).foregroundStyle(Theme.accent)
            Text(pending.title).font(.app(12.5, .semibold)).fixedSize(horizontal: false, vertical: true)
            if !pending.detail.isEmpty {
                MarkdownText(text: pending.detail)
                    .lineLimit(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.embedFill(scheme)))
            }
            HStack(spacing: 6) {
                // No keyboard shortcuts here: Return belongs to the composer, so an edit is only allowed by a click.
                Button(L("Decline", "거절")) { engine.answer(.deny) }
                    .buttonStyle(SoftButtonStyle())
                Button(L("Always in this chat", "이 대화에서 항상")) { engine.answer(.allowAll) }
                    .buttonStyle(SoftButtonStyle())
                Spacer(minLength: 0)
                Button { engine.answer(.allow) } label: { Text(L("Allow", "허용")).padding(.horizontal, 4) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(12)
        .card(radius: 14)
    }
}

/// The facts every model is given. The user can add, correct and remove them.
private struct MemoryList: View {
    let accountID: UUID
    @Environment(AIStore.self) private var ai
    @Environment(\.colorScheme) private var scheme
    @State private var draft = ""

    var body: some View {
        let items = ai.memory(for: accountID)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Shared memory", "공유 메모리")).font(.app(13, .semibold))
                Text(L("Claude, ChatGPT, Gemini and local models all read this. Models add to it when they learn something lasting.",
                       "Claude, ChatGPT, Gemini, 로컬 모델이 모두 읽어요. 오래 쓸 만한 것을 알게 되면 모델이 스스로 추가하기도 해요."))
                    .font(.app(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if items.isEmpty {
                Text(L("Nothing saved yet.", "아직 저장된 것이 없어요.")).font(.app(12)).foregroundStyle(.tertiary).padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text).font(.app(12)).fixedSize(horizontal: false, vertical: true)
                                    Text((item.author.isEmpty ? L("You", "나") : item.author) + " · " + formatDate(item.date, date: .abbreviated, time: .omitted))
                                        .font(.app(10.5)).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 4)
                                IconButton(symbol: "xmark", size: 9, side: 20, help: L("Forget", "잊기")) {
                                    withAnimation(Motion.snappy) { ai.forget(item.id, for: accountID) }
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chipFill(scheme)))
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            GlassField(symbol: "plus", placeholder: L("Add something to remember", "기억해 둘 것 추가"), text: $draft) {
                if ai.remember(draft, author: "", for: accountID) != nil { draft = "" }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// A model's reply: light Markdown (headings, lists, bold, italic, code) drawn in the interface font.
struct MarkdownText: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    private enum Piece: Identifiable {
        case prose(Int, AttributedString)
        case code(Int, String)
        var id: Int {
            switch self {
            case .prose(let index, _), .code(let index, _): return index
            }
        }
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var prose: [String] = []
        var code: [String]?
        func flush() {
            guard !prose.isEmpty else { return }
            result.append(.prose(result.count, Self.attributed(prose)))
            prose = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = code {
                    result.append(.code(result.count, open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else {
                prose.append(line)
            }
        }
        if let open = code { result.append(.code(result.count, open.joined(separator: "\n"))) }
        flush()
        return result
    }

    private static func attributed(_ lines: [String]) -> AttributedString {
        var out = AttributedString()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        for (index, raw) in lines.enumerated() {
            var line = raw
            var size: CGFloat = 13
            var bold = false
            for (marker, points) in [("### ", CGFloat(13.5)), ("## ", 14.5), ("# ", 15.5)] where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count))
                size = points
                bold = true
                break
            }
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                line = String(repeating: " ", count: line.count - trimmed.count) + "•  " + trimmed.dropFirst(2)
            }
            var piece = (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
            if bold { piece.font = .app(size, .bold) }
            out.append(piece)
            if index < lines.count - 1 { out.append(AttributedString("\n")) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pieces) { piece in
                switch piece {
                case .prose(_, let content):
                    Text(content)
                        .font(.app(13))
                        .lineSpacing(3.5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let content):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(content)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.embedFill(scheme)))
                }
            }
        }
    }
}
