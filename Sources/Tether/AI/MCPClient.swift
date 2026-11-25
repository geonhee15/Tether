import Foundation
import Observation

/// A connection to one Model Context Protocol server. Only tools are used.
@MainActor
protocol MCPConnection: AnyObject {
    func request(_ method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any]
    func notify(_ method: String) async
    func close()
}

private struct MCPFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A local server started as a child process and spoken to over stdin/stdout, one JSON-RPC
/// message per line. The command runs through a login shell so tools like `npx` and `uvx` are found.
@MainActor
final class StdioMCPConnection: MCPConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1
    private var lastError = ""

    init(command: String) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardInput = input
        process.standardOutput = output
        let errors = Pipe()
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.received(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self?.lastError = String(text.suffix(300)) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.failAll("The server exited.") }
        }
        try process.run()
    }

    private func received(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (message["id"] as? NSNumber)?.intValue, let waiting = pending.removeValue(forKey: id) else { continue }
            if let error = message["error"] as? [String: Any] {
                waiting.resume(throwing: MCPFailure(message: error["message"] as? String ?? "MCP error"))
            } else {
                waiting.resume(returning: message["result"] as? [String: Any] ?? [:])
            }
        }
    }

    private func failAll(_ reason: String) {
        let detail = lastError.isEmpty ? reason : reason + " " + lastError
        for (_, waiting) in pending { waiting.resume(throwing: MCPFailure(message: detail)) }
        pending.removeAll()
    }

    private func write(_ message: [String: Any]) throws {
        guard process.isRunning else { throw MCPFailure(message: lastError.isEmpty ? "The server is not running." : lastError) }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func request(_ method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let waiting = self.pending.removeValue(forKey: id) else { return }
                waiting.resume(throwing: MCPFailure(message: "The server did not answer in time." + (self.lastError.isEmpty ? "" : " " + self.lastError)))
            }
        }
    }

    func notify(_ method: String) async {
        try? write(["jsonrpc": "2.0", "method": method])
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        failAll("Disconnected.")
    }
}

/// A remote server reached with HTTP POST ("Streamable HTTP"). Each call is one request; the
/// answer comes back as JSON or as a short event stream.
@MainActor
final class HTTPMCPConnection: MCPConnection {
    private let url: String
    private var session: String?
    private var nextID = 1

    init(url: String) { self.url = url }

    private func post(_ message: [String: Any], timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var headers = ["Accept": "application/json, text/event-stream", "MCP-Protocol-Version": MCPHub.protocolVersion]
        if let session { headers["Mcp-Session-Id"] = session }
        var request = try AIHTTP.request(url, headers: headers, body: message)
        request.timeoutInterval = timeout
        let (data, response) = try await AIHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MCPFailure(message: "No HTTP response.") }
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id") { session = id }
        guard (200..<300).contains(http.statusCode) else {
            throw MCPFailure(message: http.statusCode == 401 ? "The server needs sign-in, which isn't supported yet." : "HTTP \(http.statusCode) " + AIHTTP.message(in: data))
        }
        return (data, http)
    }

    func request(_ method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let (data, http) = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": params], timeout: timeout)
        var messages: [[String: Any]] = []
        if (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
            for line in (String(data: data, encoding: .utf8) ?? "").components(separatedBy: .newlines) {
                if let payload = AIHTTP.eventPayload(line) { messages.append(payload) }
            }
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            messages = [object]
        }
        guard let answer = messages.first(where: { ($0["id"] as? NSNumber)?.intValue == id }) else { throw MCPFailure(message: "The server sent no answer.") }
        if let error = answer["error"] as? [String: Any] { throw MCPFailure(message: error["message"] as? String ?? "MCP error") }
        return answer["result"] as? [String: Any] ?? [:]
    }

    func notify(_ method: String) async {
        _ = try? await post(["jsonrpc": "2.0", "method": method], timeout: 15)
    }

    func close() {}
}

enum MCPStatus: Equatable {
    case idle, connecting
    case connected(Int)
    case failed(String)
}

/// Keeps the user's MCP servers connected and offers their tools to whichever model is answering.
@MainActor
@Observable
final class MCPHub {
    static let protocolVersion = "2025-06-18"

    private struct Route {
        var server: UUID
        var serverName: String
        var tool: String
    }

    private(set) var tools: [AIToolSpec] = []
    var status: [UUID: MCPStatus] = [:]

    @ObservationIgnored private var connections: [UUID: MCPConnection] = [:]
    @ObservationIgnored private var active: [UUID: MCPServerConfig] = [:]
    @ObservationIgnored private var serverTools: [UUID: [AIToolSpec]] = [:]
    @ObservationIgnored private var routes: [String: Route] = [:]

