import Foundation
import PDFKit
import SwiftUI

/// Turns what a model writes (light Markdown) into the runs a node stores.
enum MarkdownRuns {
    static func runs(from text: String) -> [TextRun] {
        var result: [TextRun] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            var line = raw
            var size: Double?
            var heading = false
            for (marker, preset) in [("### ", TextPreset.subheading), ("## ", .heading), ("# ", .title)] where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count))
                size = preset == .title ? TextPreset.heading.size : preset.size
                heading = true
                break
            }
            if !heading {
                let trimmed = line.drop { $0 == " " }
                let indent = String(repeating: " ", count: line.count - trimmed.count)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { line = indent + "• " + trimmed.dropFirst(2) }
            }
            var pieces = inline(line)
            if heading { pieces = pieces.map { var run = $0; run.b = true; run.z = size; return run } }
            if index < lines.count - 1 {
                if pieces.isEmpty { pieces = [TextRun(t: "\n")] } else { pieces[pieces.count - 1].t += "\n" }
            }
            result.append(contentsOf: pieces)
        }
        return merged(result)
    }

    /// `**bold**`, `*italic*`, `_italic_` and `~~strike~~` inside one line.
    private static func inline(_ line: String) -> [TextRun] {
        var runs: [TextRun] = []
        var buffer = ""
        var bold = false, italic = false, strike = false
        let chars = Array(line)
        var i = 0
        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(TextRun(t: buffer, b: bold ? true : nil, i: italic ? true : nil, s: strike ? true : nil))
            buffer = ""
        }
        func closes(_ marker: [Character], from start: Int) -> Bool {
            guard start + marker.count <= chars.count else { return false }
            var j = start
            while j + marker.count <= chars.count {
                if Array(chars[j..<(j + marker.count)]) == marker { return true }
                j += 1
            }
            return false
        }
        while i < chars.count {
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if chars[i] == "*", next == "*", bold || closes(["*", "*"], from: i + 2) {
                flush(); bold.toggle(); i += 2
            } else if chars[i] == "~", next == "~", strike || closes(["~", "~"], from: i + 2) {
                flush(); strike.toggle(); i += 2
            } else if chars[i] == "*", next != " ", italic || closes(["*"], from: i + 1) {
                flush(); italic.toggle(); i += 1
            } else {
                buffer.append(chars[i]); i += 1
            }
        }
        flush()
        return runs
    }

    static func merged(_ runs: [TextRun]) -> [TextRun] {
        var result: [TextRun] = []
        for run in runs where !run.t.isEmpty {
            if let last = result.last, last.sameStyle(as: run) {
                result[result.count - 1].t += run.t
            } else {
                result.append(run)
            }
        }
        return result
    }

    /// Replaces a UTF-16 range of the text held in `runs`, keeping the style at the start of the range.
    static func replacing(_ range: NSRange, in runs: [TextRun], with replacement: String) -> [TextRun] {
        var result: [TextRun] = []
        var offset = 0
        var inserted = false
        for run in runs {
            let text = run.t as NSString
            let start = offset, end = offset + text.length
            offset = end
            if end <= range.location || start >= range.location + range.length {
                if !inserted, start >= range.location + range.length {
                    var piece = run; piece.t = replacement
                    result.append(piece); inserted = true
                }
                result.append(run)
                continue
            }
            if start < range.location {
                var head = run; head.t = text.substring(to: range.location - start)
                result.append(head)
            }
            if !inserted {
                var piece = run; piece.t = replacement
                result.append(piece); inserted = true
            }
            if end > range.location + range.length {
                var tail = run; tail.t = text.substring(from: range.location + range.length - start)
                result.append(tail)
            }
        }
        if !inserted { result.append(TextRun(t: replacement)) }
        return merged(result)
    }
}

