import Foundation

// One file per wire format would be tidier, but the four adapters share so much (history in,
// streamed text and tool calls out) that reading them side by side is easier.
//
// The shape every adapter follows:
//   • Earlier turns of the conversation go in as plain text, so a thread started with one
//     service can be continued by another.
//   • Inside the reply being written, a model may call tools several times. What the model
//     produced in those rounds is replayed to the same service exactly as it arrived (`raw`),
//     because each service attaches its own hidden state to it (thinking blocks, reasoning
//     items, thought signatures).

enum AIError: Error {
    case api(status: Int, message: String)
    case missingKey(AIProviderKind)
    case unreadable(String)

    @MainActor
    static func describe(_ error: Error) -> String {
        switch error {
        case AIError.api(let status, let message):
            let hint: String
            switch status {
            case 401, 403: hint = L("The key was not accepted.", "키가 받아들여지지 않았어요.")
            case 402: hint = L("The account has no credit left.", "계정에 남은 크레딧이 없어요.")
            case 404: hint = L("That model isn't available to this key.", "이 키로는 쓸 수 없는 모델이에요.")
            case 429: hint = L("Rate limit or spending cap reached.", "요청 한도 또는 지출 한도에 도달했어요.")
            case 500...599: hint = L("The service is having trouble. Try again shortly.", "서비스에 문제가 있어요. 잠시 후 다시 시도해 주세요.")
            default: hint = ""
            }
            let detail = message.isEmpty ? "HTTP \(status)" : message
            return hint.isEmpty ? detail : hint + " (" + detail + ")"
        case AIError.missingKey(let kind):
            return L("\(kind.title) is not connected yet.", "\(kind.title)이(가) 아직 연결되지 않았어요.")
        case AIError.unreadable(let what):
            return L("The reply could not be read: \(what)", "응답을 읽을 수 없어요: \(what)")
        case let urlError as URLError:
            if urlError.code == .cannotConnectToHost || urlError.code == .cannotFindHost {
                return L("Couldn't reach the service.", "서비스에 연결할 수 없어요.")
            }
            if urlError.code == .notConnectedToInternet { return L("No internet connection.", "인터넷에 연결되어 있지 않아요.") }
            return urlError.localizedDescription
        case is CancellationError:
            return L("Stopped.", "중지했어요.")
        default:
            return error.localizedDescription
        }
    }
}

struct AITurn {
    var role: ChatMessage.Role
    var text: String
}

struct AIRequest {
    var model: AIModelRef
    var system: String
    var history: [AITurn]
    var tools: [AIToolSpec]
}

/// One round of tool use inside the reply being written.
struct AIRound {
    /// What the service sent, in its own format, to be replayed unchanged.
    var raw: Any
    var calls: [AIToolCall]
    var results: [AIToolResult]
}

enum AIStop {
    case end, tools, maxTokens
    case refusal(String)
}

struct AIStep {
    var text = ""
    var calls: [AIToolCall] = []
    var raw: Any = [Any]()
    var stop: AIStop = .end
    /// The model that actually answered, when the service reports a different one.
    var servedBy: String?
}

@MainActor
protocol AIProvider {
    func listModels() async throws -> [AIModelRef]
    func step(_ request: AIRequest, rounds: [AIRound], onText: (String) -> Void) async throws -> AIStep
}

@MainActor
enum AIProviders {
    static func make(_ kind: AIProviderKind, baseURL: String, key: String) -> AIProvider {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        switch kind {
        case .anthropic: return ClaudeProvider(base: base, key: key)
        case .openai: return OpenAIProvider(base: base, key: key)
        case .gemini: return GeminiProvider(base: base, key: key)
        case .ollama: return OllamaProvider(base: base)
        }
    }
}

// MARK: HTTP