    /// Brings the connections in line with the settings: new or changed servers are (re)started,
    /// removed or disabled ones are stopped.
    func sync(with configs: [MCPServerConfig]) async {
        let wanted = Dictionary(uniqueKeysWithValues: configs.filter(\.enabled).map { ($0.id, $0) })
        for id in Array(connections.keys) where wanted[id] != active[id] { disconnect(id) }
        for (id, _) in status where wanted[id] == nil { status[id] = .idle }
        for config in wanted.values where connections[config.id] == nil {
            if case .failed = status[config.id] ?? .idle, active[config.id] == config { continue }
            await connect(config)
        }
    }

    /// Connects (or reconnects) one server and reports how it went.
    func connect(_ config: MCPServerConfig) async {
        disconnect(config.id)
        active[config.id] = config
        status[config.id] = .connecting
        do {
            let connection: MCPConnection
            switch config.transport {
            case .stdio:
                guard !config.command.trimmingCharacters(in: .whitespaces).isEmpty else { throw MCPFailure(message: "No command.") }
                connection = try StdioMCPConnection(command: config.command)
            case .http:
                guard config.url.hasPrefix("http") else { throw MCPFailure(message: "The address must start with http:// or https://.") }
                connection = HTTPMCPConnection(url: config.url)
            }
            connections[config.id] = connection
            _ = try await connection.request("initialize", params: [
                "protocolVersion": Self.protocolVersion,
                "capabilities": [String: Any](),
                "clientInfo": ["name": "Tether", "version": AppInfo.version],
            ], timeout: 45)
            await connection.notify("notifications/initialized")
            var listed: [AIToolSpec] = []
            var cursor: String?
            repeat {
                let page = try await connection.request("tools/list", params: cursor.map { ["cursor": $0] } ?? [:], timeout: 30)
                for tool in page["tools"] as? [[String: Any]] ?? [] {
                    guard let name = tool["name"] as? String else { continue }
                    let exposed = Self.exposedName(server: config.name, tool: name)
                    let readOnly = ((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool) == true
                    var schema = tool["inputSchema"] as? [String: Any] ?? ["type": "object", "properties": [String: Any]()]
                    if schema["type"] == nil { schema["type"] = "object" }
                    if schema["properties"] == nil { schema["properties"] = [String: Any]() }
                    listed.append(AIToolSpec(name: exposed, description: "From the MCP server “\(config.name)”. " + (tool["description"] as? String ?? name),
                                             schema: schema, writes: !readOnly))
                    routes[exposed] = Route(server: config.id, serverName: config.name, tool: name)
                }
                cursor = page["nextCursor"] as? String
            } while cursor != nil
            serverTools[config.id] = listed
            status[config.id] = .connected(listed.count)
        } catch {
            connections[config.id]?.close()
            connections[config.id] = nil
            serverTools[config.id] = nil
            status[config.id] = .failed(error.localizedDescription)
        }
        rebuild()
    }

    func disconnect(_ id: UUID) {
        connections[id]?.close()
        connections[id] = nil
        serverTools[id] = nil
        routes = routes.filter { $0.value.server != id }
        active[id] = nil
        rebuild()
    }

    func shutdown() {
        for id in Array(connections.keys) { disconnect(id) }
    }

    private func rebuild() {
        tools = serverTools.values.flatMap { $0 }.sorted { $0.name < $1.name }
    }

    /// Tool names must be short and plain for every model service, so server and tool are folded into one.
    private static func exposedName(server: String, tool: String) -> String {
        func plain(_ text: String) -> String {
            String(text.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
        }
        return String(("mcp__" + plain(server) + "__" + plain(tool)).prefix(64))
    }

    func display(_ name: String) -> (server: String, tool: String)? {
        routes[name].map { ($0.serverName, $0.tool) }
    }

    func call(_ name: String, arguments: [String: Any]) async throws -> String {
        guard let route = routes[name], let connection = connections[route.server] else { throw MCPFailure(message: "That MCP server is not connected.") }
        let result = try await connection.request("tools/call", params: ["name": route.tool, "arguments": arguments], timeout: 120)
        let text = (result["content"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            if let text = item["text"] as? String { return text }
            if let type = item["type"] as? String { return "(\(type) content that can't be shown as text)" }
            return nil
        }.joined(separator: "\n")
        if (result["isError"] as? Bool) == true { throw MCPFailure(message: text.isEmpty ? "The tool reported an error." : text) }
        let clipped = text.count > 40_000 ? String(text.prefix(40_000)) + "\n…(cut here)" : text
        return clipped.isEmpty ? "(The tool returned nothing.)" : clipped
    }
}
