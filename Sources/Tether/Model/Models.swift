import Foundation

// MARK: Accounts

/// A local account. An account owns up to `AppInfo.maxSpaces` Spaces.
struct Account: Codable, Identifiable, Equatable {
    var id: UUID
    var username: String
    var email: String
    var passwordSalt: String
    var passwordHash: String
    var createdAt: Date
    /// The account's Spaces, in the order they appear in the rail. Never empty.
    var spaceIDs: [UUID]
    /// The Space shown when this account is in front.
    var activeSpace: UUID?

    init(username: String, email: String = "", passwordSalt: String, passwordHash: String) {
        let id = UUID()
        self.id = id
        self.username = username
        self.email = email
        self.passwordSalt = passwordSalt
        self.passwordHash = passwordHash
        createdAt = Date()
        // The first Space shares the account's identifier, which is also how accounts saved
        // before an account could hold several Spaces are read.
        spaceIDs = [id]
        activeSpace = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        passwordSalt = try c.decode(String.self, forKey: .passwordSalt)
        passwordHash = try c.decode(String.self, forKey: .passwordHash)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let saved = try c.decodeIfPresent([UUID].self, forKey: .spaceIDs) ?? []
        spaceIDs = saved.isEmpty ? [id] : saved
        activeSpace = try c.decodeIfPresent(UUID.self, forKey: .activeSpace)
    }
}

/// Which accounts are signed in right now (several can be at once) and which one is in front.
struct SessionState: Codable, Equatable {
    var loggedIn: [UUID] = []
    var active: UUID?
}

// MARK: Space

struct SpaceInfo: Codable, Equatable {
    var name: String
    var subtitle: String = ""
    var about: String = ""
    var symbol: String = "sparkles"
    var colorIndex: Int = 0
    /// False until the owner has gone through the first-run Space setup.
    var isConfigured = false
}

/// A named group of nodes inside a Space.
struct NodeCategory: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colorIndex: Int = 0
}

/// Everything a Space stores on disk.
struct SpaceSnapshot: Codable {
    var info: SpaceInfo
    var nodes: [NodeDoc] = []
    var links: [RefLink] = []
    var categories: [NodeCategory] = []
    var openTabs: [UUID] = []
    var activeTab: UUID?
    /// Categories folded shut on the Space home.
    var collapsedCategories: [UUID] = []

    init(info: SpaceInfo, nodes: [NodeDoc] = [], links: [RefLink] = [], categories: [NodeCategory] = [],
         openTabs: [UUID] = [], activeTab: UUID? = nil, collapsedCategories: [UUID] = []) {
        self.info = info
        self.nodes = nodes
        self.links = links
        self.categories = categories
        self.openTabs = openTabs
        self.activeTab = activeTab
        self.collapsedCategories = collapsedCategories
    }

    /// Keys added after the first release are optional, so older files keep opening.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        info = try c.decode(SpaceInfo.self, forKey: .info)
        nodes = try c.decodeIfPresent([NodeDoc].self, forKey: .nodes) ?? []
        links = try c.decodeIfPresent([RefLink].self, forKey: .links) ?? []
        categories = try c.decodeIfPresent([NodeCategory].self, forKey: .categories) ?? []
        openTabs = try c.decodeIfPresent([UUID].self, forKey: .openTabs) ?? []
        activeTab = try c.decodeIfPresent(UUID.self, forKey: .activeTab)
        collapsedCategories = try c.decodeIfPresent([UUID].self, forKey: .collapsedCategories) ?? []
    }
}

// MARK: Nodes & blocks

struct NodeDoc: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var symbol: String = "doc.text"
    var createdAt = Date()
    var updatedAt = Date()
    /// A written node's page; on a file node, the notes kept beside the file.
    var blocks: [Block] = [Block(kind: .text)]
    /// Set when this node shows a file instead of a written page.
    var file: FileAttachment?
    /// The category this node is filed under, if any.
    var categoryID: UUID?
}

/// A file kept inside the Space. The bytes are copied into the Space's own folder, so the node
/// keeps working if the original is moved or deleted.
struct FileAttachment: Codable, Equatable {
    /// Name of the copy on disk (`<uuid>.<extension>`).
    var storedName: String
    /// The file's name when it was added, extension included.
    var originalName: String
    var byteCount: Int
    var addedAt = Date()

    var fileExtension: String { (originalName as NSString).pathExtension.lowercased() }

    enum Category { case pdf, image, video, audio, text, code, spreadsheet, presentation, document, archive, other }

    var category: Category {
        switch fileExtension {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "webp", "bmp", "svg", "psd": return .image
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return .video
        case "mp3", "m4a", "wav", "aac", "flac", "aiff", "ogg": return .audio
        case "txt", "md", "markdown", "rtf", "log": return .text
        case "swift", "py", "js", "ts", "json", "html", "css", "c", "h", "cpp", "java", "kt", "rs", "go", "rb", "sh", "yml", "yaml", "xml", "sql":
            return .code
        case "xlsx", "xls", "numbers", "csv", "tsv": return .spreadsheet
        case "pptx", "ppt", "key": return .presentation
        case "docx", "doc", "pages", "hwp", "hwpx", "odt": return .document
        case "zip", "tar", "gz", "7z", "rar", "dmg": return .archive
        default: return .other
        }
    }