@MainActor
enum AIHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3600
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func request(_ url: String, method: String = "POST", headers: [String: String], body: [String: Any]? = nil) throws -> URLRequest {
        guard let target = URL(string: url) else { throw AIError.unreadable(url) }
        var request = URLRequest(url: target)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }

    /// The human-readable part of an error body. Every service nests it a little differently.
    static func message(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(String(data: data, encoding: .utf8)?.prefix(300) ?? "")
        }
        let root = (object as? [Any])?.first ?? object
        guard let dict = root as? [String: Any] else { return "" }
        if let error = dict["error"] as? [String: Any] { return (error["message"] as? String) ?? "" }
        if let error = dict["error"] as? String { return error }
        return (dict["message"] as? String) ?? ""
    }

    static func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.api(status: status, message: message(in: data)) }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.unreadable("JSON") }
        return dict
    }

    /// Reads a streamed reply line by line. Server-sent events and newline-delimited JSON both
    /// come through here; blank lines are dropped.
    static func lines(_ request: URLRequest, _ onLine: (String) throws -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 65_536 { break }
            }
            throw AIError.api(status: status, message: message(in: data))
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            try onLine(line)
        }
    }

    /// The JSON after `data:` on a server-sent-events line.
    static func eventPayload(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let text = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard text != "[DONE]", let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func parseObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func string(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// Earlier turns as alternating user/assistant text, starting with the user — the form every
/// service accepts.
private func alternating(_ history: [AITurn]) -> [AITurn] {
    var result: [AITurn] = []
    for turn in history where !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let last = result.last, last.role == turn.role {
            result[result.count - 1].text += "\n\n" + turn.text
        } else {
            result.append(turn)
        }
    }
    while let first = result.first, first.role == .assistant { result.removeFirst() }
    return result
}

// MARK: Claude (Anthropic Messages API)

@MainActor
struct ClaudeProvider: AIProvider {
    let base: String
    let key: String

    private var headers: [String: String] { ["x-api-key": key, "anthropic-version": "2026-10-21"] }

    func listModels() async throws -> [AIModelRef] {
        guard !key.isEmpty else { throw AIError.missingKey(.anthropic) }
        var result: [AIModelRef] = []
        var after: String?
        repeat {
            let url = base + "/v1/models?limit=1000" + (after.map { "&after_id=" + $0 } ?? "")
            let page = try await AIHTTP.json(try AIHTTP.request(url, method: "GET", headers: headers))
            for item in page["data"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String else { continue }
                result.append(AIModelRef(provider: .anthropic, modelID: id, name: (item["display_name"] as? String) ?? id,
                                         maxOutput: item["max_tokens"] as? Int))
            }
            after = (page["has_more"] as? Bool) == true ? page["last_id"] as? String : nil
        } while after != nil
        return result
    }

    /// Models whose safety classifiers can decline a request: these get a server-side fallback,
    /// so a decline is answered by another model instead of ending the turn.
    private func supportsFallback(_ id: String) -> Bool {
        ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5"].contains { id.hasPrefix($0) } || id == "claude-opus-5"
    }

    func step(_ request: AIRequest, rounds: [AIRound], onText: (String) -> Void) async throws -> AIStep {
        guard !key.isEmpty else { throw AIError.missingKey(.anthropic) }
        do {
            return try await run(request, rounds: rounds, fallback: supportsFallback(request.model.modelID), onText: onText)
        } catch AIError.api(400, let message) where message.lowercased().contains("fallback") {
            // The organisation can't use server-side fallbacks: send the request without them.
            return try await run(request, rounds: rounds, fallback: false, onText: onText)
        }
    }

    private func run(_ request: AIRequest, rounds: [AIRound], fallback: Bool, onText: (String) -> Void) async throws -> AIStep {
        var messages: [[String: Any]] = alternating(request.history).map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }
        for round in rounds {
            messages.append(["role": "assistant", "content": Self.replayable(round.raw as? [[String: Any]] ?? [])])
            messages.append(["role": "user", "content": round.results.map { result -> [String: Any] in
                var block: [String: Any] = ["type": "tool_result", "tool_use_id": result.callID, "content": result.text]
                if result.isError { block["is_error"] = true }
                return block
            }])
        }
        var body: [String: Any] = [
            "model": request.model.modelID,
            "max_tokens": min(64_000, request.model.maxOutput ?? 64_000),
            "stream": true,
            "system": request.system,
            "messages": messages,
            // Everything before the newest message is the same on each round of a tool loop.
            "cache_control": ["type": "ephemeral"],
        ]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool -> [String: Any] in
                ["name": tool.name, "description": tool.description, "input_schema": tool.schema, "eager_input_streaming": true]
            }
        }
        var headers = headers
        if fallback {
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            body["fallbacks"] = "default"
        }

        var blocks: [Int: [String: Any]] = [:]
        var partial: [Int: String] = [:]
        var broken: Set<Int> = []
        var step = AIStep()
        var stopReason = ""
        var refusal = ""

        try await AIHTTP.lines(try AIHTTP.request(base + "/v1/messages", headers: headers, body: body)) { line in
            guard let event = AIHTTP.eventPayload(line), let type = event["type"] as? String else { return }
            let index = event["index"] as? Int ?? 0
            switch type {
            case "message_start":
                if let model = (event["message"] as? [String: Any])?["model"] as? String, model != request.model.modelID {
                    step.servedBy = model
                }
            case "content_block_start":
                blocks[index] = event["content_block"] as? [String: Any] ?? [:]
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], let kind = delta["type"] as? String else { return }
                switch kind {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    let soFar = (blocks[index]?["text"] as? String) ?? ""
                    blocks[index]?["text"] = soFar + text
                    step.text += text
                    onText(text)
                case "input_json_delta":
                    partial[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "thinking_delta":
                    let soFar = (blocks[index]?["thinking"] as? String) ?? ""
                    blocks[index]?["thinking"] = soFar + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    blocks[index]?["signature"] = delta["signature"] as? String ?? ""
                default:
                    break
                }
            case "content_block_stop":
                guard blocks[index]?["type"] as? String == "tool_use" else { return }
                // With eager input streaming the service no longer checks the JSON, so it is checked here.
                if let input = AIHTTP.parseObject(partial[index] ?? "") {
                    blocks[index]?["input"] = input
                } else {
                    blocks[index]?["input"] = [String: Any]()
                    broken.insert(index)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any] {
                    stopReason = delta["stop_reason"] as? String ?? stopReason
                    if let details = delta["stop_details"] as? [String: Any] {
                        refusal = (details["explanation"] as? String) ?? (details["category"] as? String) ?? ""
                    }
                }
            case "error":
                let error = event["error"] as? [String: Any]
                let kind = error?["type"] as? String ?? ""
                throw AIError.api(status: kind == "overloaded_error" ? 529 : 500, message: error?["message"] as? String ?? kind)
            default:
                break
            }
        }

        let ordered = blocks.keys.sorted()
        step.raw = ordered.compactMap { blocks[$0] }
        for index in ordered {
            guard let block = blocks[index], block["type"] as? String == "tool_use",
                  let id = block["id"] as? String, let name = block["name"] as? String else { continue }
            step.calls.append(AIToolCall(id: id, name: name, input: broken.contains(index) ? nil : block["input"] as? [String: Any],
                                         rawInput: partial[index] ?? ""))
        }
        switch stopReason {
        case "tool_use": step.stop = step.calls.isEmpty ? .end : .tools
        case "max_tokens": step.stop = .maxTokens
        case "refusal": step.stop = .refusal(refusal)
        default: step.stop = .end
        }
        return step
    }

    /// After a mid-reply fallback, only the text written before the switch may be sent back;
    /// the marker itself stays where it was.
    private static func replayable(_ blocks: [[String: Any]]) -> [[String: Any]] {
        guard let boundary = blocks.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return blocks }
        return blocks.enumerated().compactMap { index, block in
            let type = block["type"] as? String
            return index >= boundary || type == "text" || type == "fallback" ? block : nil
        }
    }
}

