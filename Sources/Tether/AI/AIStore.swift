import Foundation
import Observation
import Security

/// Where API keys are kept: the macOS Keychain, never the data folder (so they stay out of
/// backups). Demo and test runs never touch the Keychain — they read throwaway keys from the
/// environment instead.
enum KeyVault {
    private static let service = "com.geonhee.tether.ai"
    private static var memory: [String: String] = [:]
    /// Keys already read from the Keychain this session ("" = looked, none there), so views that
    /// ask whether a service is connected don't query the Keychain on every redraw.
    private static var cache: [String: String] = [:]

    private static var isDemo: Bool { ProcessInfo.processInfo.environment["TETHER_DATA_DIR"] != nil }

    static func key(for provider: AIProviderKind) -> String? {
        if isDemo {
            if let stored = memory[provider.rawValue] { return stored.isEmpty ? nil : stored }
            let fromEnv = ProcessInfo.processInfo.environment["TETHER_AI_KEY_" + provider.rawValue.uppercased()]
            return (fromEnv?.isEmpty ?? true) ? nil : fromEnv
        }
        if let cached = cache[provider.rawValue] { return cached.isEmpty ? nil : cached }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: provider.rawValue,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            cache[provider.rawValue] = ""
            return nil
        }
        cache[provider.rawValue] = value
        return value
    }

    @discardableResult
    static func setKey(_ value: String?, for provider: AIProviderKind) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isDemo {
            memory[provider.rawValue] = trimmed
            return true
        }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: provider.rawValue]
        SecItemDelete(base as CFDictionary)
        cache[provider.rawValue] = trimmed
        guard !trimmed.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "Tether — \(provider.title) API key"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

enum AIConnection: Equatable {
    case unknown, checking, connected
    case failed(String)
}

/// Everything the assistant keeps: which services are connected, conversations (per Space),
/// the memory shared by every model (per account), skills and MCP servers.
/// Files live in `ai/` inside the data folder.
@MainActor
@Observable
final class AIStore {
    @ObservationIgnored let directory: URL

    var settings: AISettings { didSet { if settings != oldValue { writeSettings() } } }
    /// Models each service offers, as last listed.
    var models: [AIProviderKind: [AIModelRef]] = [:]
    var connection: [AIProviderKind: AIConnection] = [:]
    /// Bumped when a key is saved or removed, so views re-read the Keychain.
    var keyRevision = 0

