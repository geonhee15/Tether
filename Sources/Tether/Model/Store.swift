import CryptoKit
import Foundation
import Observation

enum AuthError: Error {
    case emptyFields, usernameTaken, unknownUser, wrongPassword, limitReached, passwordMismatch

    @MainActor var message: String {
        switch self {
        case .emptyFields: return L("Enter a username and a password.", "유저네임과 비밀번호를 입력해 주세요.")
        case .usernameTaken: return L("That username is already in use.", "이미 사용 중인 유저네임이에요.")
        case .unknownUser: return L("No account with that username.", "해당 유저네임의 계정이 없어요.")
        case .wrongPassword: return L("That password doesn't match.", "비밀번호가 일치하지 않아요.")
        case .passwordMismatch: return L("The two passwords don't match.", "두 비밀번호가 서로 달라요.")
        case .limitReached: return L("You can keep up to \(AppInfo.maxAccounts) accounts.", "계정은 최대 \(AppInfo.maxAccounts)개까지 만들 수 있어요.")
        }
    }
}

/// Accounts, sessions and every signed-in Space, persisted as JSON under Application Support.
/// Saving is driven by Observation: any change to a Space schedules a debounced write.
@MainActor
@Observable
final class Store {
    @ObservationIgnored let dataDir: URL
    var accounts: [Account] = []
    var session = SessionState()
    var spaces: [UUID: SpaceModel] = [:]
    var lastSaved: Date?

    @ObservationIgnored private var saveTimers: [UUID: Timer] = [:]
    @ObservationIgnored private var histories: [UUID: SpaceHistory] = [:]
    @ObservationIgnored private var signatures: [UUID: Int] = [:]

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

    init() {
        if let custom = ProcessInfo.processInfo.environment["TETHER_DATA_DIR"], !custom.isEmpty {
            dataDir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            dataDir = base.appendingPathComponent("Tether", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dataDir.appendingPathComponent("spaces"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dataDir.appendingPathComponent("files"), withIntermediateDirectories: true)
        accounts = read([Account].self, from: "accounts.json") ?? []
        session = read(SessionState.self, from: "session.json") ?? SessionState()
        let known = Set(accounts.map(\.id))
        session.loggedIn = session.loggedIn.filter(known.contains)
        if let active = session.active, !session.loggedIn.contains(active) { session.active = session.loggedIn.first }
        if session.active == nil { session.active = session.loggedIn.first }
        for id in session.loggedIn { loadSpace(id) }
    }

    // MARK: Lookups

    var activeSpace: SpaceModel? { session.active.flatMap { spaces[$0] } }

    var loggedInSpaces: [SpaceModel] { session.loggedIn.compactMap { spaces[$0] } }

    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }

    var canAddAccount: Bool { accounts.count < AppInfo.maxAccounts }

    /// Accounts that exist on this Mac but are not signed in right now.
    var signedOutAccounts: [Account] { accounts.filter { !session.loggedIn.contains($0.id) } }

    // MARK: Auth

    func signUp(username: String, password: String, email: String) throws {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { throw AuthError.emptyFields }
        guard accounts.count < AppInfo.maxAccounts else { throw AuthError.limitReached }
        guard !accounts.contains(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) else { throw AuthError.usernameTaken }
        let salt = Self.makeSalt()
        let account = Account(username: name, email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                              passwordSalt: salt, passwordHash: Self.hash(password, salt: salt))
        accounts.append(account)
        let info = SpaceInfo(name: name, colorIndex: (accounts.count - 1) % Theme.spaceColors.count)
        let space = SpaceModel(id: account.id, snapshot: SpaceSnapshot(info: info))
        spaces[account.id] = space
        session.loggedIn.append(account.id)
        session.active = account.id
        persistAccounts()
        histories[account.id] = SpaceHistory(space)
        save(space)
        watch(space)
    }

    func signIn(username: String, password: String) throws {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { throw AuthError.emptyFields }
        guard let account = accounts.first(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) else { throw AuthError.unknownUser }
        guard Self.hash(password, salt: account.passwordSalt) == account.passwordHash else { throw AuthError.wrongPassword }
        if !session.loggedIn.contains(account.id) {
            session.loggedIn.append(account.id)
            loadSpace(account.id)
        }
        session.active = account.id
        persistAccounts()
    }

    func account(named username: String) -> Account? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.first { $0.username.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Replaces an account's password (fresh salt). Callers decide who is allowed to do this:
    /// the signed-in owner, or someone who just proved they own this Mac.
    func setPassword(for id: UUID, to password: String) throws {
        guard !password.isEmpty else { throw AuthError.emptyFields }
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw AuthError.unknownUser }
        let salt = Self.makeSalt()
        accounts[index].passwordSalt = salt
        accounts[index].passwordHash = Self.hash(password, salt: salt)
        persistAccounts()
    }

    func switchTo(_ id: UUID) {
        guard session.loggedIn.contains(id) else { return }
        session.active = id
        persistAccounts()
    }

    func logOut(_ id: UUID) {
        if let space = spaces[id] { flush(space, closing: true) }
        spaces[id] = nil
        histories[id] = nil
        session.loggedIn.removeAll { $0 == id }
        if session.active == id { session.active = session.loggedIn.first }
        persistAccounts()
    }

    /// Removes the account and its Space file for good.
    func deleteAccount(_ id: UUID) {
        saveTimers[id]?.invalidate()
        saveTimers[id] = nil
        spaces[id] = nil
        histories[id] = nil
        session.loggedIn.removeAll { $0 == id }
        if session.active == id { session.active = session.loggedIn.first }
        accounts.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: spaceURL(id))
        try? FileManager.default.removeItem(at: filesDirectory(for: id))
        persistAccounts()
    }

