import Foundation

// MARK: Accounts

/// A local account. Each account owns exactly one Space.
struct Account: Codable, Identifiable, Equatable {
    var id = UUID()
    var username: String
    var email: String = ""
    var passwordSalt: String
    var passwordHash: String
    var createdAt = Date()
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

/// Everything a Space stores on disk.
struct SpaceSnapshot: Codable {
    var info: SpaceInfo
    var nodes: [NodeDoc] = []
    var links: [RefLink] = []
    var openTabs: [UUID] = []
    var activeTab: UUID?
}

// MARK: Nodes & blocks

struct NodeDoc: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var symbol: String = "doc.text"
    var createdAt = Date()
    var updatedAt = Date()
    var blocks: [Block] = [Block(kind: .text)]
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