    var symbol: String {
        switch category {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        case .document: return "doc.text"
        case .archive: return "doc.zipper"
        case .other: return "doc"
        }
    }

    /// "PDF · 1.2 MB"
    var summary: String {
        let kind = fileExtension.isEmpty ? "FILE" : fileExtension.uppercased()
        return kind + " · " + ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

/// One piece of a node: a run of rich text, or an inserted object.
struct Block: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, table, chart, analytics }

    var id = UUID()
    var kind: Kind
    var runs: [TextRun]?
    var table: TableData?
    var chart: ChartData?
    var analytics: AnalyticsData?

    var isEmbed: Bool { kind != .text }

    /// Title shown in link chips and pickers.
    var displayTitle: String {
        switch kind {
        case .text: return ""
        case .table: return table?.title ?? ""
        case .chart: return chart?.title ?? ""
        case .analytics: return analytics?.name ?? ""
        }
    }
}

/// A stretch of text sharing one style. Short keys keep the saved JSON small.
struct TextRun: Codable, Equatable {
    var t: String
    var b: Bool?        // bold
    var i: Bool?        // italic
    var u: Bool?        // underline
    var s: Bool?        // strikethrough
    var c: String?      // text colour (hex RRGGBBAA); nil follows light/dark
    var h: String?      // highlight colour
    var f: String?      // font family choice; nil follows the app setting
    var z: Double?      // point size; nil follows the app setting
    var a: Int?         // paragraph alignment: 0 leading, 1 centre, 2 trailing

    func sameStyle(as other: TextRun) -> Bool {
        b == other.b && i == other.i && u == other.u && s == other.s && c == other.c
            && h == other.h && f == other.f && z == other.z && a == other.a
    }
}

// MARK: Table

struct TableCell: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
}

struct TableData: Codable, Equatable {
    var title = ""
    var hasHeader = true
    var rows: [[TableCell]]

    static func blank(rows: Int = 3, columns: Int = 3) -> TableData {
        TableData(rows: (0..<rows).map { _ in (0..<columns).map { _ in TableCell() } })
    }

    var columnCount: Int { rows.first?.count ?? 0 }

    /// Header text for the column a cell sits in (used to name link targets).
    func label(forCell id: UUID) -> String? {
        for (r, row) in rows.enumerated() {
            guard let c = row.firstIndex(where: { $0.id == id }) else { continue }
            let column = hasHeader ? (rows.first?[c].text ?? "") : ""
            let rowName = c > 0 ? row[0].text : ""
            let parts = [rowName, column].filter { !$0.isEmpty }
            return parts.isEmpty ? "R\(r + 1)·C\(c + 1)" : parts.joined(separator: " · ")
        }
        return nil
    }
}

// MARK: Chart

enum ChartStyle: String, Codable, CaseIterable, Identifiable {
    case pie, bar, line
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .pie: return "chart.pie"
        case .bar: return "chart.bar"
        case .line: return "chart.xyaxis.line"
        }
    }
}

struct ChartPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var value: Double
    /// Fixed palette slot, assigned once so a point keeps its colour when others come and go.
    var colorSlot: Int
}

struct ChartData: Codable, Equatable {
    var title = ""
    var style: ChartStyle
    var points: [ChartPoint]

    /// Lowest palette slot no point is using yet.
    var nextColorSlot: Int {
        let used = Set(points.map(\.colorSlot))
        return (0..<8).first { !used.contains($0) } ?? points.count % 8
    }
}

// MARK: Analytics

struct Tag: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var text = ""
    /// -1 negative, 0 neutral, 1 positive.
    var impact = 0
}

/// Points at one number somewhere in the Space: an analytics score (`itemID == nil`),
/// a chart point or a table cell.
struct ValueRef: Codable, Hashable {
    var nodeID: UUID
    var blockID: UUID
    var itemID: UUID?
}

/// "When this action is done, add `delta` to that value."
struct LinkEffect: Codable, Identifiable, Equatable {
    var id = UUID()
    var target: ValueRef
    var delta: Double = 10
}

/// A condition to work towards, e.g. "do X three times".
struct ActionItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var target = 1
    var progress = 0
    /// Added to this analytics' own score once the action is complete.
    var scoreDelta: Double = 5
    var effects: [LinkEffect] = []

    var isDone: Bool { progress >= max(1, target) }
}

struct AnalyticsData: Codable, Equatable {
    var name = ""
    var relation = ""
    /// The owner's own starting assessment, 0…100.
    var baseScore: Double = 50
    var traits: [Tag] = []
    var likes: [Tag] = []
    var cautions: [Tag] = []
    var attitude = ""
    var observations: [LogEntry] = []
    var actions: [ActionItem] = []
}

// MARK: Reference links

/// A node, or one inserted object inside a node.
struct Anchor: Codable, Hashable {
    var nodeID: UUID
    var blockID: UUID?
}

/// A two-way "see also" connection between nodes and/or inserted objects.
struct RefLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: Anchor
    var to: Anchor
}