// MARK: ChatGPT (OpenAI Responses API)

@MainActor
struct OpenAIProvider: AIProvider {
    let base: String
    let key: String

    private var headers: [String: String] { ["Authorization": "Bearer " + key] }

    func listModels() async throws -> [AIModelRef] {
        guard !key.isEmpty else { throw AIError.missingKey(.openai) }
        let page = try await AIHTTP.json(try AIHTTP.request(base + "/v1/models", method: "GET", headers: headers))
        let excluded = ["embedding", "audio", "realtime", "tts", "transcribe", "image", "whisper", "moderation",
                        "search", "instruct", "dall-e", "sora", "codex-mini", "computer-use"]
        return (page["data"] as? [[String: Any]] ?? [])
            .compactMap { item -> (String, Int)? in
                guard let id = item["id"] as? String else { return nil }
                let chatLike = id.hasPrefix("gpt-") || id.hasPrefix("chatgpt-") || (id.hasPrefix("o") && id.dropFirst().first?.isNumber == true)
                guard chatLike, !excluded.contains(where: id.contains) else { return nil }
                return (id, item["created"] as? Int ?? 0)
            }
            .sorted { $0.1 > $1.1 }
            .map { AIModelRef(provider: .openai, modelID: $0.0, name: $0.0) }
    }