/// A node written out as text for a model to read.
@MainActor
enum NodeReader {
    static func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    static func line(for node: NodeModel, in space: SpaceModel) -> String {
        var parts = ["[\(shortID(node.id))] \(node.displayTitle)"]
        parts.append(node.isFile ? "file (\(node.file?.summary ?? ""))" : "node, \(node.wordCount) words")
        if let category = space.category(of: node) { parts.append("category: \(category.name)") }
        let embeds = node.embedKinds.map(\.rawValue)
        if !embeds.isEmpty { parts.append("contains: " + embeds.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    static func text(of node: NodeModel, in space: SpaceModel, store: Store, limit: Int = 24_000) -> String {
        var out = "# \(node.displayTitle)\n"
        out += "id: \(shortID(node.id))"
        if let category = space.category(of: node) { out += " · category: \(category.name)" }
        out += "\n"
        let linked = space.links(touching: Anchor(nodeID: node.id, blockID: nil)).map { space.title(for: $0.other) }
        if !linked.isEmpty { out += "linked to: " + linked.joined(separator: "; ") + "\n" }
        if let file = node.file {
            out += "\nThis node is a file: \(file.originalName) (\(file.summary)).\n"
            let extracted = fileText(file, in: space, store: store)
            out += extracted.isEmpty ? "(Its contents can't be read as text.)\n" : "\n--- file contents ---\n" + extracted + "\n--- end of file ---\n"
            out += "\nNotes written beside the file:\n"
        } else {
            out += "\n"
        }
        for block in node.blocks {
            switch block.data.kind {
            case .text:
                let text = block.plainText
                if !text.isEmpty { out += text + "\n" }
            case .table:
                guard let table = block.data.table else { continue }
                out += "\n[Table" + (table.title.isEmpty ? "" : ": \(table.title)") + "]\n"
                for row in table.rows { out += "| " + row.map(\.text).joined(separator: " | ") + " |\n" }
                out += "\n"
            case .chart:
                guard let chart = block.data.chart else { continue }
                out += "\n[\(chart.style.rawValue.capitalized) chart" + (chart.title.isEmpty ? "" : ": \(chart.title)") + "]\n"
                for point in chart.points {
                    let extra = space.linkedDelta(for: ValueRef(nodeID: node.id, blockID: block.id, itemID: point.id))
                    out += "- \(point.label): \(formatNumber(point.value + extra))"
                    if extra != 0 { out += " (base \(formatNumber(point.value)), \(formatDelta(extra)) from linked actions)" }
                    out += "\n"
                }
                out += "\n"
            case .analytics:
                guard let analytics = block.data.analytics else { continue }
                let score = space.score(of: block, in: node)
                out += "\n[Analytics: \(analytics.name)" + (analytics.relation.isEmpty ? "" : " — \(analytics.relation)") + "]\n"
                out += "score \(formatNumber(score.value))/100 (if every action is finished: \(formatNumber(score.projected)))\n"
                if !analytics.traits.isEmpty { out += "traits: " + analytics.traits.map(\.text).joined(separator: ", ") + "\n" }
                if !analytics.likes.isEmpty { out += "likes: " + analytics.likes.map(\.text).joined(separator: ", ") + "\n" }
                if !analytics.cautions.isEmpty { out += "cautions: " + analytics.cautions.map(\.text).joined(separator: ", ") + "\n" }
                if !analytics.attitude.isEmpty { out += "attitude: \(analytics.attitude)\n" }
                for entry in analytics.observations {
                    out += "- observed (\(entry.impact > 0 ? "positive" : entry.impact < 0 ? "negative" : "neutral")): \(entry.text)\n"
                }
                for action in analytics.actions {
                    out += "- action: \(action.title) — \(action.progress)/\(action.target)\(action.isDone ? " done" : "")\n"
                }
                out += "\n"
            }
        }
        if out.count > limit { out = String(out.prefix(limit)) + "\n…(cut here: the node is longer than what fits)" }
        return out
    }

    /// Text inside a stored file, for the kinds that have any.
    static func fileText(_ file: FileAttachment, in space: SpaceModel, store: Store, limit: Int = 16_000) -> String {
        let url = store.fileURL(for: file, in: space)
        var text = ""
        switch file.category {
        case .pdf:
            text = PDFDocument(url: url)?.string ?? ""
        case .text, .code:
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        case .spreadsheet where ["csv", "tsv"].contains(file.fileExtension):
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        default:
            break
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) + "\n…(cut here)" : text
    }

    /// Adds text (light Markdown) to the end of a node's page, or of a file node's notes.
    @discardableResult
    static func append(_ text: String, to node: NodeModel) -> Bool {
        let addition = MarkdownRuns.runs(from: text)
        guard !addition.isEmpty else { return false }
        let target: BlockModel
        if let last = node.blocks.last, last.data.kind == .text {
            target = last
        } else {
            target = BlockModel(Block(kind: .text))
            node.blocks.append(target)
        }
        var runs = target.data.runs ?? []
        if !runs.isEmpty, runs.last?.t.hasSuffix("\n") == false { runs.append(TextRun(t: "\n")) }
        target.data.runs = MarkdownRuns.merged(runs + addition)
        target.revision += 1
        return true
    }

    /// Finds a node from whatever a model passed: its short id, its full id, or its title.
    static func find(_ reference: String, in space: SpaceModel) -> NodeModel? {
        let wanted = reference.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]\"")))
        guard !wanted.isEmpty else { return nil }
        let lower = wanted.lowercased()
        if let exact = space.nodes.first(where: { $0.id.uuidString.lowercased() == lower }) { return exact }
        if lower.count >= 6 {
            let byPrefix = space.nodes.filter { $0.id.uuidString.lowercased().hasPrefix(lower) }
            if byPrefix.count == 1 { return byPrefix[0] }
        }
        if let byTitle = space.nodes.first(where: { $0.title.caseInsensitiveCompare(wanted) == .orderedSame }) { return byTitle }
        let containing = space.nodes.filter { $0.title.lowercased().contains(lower) }
        return containing.count == 1 ? containing[0] : nil
    }
}