    private var chats: [UUID: SpaceChats] = [:]
    private var memories: [UUID: [MemoryItem]] = [:]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(dataDir: URL) {
        directory = dataDir.appendingPathComponent("ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = Self.read(AISettings.self, at: directory.appendingPathComponent("settings.json")) ?? AISettings()
        models = (Self.read([String: [AIModelRef]].self, at: directory.appendingPathComponent("models.json")) ?? [:])
            .reduce(into: [:]) { result, pair in
                if let kind = AIProviderKind(rawValue: pair.key) { result[kind] = pair.value }
            }
        if !settings.seededSkills {
            settings.skills.append(contentsOf: Self.starterSkills())
            settings.seededSkills = true
        }
    }

    // MARK: Files

    private static func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private func writeSettings() { write(settings, to: "settings.json") }

    static func chatsFile(for spaceID: UUID) -> String { "chats-\(spaceID.uuidString).json" }
    static func memoryFile(for accountID: UUID) -> String { "memory-\(accountID.uuidString).json" }

    // MARK: Connections

    func hasKey(_ provider: AIProviderKind) -> Bool {
        _ = keyRevision
        return !provider.needsKey || KeyVault.key(for: provider) != nil
    }

    /// A service is usable when it has a key (or needs none) and its models have been listed.
    func isReady(_ provider: AIProviderKind) -> Bool {
        hasKey(provider) && !(models[provider] ?? []).isEmpty
    }

    var readyProviders: [AIProviderKind] { AIProviderKind.allCases.filter(isReady) }

    func baseURL(for provider: AIProviderKind) -> String {
        if ProcessInfo.processInfo.environment["TETHER_DATA_DIR"] != nil,
           let override = ProcessInfo.processInfo.environment["TETHER_AI_BASE_" + provider.rawValue.uppercased()], !override.isEmpty {
            return override
        }
        let custom = settings.baseURLs[provider.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? provider.defaultBaseURL : custom
    }

    func provider(_ kind: AIProviderKind) -> AIProvider {
        AIProviders.make(kind, baseURL: baseURL(for: kind), key: KeyVault.key(for: kind) ?? "")
    }

    func saveKey(_ value: String?, for provider: AIProviderKind) {
        KeyVault.setKey(value, for: provider)
        keyRevision += 1
        if (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            models[provider] = []
            connection[provider] = .unknown
            persistModels()
            if settings.selected?.provider == provider { settings.selected = firstAvailableModel() }
        }
    }

    /// Asks the service which models this key can use. That doubles as the connection check.
    func refreshModels(_ kind: AIProviderKind) async {
        guard hasKey(kind) else {
            connection[kind] = .unknown
            return
        }
        connection[kind] = .checking
        do {
            let listed = try await provider(kind).listModels()
            models[kind] = listed
            connection[kind] = .connected
            persistModels()
            if settings.selected == nil { settings.selected = firstAvailableModel() }
        } catch {
            connection[kind] = .failed(AIError.describe(error))
            if kind == .ollama { models[kind] = [] }
        }
    }

    /// Refreshes every service that could work, without waiting for one before the next.
    /// Demo runs show seeded models and stay off the network unless a check asks for a service by name.
    func refreshAll() {
        guard ProcessInfo.processInfo.environment["TETHER_DATA_DIR"] == nil else { return }
        for kind in AIProviderKind.allCases where hasKey(kind) {
            Task { await refreshModels(kind) }
        }
    }

    private func persistModels() {
        write(models.reduce(into: [String: [AIModelRef]]()) { $0[$1.key.rawValue] = $1.value }, to: "models.json")
    }

    func firstAvailableModel() -> AIModelRef? {
        AIProviderKind.allCases.filter(isReady).compactMap(defaultModel).first
    }

    func defaultModel(of kind: AIProviderKind) -> AIModelRef? {
        let listed = models[kind] ?? []
        if let preferred = kind.preferredModel, let match = listed.first(where: { $0.modelID == preferred }) { return match }
        return listed.first
    }

    /// The model the next message goes to, if its service is still connected.
    var activeModel: AIModelRef? {
        if let selected = settings.selected, isReady(selected.provider) { return selected }
        return AIProviderKind.allCases.filter(isReady).compactMap(defaultModel).first
    }

    // MARK: Conversations

    private func loadChats(_ spaceID: UUID) -> SpaceChats {
        if let loaded = chats[spaceID] { return loaded }
        let loaded = Self.read(SpaceChats.self, at: directory.appendingPathComponent(Self.chatsFile(for: spaceID))) ?? SpaceChats()
        chats[spaceID] = loaded
        return loaded
    }

    func saveChats(_ spaceID: UUID) {
        guard let value = chats[spaceID] else { return }
        write(value, to: Self.chatsFile(for: spaceID))
    }

    func threads(in spaceID: UUID) -> [ChatThread] {
        loadChats(spaceID).threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    func activeThread(in spaceID: UUID) -> ChatThread? {
        let stored = loadChats(spaceID)
        return stored.threads.first { $0.id == stored.active }
    }

    func thread(_ id: UUID, in spaceID: UUID) -> ChatThread? {
        loadChats(spaceID).threads.first { $0.id == id }
    }

    @discardableResult
    func newThread(in spaceID: UUID) -> ChatThread {
        var stored = loadChats(spaceID)
        // An untouched new conversation is reused rather than piling up empty ones.
        if let empty = stored.threads.first(where: { $0.messages.isEmpty }) {
            stored.active = empty.id
            chats[spaceID] = stored
            return empty
        }
        let thread = ChatThread()
        stored.threads.append(thread)
        stored.active = thread.id
        chats[spaceID] = stored
        saveChats(spaceID)
        return thread
    }

    func selectThread(_ id: UUID?, in spaceID: UUID) {
        var stored = loadChats(spaceID)
        stored.active = id
        chats[spaceID] = stored
        saveChats(spaceID)
    }

    func deleteThread(_ id: UUID, in spaceID: UUID) {
        var stored = loadChats(spaceID)
        stored.threads.removeAll { $0.id == id }
        if stored.active == id { stored.active = stored.threads.max { $0.updatedAt < $1.updatedAt }?.id }
        chats[spaceID] = stored
        saveChats(spaceID)
    }

    /// Changes one conversation in place. Nothing is written to disk until `saveChats`.
    func updateThread(_ id: UUID, in spaceID: UUID, _ change: (inout ChatThread) -> Void) {
        var stored = loadChats(spaceID)
        guard let index = stored.threads.firstIndex(where: { $0.id == id }) else { return }
        change(&stored.threads[index])
        chats[spaceID] = stored
    }

    func updateMessage(_ messageID: UUID, thread: UUID, in spaceID: UUID, _ change: (inout ChatMessage) -> Void) {
        updateThread(thread, in: spaceID) { thread in
            guard let index = thread.messages.firstIndex(where: { $0.id == messageID }) else { return }
            change(&thread.messages[index])
        }
    }

    // MARK: Shared memory

    func memory(for accountID: UUID) -> [MemoryItem] {
        if let loaded = memories[accountID] { return loaded }
        let loaded = Self.read([MemoryItem].self, at: directory.appendingPathComponent(Self.memoryFile(for: accountID))) ?? []
        memories[accountID] = loaded
        return loaded
    }

    private func setMemory(_ items: [MemoryItem], for accountID: UUID) {
        memories[accountID] = items
        write(items, to: Self.memoryFile(for: accountID))
    }

    @discardableResult
    func remember(_ text: String, author: String, for accountID: UUID) -> MemoryItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var items = memory(for: accountID)
        if let existing = items.first(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) { return existing }
        let item = MemoryItem(text: trimmed, author: author)
        items.append(item)
        setMemory(items, for: accountID)
        return item
    }

    func forget(_ id: UUID, for accountID: UUID) {
        setMemory(memory(for: accountID).filter { $0.id != id }, for: accountID)
    }

    func editMemory(_ id: UUID, text: String, for accountID: UUID) {
        var items = memory(for: accountID)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = text
        setMemory(items, for: accountID)
    }

    // MARK: Skills

    func skill(named name: String) -> AISkill? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        return settings.skills.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    private static func starterSkills() -> [AISkill] {
        [
            AISkill(name: L("Summarise", "요약"),
                    summary: L("The open node in a few lines, then what is still open.", "열린 노드를 몇 줄로, 그리고 아직 남은 질문"),
                    instructions: L("Read the open node (and anything it links to that matters). Reply with: a summary of at most five bullet points, then a short list of open questions or gaps. Do not change any node.",
                                    "열린 노드(그리고 중요한 링크 대상)를 읽으세요. 다섯 개 이하의 글머리표 요약과, 아직 답이 없는 질문이나 빈틈의 짧은 목록으로 답하세요. 노드는 수정하지 마세요.")),
            AISkill(name: L("Action plan", "액션 플랜"),
                    summary: L("Concrete next steps pulled out of a node.", "노드에서 구체적인 다음 할 일 뽑기"),
                    instructions: L("Read the open node and pull out concrete next actions: each one a single sentence starting with a verb, ordered by what unblocks the most. Show the list first; if the user agrees, append it to the node under a heading “Next steps”.",
                                    "열린 노드를 읽고 구체적인 다음 행동을 뽑으세요. 각 항목은 동사로 시작하는 한 문장으로, 가장 많은 것을 풀어 주는 순서로 정렬합니다. 먼저 목록을 보여 주고, 사용자가 동의하면 노드 끝에 ‘다음 단계’ 제목으로 덧붙이세요.")),
            AISkill(name: L("Save as a node", "노드로 정리"),
                    summary: L("Turn this conversation into a clean node.", "이 대화를 깔끔한 노드로 정리"),
                    instructions: L("Turn what was worked out in this conversation into one well-organised node: a clear title, short headed sections, no chat filler. Create it with create_node, in the same category as the open node when there is one, and say where it is.",
                                    "이 대화에서 정리된 내용을 잘 짜인 노드 하나로 만드세요. 분명한 제목, 짧은 소제목 구획, 대화체 군더더기 없이. create_node로 만들고, 열린 노드가 있으면 같은 카테고리에 넣은 뒤 어디에 만들었는지 알려 주세요.")),
            AISkill(name: L("Find connections", "연결 찾기"),
                    summary: L("Nodes in this Space that belong together.", "이 Space에서 서로 이어질 노드 찾기"),
                    instructions: L("List the nodes in this Space, read the ones that look related to the open node, and propose links between nodes that genuinely inform each other, each with one line of why. Add the links with add_link only for the ones the user accepts.",
                                    "이 Space의 노드를 살펴보고 열린 노드와 관련 있어 보이는 것들을 읽은 뒤, 실제로 서로 도움이 되는 노드 사이의 링크를 이유 한 줄과 함께 제안하세요. 사용자가 받아들인 것만 add_link로 연결하세요.")),
        ]
    }

    // MARK: Clean-up

    /// Removes what a deleted Space or account left behind.
    static func erase(spaceID: UUID, in dataDir: URL) {
        try? FileManager.default.removeItem(at: dataDir.appendingPathComponent("ai/" + chatsFile(for: spaceID)))
    }

    static func erase(accountID: UUID, in dataDir: URL) {
        try? FileManager.default.removeItem(at: dataDir.appendingPathComponent("ai/" + memoryFile(for: accountID)))
    }
}