    func step(_ request: AIRequest, rounds: [AIRound], onText: (String) -> Void) async throws -> AIStep {
        guard !key.isEmpty else { throw AIError.missingKey(.openai) }
        var input: [Any] = alternating(request.history).map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] as [String: Any]
        }
        for round in rounds {
            // The model's own items (reasoning included) go back exactly as they came.
            input.append(contentsOf: round.raw as? [Any] ?? [])
            for result in round.results {
                input.append(["type": "function_call_output", "call_id": result.callID, "output": result.text] as [String: Any])
            }
        }
        var body: [String: Any] = ["model": request.model.modelID, "instructions": request.system, "input": input, "stream": true]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { tool -> [String: Any] in
                ["type": "function", "name": tool.name, "description": tool.description, "parameters": tool.schema, "strict": false]
            }
        }

        var step = AIStep()
        var items: [Int: [String: Any]] = [:]
        var completed: [[String: Any]]?
        var incomplete = false

        try await AIHTTP.lines(try AIHTTP.request(base + "/v1/responses", headers: headers, body: body)) { line in
            guard let event = AIHTTP.eventPayload(line), let type = event["type"] as? String else { return }
            switch type {
            case "response.output_text.delta", "response.refusal.delta":
                let text = event["delta"] as? String ?? ""
                step.text += text
                onText(text)
            case "response.output_item.done":
                if let item = event["item"] as? [String: Any] { items[event["output_index"] as? Int ?? items.count] = item }
            case "response.completed", "response.incomplete":
                let response = event["response"] as? [String: Any]
                completed = response?["output"] as? [[String: Any]]
                incomplete = type == "response.incomplete"
            case "response.failed":
                let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                throw AIError.api(status: 500, message: error?["message"] as? String ?? "")
            case "error":
                let nested = event["error"] as? [String: Any]
                throw AIError.api(status: 500, message: (event["message"] as? String) ?? (nested?["message"] as? String) ?? "")
            default:
                break
            }
        }

        let output = completed ?? items.keys.sorted().compactMap { items[$0] }
        step.raw = output
        for item in output where item["type"] as? String == "function_call" {
            guard let callID = item["call_id"] as? String, let name = item["name"] as? String else { continue }
            let arguments = item["arguments"] as? String ?? ""
            step.calls.append(AIToolCall(id: callID, name: name, input: AIHTTP.parseObject(arguments), rawInput: arguments))
        }
        step.stop = incomplete ? .maxTokens : (step.calls.isEmpty ? .end : .tools)
        return step
    }
}