    private static func makeSalt() -> String {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    }

    /// Salted, stretched SHA-256. The data never leaves this Mac; this just avoids storing the password itself.
    private static func hash(_ password: String, salt: String) -> String {
        var digest = Data(SHA256.hash(data: Data((salt + password).utf8)))
        for _ in 0..<20_000 { digest = Data(SHA256.hash(data: digest)) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Persistence

    private func spaceURL(_ id: UUID) -> URL {
        dataDir.appendingPathComponent("spaces/\(id.uuidString).json")
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: dataDir.appendingPathComponent(name)) else { return nil }
        return try? Self.decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func persistAccounts() {
        write(accounts, to: dataDir.appendingPathComponent("accounts.json"))
        write(session, to: dataDir.appendingPathComponent("session.json"))
    }

    private func loadSpace(_ id: UUID) {
        guard spaces[id] == nil, let account = account(id) else { return }
        let snapshot: SpaceSnapshot
        if let data = try? Data(contentsOf: spaceURL(id)), let decoded = try? Self.decoder.decode(SpaceSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = SpaceSnapshot(info: SpaceInfo(name: account.username))
        }
        let space = SpaceModel(id: id, snapshot: snapshot)
        spaces[id] = space
        for node in space.nodes { signatures[node.id] = signature(of: node) }
        histories[id] = SpaceHistory(space)
        purgeOrphanFiles(in: space)
        watch(space)
    }

    // MARK: Files

    /// Where a Space keeps the files added to it.
    func filesDirectory(for spaceID: UUID) -> URL {
        dataDir.appendingPathComponent("files/\(spaceID.uuidString)", isDirectory: true)
    }

    func fileURL(for file: FileAttachment, in space: SpaceModel) -> URL {
        filesDirectory(for: space.id).appendingPathComponent(file.storedName)
    }

    /// Copies a file into the Space and opens it as a node.
    @discardableResult
    func importFile(at source: URL, into space: SpaceModel) throws -> NodeModel {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let directory = filesDirectory(for: space.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension
        let storedName = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(storedName))
        let file = FileAttachment(storedName: storedName, originalName: source.lastPathComponent, byteCount: values.fileSize ?? 0)
        return space.addFileNode(file)
    }

    /// Deletes stored files no node points at any more. Deleting a file node keeps its file so
    /// Undo can bring it back; the leftovers are cleared when the undo history is gone
    /// (at launch, at sign-out and at quit).
    func purgeOrphanFiles(in space: SpaceModel) {
        let directory = filesDirectory(for: space.id)
        guard let stored = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let used = Set(space.nodes.compactMap { $0.file?.storedName })
        for name in stored where !used.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Registers for the next change anywhere in the Space. Observation fires once per
    /// registration, so the handler re-registers and every later change is seen too.
    private func watch(_ space: SpaceModel) {
        withObservationTracking {
            _ = space.snapshot()
        } onChange: { [weak self, weak space] in
            DispatchQueue.main.async {
                guard let self, let space, self.spaces[space.id] === space else { return }
                self.watch(space)
                self.scheduleSave(space)
                self.histories[space.id]?.noteChange(in: space)
            }
        }
    }

    // MARK: Undo

    /// Steps the Space back by one edit. False when there is nothing to undo.
    @discardableResult
    func undo(in space: SpaceModel) -> Bool {
        histories[space.id]?.undo(space) ?? false
    }

    @discardableResult
    func redo(in space: SpaceModel) -> Bool {
        histories[space.id]?.redo(space) ?? false
    }

    /// Starts the Space's undo history afresh from its current state.
    func resetHistory(for space: SpaceModel) {
        histories[space.id]?.reset(space)
    }

    private func scheduleSave(_ space: SpaceModel) {
        saveTimers[space.id]?.invalidate()
        saveTimers[space.id] = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self, weak space] _ in
            DispatchQueue.main.async {
                guard let self, let space, self.spaces[space.id] === space else { return }
                self.save(space)
            }
        }
    }

    private func signature(of node: NodeModel) -> Int {
        var hasher = Hasher()
        hasher.combine(node.title)
        hasher.combine(node.symbol)
        if let data = try? Self.encoder.encode(node.blocks.map(\.data)) { hasher.combine(data) }
        return hasher.finalize()
    }

    func save(_ space: SpaceModel) {
        saveTimers[space.id]?.invalidate()
        saveTimers[space.id] = nil
        for node in space.nodes {
            let current = signature(of: node)
            if let previous = signatures[node.id], previous != current { node.updatedAt = Date() }
            signatures[node.id] = current
        }
        write(space.snapshot(), to: spaceURL(space.id))
        persistAccounts()
        lastSaved = Date()
    }

    /// Writes a Space out now. `closing` means its undo history ends here (sign-out or quit),
    /// so files that only Undo could still bring back are removed too.
    private func flush(_ space: SpaceModel, closing: Bool = false) {
        if closing {
            histories[space.id]?.reset(space)
            purgeOrphanFiles(in: space)
        }
        save(space)
        saveTimers[space.id]?.invalidate()
        saveTimers[space.id] = nil
    }

    /// Writes everything out now. Pass `closing: true` when the app is quitting.
    func flushAll(closing: Bool = false) {
        for space in spaces.values { flush(space, closing: closing) }
        persistAccounts()
    }

    /// Copies the whole data folder to a destination the user picked.
    func exportBackup(to destination: URL) throws {
        flushAll()
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: dataDir, to: destination)
    }
}