/// The tools a model is given, and what happens when it calls one. Edits go straight into the
/// observed Space model, so they are autosaved and ⌘Z undoes them like anything typed by hand.
@MainActor
struct AIToolbox {
    let space: SpaceModel
    let store: Store
    let ai: AIStore
    let account: Account
    let threadID: UUID
    let model: AIModelRef
    let mcp: MCPHub

    // MARK: Definitions

    private static func schema(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

    private static let nodeArgument = string("The node: its short id from list_nodes (best), or its exact title.")

    static let builtIn: [AIToolSpec] = [
        AIToolSpec(name: "list_nodes",
                   description: "List every node and file in a Space with its id, kind, category and size. Call this to find out what exists before reading or editing.",
                   schema: schema(["space": string("Name of another Space of the same account to list instead of the current one. Leave out for the current Space.")])),
        AIToolSpec(name: "read_node",
                   description: "Read one node in full: its text, tables, charts (with linked values applied), analytics cards and links. For a file node this returns the file's text when it has any (PDF, plain text, code, CSV) and the notes beside it.",
                   schema: schema(["node": nodeArgument,
                                   "space": string("Name of another Space of the same account to read from. Leave out for the current Space.")], required: ["node"])),
        AIToolSpec(name: "search",
                   description: "Search the current Space: node text, earlier conversations with any model, and the shared memory. Returns the best matches with a snippet each.",
                   schema: schema(["query": string("Words to look for."),
                                   "all_spaces": ["type": "boolean", "description": "Also search the account's other Spaces (nodes only)."]], required: ["query"])),
        AIToolSpec(name: "list_spaces",
                   description: "List the Spaces of this account with how many nodes each has.",
                   schema: schema([:])),
        AIToolSpec(name: "list_chats",
                   description: "List the conversations kept in this Space (with any model), newest first.",
                   schema: schema([:])),
        AIToolSpec(name: "read_chat",
                   description: "Read an earlier conversation from this Space, whichever model it was with.",
                   schema: schema(["chat": string("The conversation's short id from list_chats, or its title.")], required: ["chat"])),
        AIToolSpec(name: "create_node",
                   description: "Create a new node in the current Space. The text may use light Markdown: #/##/### headings, **bold**, *italic*, ~~strike~~ and '- ' bullets.",
                   schema: schema(["title": string("Title of the node."),
                                   "text": string("The node's text."),
                                   "category": string("Name of a category to file it under; it is created if it doesn't exist. Leave out for none.")], required: ["title"]),
                   writes: true),
        AIToolSpec(name: "append_to_node",
                   description: "Add text to the end of a node (for a file node: to its notes). Same light Markdown as create_node. Use this rather than rewriting a node.",
                   schema: schema(["node": nodeArgument, "text": string("Text to add.")], required: ["node", "text"]),
                   writes: true),
        AIToolSpec(name: "replace_in_node",
                   description: "Replace one exact passage of a node's text with new text. `find` must match the node's text exactly (read the node first); only the first match is replaced. Use an empty `replace` to delete the passage.",
                   schema: schema(["node": nodeArgument,
                                   "find": string("The exact existing text to replace."),
                                   "replace": string("What to put in its place.")], required: ["node", "find", "replace"]),
                   writes: true),
        AIToolSpec(name: "rename_node",
                   description: "Change a node's title.",
                   schema: schema(["node": nodeArgument, "title": string("The new title.")], required: ["node", "title"]),
                   writes: true),
        AIToolSpec(name: "set_category",
                   description: "File a node under a category of this Space (created if it doesn't exist), or pass an empty category to unfile it.",
                   schema: schema(["node": nodeArgument, "category": string("Category name, or an empty string for none.")], required: ["node", "category"]),
                   writes: true),
        AIToolSpec(name: "add_table",
                   description: "Add a table at the end of a node.",
                   schema: schema(["node": nodeArgument,
                                   "title": string("Title shown above the table."),
                                   "rows": ["type": "array", "description": "Rows of cell text; the first row is the header.",
                                            "items": ["type": "array", "items": ["type": "string"]]]], required: ["node", "rows"]),
                   writes: true),
        AIToolSpec(name: "add_chart",
                   description: "Add a pie, bar or line chart at the end of a node.",
                   schema: schema(["node": nodeArgument,
                                   "title": string("Title shown above the chart."),
                                   "style": ["type": "string", "enum": ["pie", "bar", "line"], "description": "Kind of chart."],
                                   "points": ["type": "array", "description": "The values to plot, in order.",
                                              "items": ["type": "object",
                                                        "properties": ["label": ["type": "string"], "value": ["type": "number"]],
                                                        "required": ["label", "value"]]]], required: ["node", "style", "points"]),
                   writes: true),
        AIToolSpec(name: "add_link",
                   description: "Link two nodes of this Space to each other (a two-way “see also”).",
                   schema: schema(["from": nodeArgument, "to": nodeArgument], required: ["from", "to"]),
                   writes: true),
        AIToolSpec(name: "remember",
                   description: "Save a lasting fact to the memory shared by every model the user talks to in Tether (Claude, ChatGPT, Gemini, local). Use it for preferences, decisions and facts worth knowing in later conversations — not for things already written in a node.",
                   schema: schema(["text": string("One self-contained sentence.")], required: ["text"])),
        AIToolSpec(name: "use_skill",
                   description: "Load the full instructions of one of the user's skills (listed in the system prompt) before carrying it out.",
                   schema: schema(["name": string("The skill's name.")], required: ["name"])),
    ]

    /// The tools offered for this turn: built-in ones (without the editing ones when the user
    /// allows reading only) plus whatever the connected MCP servers provide.
    func specs() -> [AIToolSpec] {
        let readOnly = ai.settings.permission == .readOnly
        return (Self.builtIn + mcp.tools).filter { !readOnly || !$0.writes }
    }

    func needsApproval(_ call: AIToolCall) -> Bool {
        guard ai.settings.permission == .ask else { return false }
        return (Self.builtIn + mcp.tools).first { $0.name == call.name }?.writes ?? true
    }

    // MARK: Describing a call

    private func arg(_ call: AIToolCall, _ name: String) -> String {
        guard let value = call.input?[name] else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private func nodeName(_ reference: String) -> String {
        NodeReader.find(reference, in: space)?.displayTitle ?? reference
    }

    /// One line saying what a call does, shown on the approval card and in the transcript.
    func summary(of call: AIToolCall) -> String {
        let node = "“\(nodeName(arg(call, "node")))”"
        switch call.name {
        case "list_nodes": return L("Looked through the nodes", "노드 목록을 살펴봄")
        case "read_node": return L("Read \(node)", "\(node) 읽음")
        case "search": return L("Searched for “\(arg(call, "query"))”", "“\(arg(call, "query"))” 검색")
        case "list_spaces": return L("Looked at the Spaces", "Space 목록을 살펴봄")
        case "list_chats": return L("Looked at earlier conversations", "이전 대화 목록을 살펴봄")
        case "read_chat": return L("Read an earlier conversation", "이전 대화를 읽음")
        case "create_node": return L("Create the node “\(arg(call, "title"))”", "“\(arg(call, "title"))” 노드 만들기")
        case "append_to_node": return L("Add text to \(node)", "\(node)에 글 추가")
        case "replace_in_node": return L("Edit a passage in \(node)", "\(node)의 글 일부 수정")
        case "rename_node": return L("Rename \(node) to “\(arg(call, "title"))”", "\(node)의 제목을 “\(arg(call, "title"))”(으)로 변경")
        case "set_category":
            let category = arg(call, "category")
            return category.isEmpty ? L("Unfile \(node)", "\(node)을(를) 미분류로") : L("File \(node) under “\(category)”", "\(node)을(를) “\(category)”에 넣기")
        case "add_table": return L("Add a table to \(node)", "\(node)에 표 추가")
        case "add_chart": return L("Add a chart to \(node)", "\(node)에 그래프 추가")
        case "add_link": return L("Link “\(nodeName(arg(call, "from")))” and “\(nodeName(arg(call, "to")))”", "“\(nodeName(arg(call, "from")))”와(과) “\(nodeName(arg(call, "to")))” 연결")
        case "remember": return L("Saved to shared memory", "공유 메모리에 저장")
        case "use_skill": return L("Used the skill “\(arg(call, "name"))”", "“\(arg(call, "name"))” 스킬 사용")
        default:
            if let tool = mcp.display(call.name) { return L("\(tool.server): \(tool.tool)", "\(tool.server): \(tool.tool)") }
            return call.name
        }
    }

    /// The part of a call worth showing before it is approved (the text to be written).
    func detail(of call: AIToolCall) -> String {
        switch call.name {
        case "create_node", "append_to_node": return arg(call, "text")
        case "replace_in_node": return "− " + arg(call, "find") + "\n+ " + arg(call, "replace")
        case "remember": return arg(call, "text")
        default: return call.name.hasPrefix("mcp__") ? call.rawInput : ""
        }
    }

    // MARK: Running a call

    func run(_ call: AIToolCall) async -> (AIToolResult, ToolActivity) {
        var activity = ToolActivity(tool: call.name, summary: summary(of: call))
        func finish(_ text: String, error: Bool = false) -> (AIToolResult, ToolActivity) {
            if error { activity.status = .failed }
            return (AIToolResult(callID: call.id, name: call.name, text: text, isError: error), activity)
        }
        guard call.input != nil else {
            // The model produced arguments that are not valid JSON; say so in a form it can act on.
            return finish(AIHTTP.string(["INVALID_JSON": call.rawInput]), error: true)
        }
        if call.name.hasPrefix("mcp__") {
            do {
                return finish(try await mcp.call(call.name, arguments: call.input ?? [:]))
            } catch {
                return finish("The tool failed: \(AIError.describe(error))", error: true)
            }
        }
        do {
            let text = try execute(call, activity: &activity)
            return finish(text)
        } catch let failure as ToolFailure {
            return finish(failure.message, error: true)
        } catch {
            return finish(error.localizedDescription, error: true)
        }
    }

    private struct ToolFailure: Error { let message: String }

    private func otherSpace(_ call: AIToolCall) throws -> SpaceModel {
        let name = arg(call, "space")
        guard !name.isEmpty, name.caseInsensitiveCompare(space.info.name) != .orderedSame else { return space }
        guard let match = store.spaces(of: account.id).first(where: { $0.info.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ToolFailure(message: "There is no Space named “\(name)”. Call list_spaces to see the names.")
        }
        return match
    }

    private func node(_ reference: String, in target: SpaceModel? = nil) throws -> NodeModel {
        guard let found = NodeReader.find(reference, in: target ?? space) else {
            throw ToolFailure(message: "No node matches “\(reference)”. Call list_nodes to get the ids.")
        }
        return found
    }

    private func execute(_ call: AIToolCall, activity: inout ToolActivity) throws -> String {
        switch call.name {
        case "list_nodes":
            let target = try otherSpace(call)
            guard !target.nodes.isEmpty else { return "The Space “\(target.info.name)” has no nodes yet." }
            let groups = target.categories.map { category in (category.name, target.nodes(in: category.id)) } + [("No category", target.nodes(in: nil))]
            var out = "Space “\(target.info.name)” — \(target.nodes.count) nodes\n"
            for (name, nodes) in groups where !nodes.isEmpty {
                if !target.categories.isEmpty { out += "\n\(name):\n" }
                for node in nodes { out += "- " + NodeReader.line(for: node, in: target) + "\n" }
            }
            return out

        case "read_node":
            let target = try otherSpace(call)
            let found = try node(arg(call, "node"), in: target)
            if target === space { activity.nodeID = found.id }
            activity.summary = L("Read “\(found.displayTitle)”", "“\(found.displayTitle)” 읽음")
            return NodeReader.text(of: found, in: target, store: store)

        case "search":
            return search(arg(call, "query"), everywhere: (call.input?["all_spaces"] as? Bool) ?? false)

        case "list_spaces":
            return store.spaces(of: account.id).map { item in
                "- \(item.info.name)\(item === space ? " (current)" : "")" + (item.info.subtitle.isEmpty ? "" : " — \(item.info.subtitle)") + " · \(item.nodes.count) nodes"
            }.joined(separator: "\n")

        case "list_chats":
            let threads = ai.threads(in: space.id).filter { !$0.messages.isEmpty }
            guard !threads.isEmpty else { return "No earlier conversations in this Space." }
            return threads.map { thread in
                let models = Set(thread.messages.compactMap { $0.model?.label }).sorted().joined(separator: ", ")
                return "- [\(NodeReader.shortID(thread.id))] \(thread.title.isEmpty ? "Untitled" : thread.title)\(thread.id == threadID ? " (this conversation)" : "") · \(thread.messages.count) messages · with \(models)"
            }.joined(separator: "\n")

        case "read_chat":
            let wanted = arg(call, "chat").lowercased()
            let threads = ai.threads(in: space.id)
            guard let thread = threads.first(where: { $0.id.uuidString.lowercased().hasPrefix(wanted) && wanted.count >= 6 })
                    ?? threads.first(where: { $0.title.lowercased() == wanted })
                    ?? threads.first(where: { !wanted.isEmpty && $0.title.lowercased().contains(wanted) }) else {
                throw ToolFailure(message: "No conversation matches “\(arg(call, "chat"))”. Call list_chats to get the ids.")
            }
            var out = "Conversation “\(thread.title)”\n"
            for message in thread.messages where !message.text.isEmpty {
                out += "\n" + (message.role == .user ? "User" : (message.model?.label ?? "Assistant")) + ": " + message.text + "\n"
            }
            return out.count > 24_000 ? String(out.suffix(24_000)) : out

        case "create_node":
            let title = arg(call, "title").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw ToolFailure(message: "A title is required.") }
            let category = arg(call, "category").trimmingCharacters(in: .whitespaces)
            let categoryID = category.isEmpty ? nil : self.category(named: category).id
            let runs = MarkdownRuns.runs(from: arg(call, "text"))
            let created = NodeModel(NodeDoc(title: title, symbol: "sparkles", blocks: [Block(kind: .text, runs: runs.isEmpty ? nil : runs)], categoryID: categoryID))
            withAnimation(Motion.spring) {
                space.nodes.append(created)
                space.openTabs.append(created.id)
            }
            activity.nodeID = created.id
            activity.changedContent = true
            activity.summary = L("Created the node “\(title)”", "“\(title)” 노드를 만듦")
            return "Created the node “\(title)” (id \(NodeReader.shortID(created.id)))."

        case "append_to_node":
            let found = try node(arg(call, "node"))
            guard NodeReader.append(arg(call, "text"), to: found) else { throw ToolFailure(message: "There is no text to add.") }
            activity.nodeID = found.id
            activity.changedContent = true
            activity.summary = L("Added text to “\(found.displayTitle)”", "“\(found.displayTitle)”에 글을 추가함")
            return "Added to “\(found.displayTitle)”."

        case "replace_in_node":
            let found = try node(arg(call, "node"))
            let find = arg(call, "find")
            guard !find.isEmpty else { throw ToolFailure(message: "`find` is empty.") }
            for block in found.blocks where block.data.kind == .text {
                let range = (block.plainText as NSString).range(of: find)
                guard range.location != NSNotFound else { continue }
                block.data.runs = MarkdownRuns.replacing(range, in: block.data.runs ?? [], with: arg(call, "replace"))
                block.revision += 1
                activity.nodeID = found.id
                activity.changedContent = true
                activity.summary = L("Edited “\(found.displayTitle)”", "“\(found.displayTitle)”을(를) 수정함")
                return "Replaced the passage in “\(found.displayTitle)”."
            }
            throw ToolFailure(message: "That exact text is not in “\(found.displayTitle)”. Read the node again and copy the passage exactly (text inside tables, charts and analytics cards can't be edited with this tool).")

        case "rename_node":
            let found = try node(arg(call, "node"))
            let title = arg(call, "title").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw ToolFailure(message: "A title is required.") }
            let before = found.displayTitle
            found.title = title
            activity.nodeID = found.id
            activity.changedContent = true
            activity.summary = L("Renamed “\(before)” to “\(title)”", "“\(before)”의 제목을 “\(title)”(으)로 바꿈")
            return "Renamed to “\(title)”."

        case "set_category":
            let found = try node(arg(call, "node"))
            let name = arg(call, "category").trimmingCharacters(in: .whitespaces)
            withAnimation(Motion.spring) { found.categoryID = name.isEmpty ? nil : category(named: name).id }
            activity.nodeID = found.id
            activity.changedContent = true
            return name.isEmpty ? "“\(found.displayTitle)” is no longer in a category." : "“\(found.displayTitle)” is now under “\(name)”."

        case "add_table":
            let found = try node(arg(call, "node"))
            guard !found.isFile else { throw ToolFailure(message: "A file node only holds notes; tables can't be added to it.") }
            let rows = (call.input?["rows"] as? [[Any]] ?? []).map { $0.map { "\($0)" } }
            let width = rows.map(\.count).max() ?? 0
            guard width > 0 else { throw ToolFailure(message: "`rows` is empty.") }
            let cells = rows.map { row in (0..<width).map { TableCell(text: $0 < row.count ? row[$0] : "") } }
            insert(Block(kind: .table, table: TableData(title: arg(call, "title"), hasHeader: true, rows: cells)), into: found)
            activity.nodeID = found.id
            activity.changedContent = true
            activity.summary = L("Added a table to “\(found.displayTitle)”", "“\(found.displayTitle)”에 표를 추가함")
            return "Added a \(rows.count)×\(width) table to “\(found.displayTitle)”."

        case "add_chart":
            let found = try node(arg(call, "node"))
            guard !found.isFile else { throw ToolFailure(message: "A file node only holds notes; charts can't be added to it.") }
            guard let style = ChartStyle(rawValue: arg(call, "style")) else { throw ToolFailure(message: "`style` must be pie, bar or line.") }
            let points = (call.input?["points"] as? [[String: Any]] ?? []).enumerated().compactMap { index, point -> ChartPoint? in
                guard let value = (point["value"] as? NSNumber)?.doubleValue ?? Double("\(point["value"] ?? "")") else { return nil }
                return ChartPoint(label: "\(point["label"] ?? "")", value: value, colorSlot: index % 8)
            }
            guard !points.isEmpty else { throw ToolFailure(message: "`points` needs at least one {label, value}.") }
            insert(Block(kind: .chart, chart: ChartData(title: arg(call, "title"), style: style, points: points)), into: found)
            activity.nodeID = found.id
            activity.changedContent = true
            activity.summary = L("Added a chart to “\(found.displayTitle)”", "“\(found.displayTitle)”에 그래프를 추가함")
            return "Added a \(style.rawValue) chart with \(points.count) points to “\(found.displayTitle)”."

        case "add_link":
            let from = try node(arg(call, "from")), to = try node(arg(call, "to"))
            guard from.id != to.id else { throw ToolFailure(message: "A node can't be linked to itself.") }
            withAnimation(Motion.spring) { space.addLink(from: Anchor(nodeID: from.id, blockID: nil), to: Anchor(nodeID: to.id, blockID: nil)) }
            activity.nodeID = from.id
            activity.changedContent = true
            activity.summary = L("Linked “\(from.displayTitle)” and “\(to.displayTitle)”", "“\(from.displayTitle)”와(과) “\(to.displayTitle)”을(를) 연결함")
            return "Linked “\(from.displayTitle)” and “\(to.displayTitle)”."

        case "remember":
            guard ai.remember(arg(call, "text"), author: model.label, for: account.id) != nil else { throw ToolFailure(message: "There is nothing to remember.") }
            return "Saved. Every model will see this from now on."

        case "use_skill":
            guard let skill = ai.skill(named: arg(call, "name")) else {
                throw ToolFailure(message: "There is no skill named “\(arg(call, "name"))”. Available: " + ai.settings.skills.map(\.name).joined(separator: ", "))
            }
            return "Skill “\(skill.name)” — follow these instructions:\n\n" + skill.instructions

        default:
            throw ToolFailure(message: "Unknown tool “\(call.name)”.")
        }
    }

    private func category(named name: String) -> NodeCategory {
        if let existing = space.categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        return withAnimation(Motion.spring) { space.addCategory(named: name) }
    }

    /// Puts an object at the end of the page, keeping a line of text after it to go on writing.
    private func insert(_ block: Block, into node: NodeModel) {
        withAnimation(Motion.spring) {
            if node.blocks.count > 1, let last = node.blocks.last, last.data.kind == .text, last.plainText.isEmpty {
                node.blocks.insert(BlockModel(block), at: node.blocks.count - 1)
            } else {
                node.blocks.append(contentsOf: [BlockModel(block), BlockModel(Block(kind: .text))])
            }
        }
    }

    private func search(_ query: String, everywhere: Bool) -> String {
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 }
        guard !terms.isEmpty else { return "The query has no searchable words." }
        struct Hit { var score: Int; var line: String }
        var hits: [Hit] = []
        func consider(_ label: String, _ text: String) {
            let lower = text.lowercased()
            let matched = terms.filter(lower.contains)
            guard !matched.isEmpty else { return }
            var snippet = ""
            if let range = lower.range(of: matched[0]) {
                let start = lower.index(range.lowerBound, offsetBy: -80, limitedBy: lower.startIndex) ?? lower.startIndex
                let end = lower.index(range.upperBound, offsetBy: 160, limitedBy: lower.endIndex) ?? lower.endIndex
                let offsetStart = lower.distance(from: lower.startIndex, to: start), offsetEnd = lower.distance(from: lower.startIndex, to: end)
                let chars = Array(text)
                if offsetEnd <= chars.count { snippet = String(chars[offsetStart..<offsetEnd]).replacingOccurrences(of: "\n", with: " ") }
            }
            hits.append(Hit(score: matched.count * 10 + min(9, lower.components(separatedBy: matched[0]).count - 1), line: "- \(label): …\(snippet)…"))
        }
        let spaces = everywhere ? store.spaces(of: account.id) : [space]
        for target in spaces {
            for node in target.nodes {
                let prefix = target === space ? "" : "Space “\(target.info.name)” › "
                consider(prefix + "node [\(NodeReader.shortID(node.id))] \(node.displayTitle)", NodeReader.text(of: node, in: target, store: store, limit: 60_000))
            }
        }
        for thread in ai.threads(in: space.id) where thread.id != threadID {
            for message in thread.messages where !message.text.isEmpty {
                let speaker = message.role == .user ? "user" : (message.model?.label ?? "assistant")
                consider("conversation [\(NodeReader.shortID(thread.id))] “\(thread.title)” (\(speaker))", message.text)
            }
        }
        for item in ai.memory(for: account.id) { consider("shared memory", item.text) }
        guard !hits.isEmpty else { return "Nothing matches “\(query)”." }
        return hits.sorted { $0.score > $1.score }.prefix(12).map(\.line).joined(separator: "\n")
    }
}