// MARK: Gemini (generateContent)

@MainActor
struct GeminiProvider: AIProvider {
    let base: String
    let key: String

    private var headers: [String: String] { ["x-goog-api-key": key] }

    func listModels() async throws -> [AIModelRef] {
        guard !key.isEmpty else { throw AIError.missingKey(.gemini) }
        var result: [AIModelRef] = []
        var token: String?
        let excluded = ["embedding", "tts", "image", "audio", "live", "aqa", "robotics", "veo", "imagen", "lyria"]
        repeat {
            let url = base + "/v1beta/models?pageSize=1000" + (token.map { "&pageToken=" + $0 } ?? "")
            let page = try await AIHTTP.json(try AIHTTP.request(url, method: "GET", headers: headers))
            for item in page["models"] as? [[String: Any]] ?? [] {
                guard let name = item["name"] as? String,
                      (item["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { continue }
                let id = name.replacingOccurrences(of: "models/", with: "")
                guard id.hasPrefix("gemini"), !excluded.contains(where: id.contains) else { continue }
                result.append(AIModelRef(provider: .gemini, modelID: id, name: (item["displayName"] as? String) ?? id,
                                         maxOutput: item["outputTokenLimit"] as? Int))
            }
            token = page["nextPageToken"] as? String
        } while token != nil
        return result.sorted { $0.modelID.compare($1.modelID, options: .numeric) == .orderedDescending }
    }

    func step(_ request: AIRequest, rounds: [AIRound], onText: (String) -> Void) async throws -> AIStep {
        guard !key.isEmpty else { throw AIError.missingKey(.gemini) }
        var contents: [[String: Any]] = alternating(request.history).map {
            ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]]
        }
        for round in rounds {
            // Parts carry thought signatures, so they are sent back untouched and in order.
            contents.append(["role": "model", "parts": round.raw as? [Any] ?? []])
            contents.append(["role": "user", "parts": zip(round.calls, round.results).map { call, result -> [String: Any] in
                var response: [String: Any] = ["name": result.name, "response": [result.isError ? "error" : "result": result.text]]
                if !call.id.hasPrefix("local-") { response["id"] = call.id }
                return ["functionResponse": response]
            }])
        }
        var body: [String: Any] = ["systemInstruction": ["parts": [["text": request.system]]], "contents": contents]
        if !request.tools.isEmpty {
            body["tools"] = [["functionDeclarations": request.tools.map { tool -> [String: Any] in
                var declaration: [String: Any] = ["name": tool.name, "description": tool.description]
                if let parameters = Self.simplified(tool.schema) as? [String: Any],
                   !((parameters["properties"] as? [String: Any]) ?? [:]).isEmpty {
                    declaration["parameters"] = parameters
                }
                return declaration
            }]]
        }

        var step = AIStep()
        var parts: [Any] = []
        var finish = ""
        var blocked = ""
        let url = base + "/v1beta/models/" + request.model.modelID + ":streamGenerateContent?alt=sse"

        try await AIHTTP.lines(try AIHTTP.request(url, headers: headers, body: body)) { line in
            guard let chunk = AIHTTP.eventPayload(line) else { return }
            if let error = chunk["error"] as? [String: Any] {
                throw AIError.api(status: error["code"] as? Int ?? 500, message: error["message"] as? String ?? "")
            }
            if let feedback = chunk["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String { blocked = reason }
            guard let candidate = (chunk["candidates"] as? [[String: Any]])?.first else { return }
            finish = candidate["finishReason"] as? String ?? finish
            for part in (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? [] {
                parts.append(part)
                if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String {
                    let arguments = call["args"] as? [String: Any] ?? [:]
                    step.calls.append(AIToolCall(id: (call["id"] as? String) ?? "local-\(step.calls.count)", name: name,
                                                 input: arguments, rawInput: AIHTTP.string(arguments)))
                } else if let text = part["text"] as? String, (part["thought"] as? Bool) != true {
                    step.text += text
                    onText(text)
                }
            }
        }

        step.raw = parts
        if !blocked.isEmpty {
            step.stop = .refusal(blocked)
        } else if !step.calls.isEmpty {
            step.stop = .tools
        } else if finish == "MAX_TOKENS" {
            step.stop = .maxTokens
        } else if ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII"].contains(finish) {
            step.stop = .refusal(finish)
        }
        return step
    }

    /// Gemini reads a subset of JSON Schema. Tools from MCP servers may use more, so anything
    /// outside the subset is dropped rather than refused.
    private static func simplified(_ schema: Any) -> Any {
        guard let dict = schema as? [String: Any] else { return schema }
        let kept: Set<String> = ["type", "description", "enum", "properties", "required", "items", "format", "nullable"]
        var result: [String: Any] = [:]
        for (name, value) in dict where kept.contains(name) {
            switch name {
            case "properties":
                result[name] = (value as? [String: Any] ?? [:]).mapValues(simplified)
            case "items":
                result[name] = simplified(value)
            case "type":
                result[name] = (value as? [String])?.first { $0 != "null" } ?? value
            default:
                result[name] = value
            }
        }
        if result["type"] == nil { result["type"] = result["properties"] != nil ? "object" : "string" }
        return result
    }
}

// MARK: Ollama (local models)

@MainActor
struct OllamaProvider: AIProvider {
    let base: String

