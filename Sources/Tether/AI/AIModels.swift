import Foundation
import SwiftUI

/// The services a model can come from.
enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropic, openai, gemini, ollama

    var id: String { rawValue }

    /// The assistant's name, as people know it.
    var title: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        }
    }

    var company: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        case .ollama: return "Local"
        }
    }

    var symbol: String {
        switch self {
        case .anthropic: return "sun.max.fill"
        case .openai: return "hexagon.fill"
        case .gemini: return "sparkle"
        case .ollama: return "desktopcomputer"
        }
    }

    var color: Color {
        switch self {
        case .anthropic: return Color(hex: "D9774F")
        case .openai: return Color(hex: "19A37F")
        case .gemini: return Color(hex: "4C8DF6")
        case .ollama: return Color(hex: "8A8F98")
        }
    }

    /// Local models run on this Mac and need no key.
    var needsKey: Bool { self != .ollama }

    /// Where an API key for this service is created.
    var keyPage: URL? {
        switch self {
        case .anthropic: return URL(string: "https://platform.claude.com/settings/keys")
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .ollama: return URL(string: "https://ollama.com/download")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .ollama: return "http://localhost:11434"
        }
    }

    /// The model chosen when nothing has been picked yet; nil means "the first one listed".
    var preferredModel: String? {
        switch self {
        case .anthropic: return "claude-opus-5-5"
        default: return nil
        }
    }
}

/// One model of one service.
struct AIModelRef: Codable, Hashable, Identifiable {
    var provider: AIProviderKind
    var modelID: String
    var name: String
    /// The most the model can write in one reply, when the service says.
    var maxOutput: Int?

    var id: String { provider.rawValue + "/" + modelID }

    /// "Claude · Opus 5.5"
    var label: String {
        let short = name.replacingOccurrences(of: provider.title + " ", with: "")
        return provider.title + " · " + short
    }
}

/// Something a model did with a tool during a reply, kept so the transcript shows the work.
struct ToolActivity: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case done, failed, denied }

    var id = UUID()
    var tool: String
    var summary: String
    var status: Status = .done
    /// The node the tool touched, so the chip can open it.
    var nodeID: UUID?
    var changedContent = false
}

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    /// The model that wrote an assistant message.
    var model: AIModelRef?
    var activity: [ToolActivity] = []
    /// The node that was open when the user sent the message.
    var nodeID: UUID?
    var skill: String?
    var error: String?
}

/// One conversation in a Space. Any connected model can continue it.
struct ChatThread: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
}

/// A fact every model is given, whichever service it comes from.
struct MemoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    /// Who saved it: a model's name, or empty when the user wrote it.
    var author = ""
}

/// A reusable instruction any model can follow.
struct AISkill: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var summary: String
    var instructions: String
}

struct MCPServerConfig: Codable, Identifiable, Equatable {
    enum Transport: String, Codable { case stdio, http }

    var id = UUID()
    var name: String
    var transport: Transport = .stdio
    /// Shell command for a local server, e.g. `npx -y @modelcontextprotocol/server-filesystem ~/Documents`.
    var command = ""
    var url = ""
    var enabled = true
}

/// How much a model may do to the Space without asking.
enum AIPermission: String, Codable, CaseIterable, Identifiable {
    case readOnly, ask, auto
    var id: String { rawValue }
}

/// App-wide assistant preferences (keys are not here: they live in the Keychain).
struct AISettings: Codable, Equatable {
    var selected: AIModelRef?
    var permission: AIPermission = .ask
    var skills: [AISkill] = []
    var servers: [MCPServerConfig] = []
    var baseURLs: [String: String] = [:]
    /// Whether the open node is sent along with each message.
    var includeOpenNode = true
    var seededSkills = false
    /// Whether the assistant panel is showing beside the page.
    var panelOpen = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selected = try c.decodeIfPresent(AIModelRef.self, forKey: .selected)
        permission = try c.decodeIfPresent(AIPermission.self, forKey: .permission) ?? .ask
        skills = try c.decodeIfPresent([AISkill].self, forKey: .skills) ?? []
        servers = try c.decodeIfPresent([MCPServerConfig].self, forKey: .servers) ?? []
        baseURLs = try c.decodeIfPresent([String: String].self, forKey: .baseURLs) ?? [:]
        includeOpenNode = try c.decodeIfPresent(Bool.self, forKey: .includeOpenNode) ?? true
        seededSkills = try c.decodeIfPresent(Bool.self, forKey: .seededSkills) ?? false
        panelOpen = try c.decodeIfPresent(Bool.self, forKey: .panelOpen) ?? false
    }
}

/// What a Space keeps of its conversations.
struct SpaceChats: Codable {
    var threads: [ChatThread] = []
    var active: UUID?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threads = try c.decodeIfPresent([ChatThread].self, forKey: .threads) ?? []
        active = try c.decodeIfPresent(UUID.self, forKey: .active)
    }
}

/// A tool a model can call: a name, what it is for, and a JSON Schema for its input.
struct AIToolSpec {
    var name: String
    var description: String
    /// JSON Schema object (`type: object`, `properties`, `required`).
    var schema: [String: Any]
    /// True when calling it changes something (a node, the memory, the outside world).
    var writes = false
}

/// A tool call a model asked for.
struct AIToolCall {
    var id: String
    var name: String
    /// Parsed input; nil when the model produced JSON that could not be read.
    var input: [String: Any]?
    var rawInput: String
}

struct AIToolResult {
    var callID: String
    var name: String
    var text: String
    var isError = false
}