    func listModels() async throws -> [AIModelRef] {
        let page = try await AIHTTP.json(try AIHTTP.request(base + "/api/tags", method: "GET", headers: [:]))
        return (page["models"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String, !name.contains("embed") else { return nil }
            return AIModelRef(provider: .ollama, modelID: name, name: name)
        }
    }

    func step(_ request: AIRequest, rounds: [AIRound], onText: (String) -> Void) async throws -> AIStep {
        do {
            return try await run(request, rounds: rounds, tools: request.tools, onText: onText)
        } catch AIError.api(400, let message) where message.contains("does not support tools") {
            // Small local models often can't call tools; they can still talk.
            return try await run(request, rounds: rounds, tools: [], onText: onText)
        }
    }

    private func run(_ request: AIRequest, rounds: [AIRound], tools: [AIToolSpec], onText: (String) -> Void) async throws -> AIStep {
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        messages += alternating(request.history).map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        for round in rounds {
            messages.append(round.raw as? [String: Any] ?? ["role": "assistant", "content": ""])
            for result in round.results {
                messages.append(["role": "tool", "content": result.text, "tool_name": result.name])
            }
        }
        var body: [String: Any] = ["model": request.model.modelID, "messages": messages, "stream": true]
        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                ["type": "function", "function": ["name": tool.name, "description": tool.description, "parameters": tool.schema]]
            }
        }

        var step = AIStep()
        var rawCalls: [[String: Any]] = []
        try await AIHTTP.lines(try AIHTTP.request(base + "/api/chat", headers: [:], body: body)) { line in
            guard let data = line.data(using: .utf8), let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let error = chunk["error"] as? String { throw AIError.api(status: 500, message: error) }
            guard let message = chunk["message"] as? [String: Any] else { return }
            if let text = message["content"] as? String, !text.isEmpty {
                step.text += text
                onText(text)
            }
            for call in message["tool_calls"] as? [[String: Any]] ?? [] {
                guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { continue }
                let arguments = function["arguments"] as? [String: Any] ?? [:]
                rawCalls.append(call)
                step.calls.append(AIToolCall(id: "local-\(step.calls.count)", name: name, input: arguments, rawInput: AIHTTP.string(arguments)))
            }
        }
        var raw: [String: Any] = ["role": "assistant", "content": step.text]
        if !rawCalls.isEmpty { raw["tool_calls"] = rawCalls }
        step.raw = raw
        step.stop = step.calls.isEmpty ? .end : .tools
        return step
    }
}
