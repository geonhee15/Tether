import Foundation
import Observation
import SwiftUI

/// Live, observable wrapper around one block so editing it only redraws that block.
@MainActor
@Observable
final class BlockModel: Identifiable {
    let id: UUID
    var data: Block
    /// Bumped when the text is replaced from outside the text view (split, merge, restyle) so the editor reloads it.
    var revision = 0

    init(_ data: Block) {
        id = data.id
        self.data = data
    }

    var plainText: String { (data.runs ?? []).map(\.t).joined() }
}

@MainActor
@Observable
final class NodeModel: Identifiable {
    let id: UUID
    var title: String
    var symbol: String
    var createdAt: Date
    var updatedAt: Date
    var blocks: [BlockModel]

    init(_ doc: NodeDoc) {
        id = doc.id
        title = doc.title
        symbol = doc.symbol
        createdAt = doc.createdAt
        updatedAt = doc.updatedAt
        blocks = doc.blocks.map(BlockModel.init)
        if blocks.isEmpty { blocks = [BlockModel(Block(kind: .text))] }
    }

    var snapshot: NodeDoc {
        NodeDoc(id: id, title: title, symbol: symbol, createdAt: createdAt, updatedAt: updatedAt, blocks: blocks.map(\.data))
    }

    var displayTitle: String { title.isEmpty ? L("Untitled", "제목 없음") : title }

    func block(_ id: UUID) -> BlockModel? { blocks.first { $0.id == id } }

    var plainText: String {
        blocks.filter { $0.data.kind == .text }.map(\.plainText).joined(separator: "\n")
    }

    var preview: String {
        let text = plainText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.prefix(3).joined(separator: " · ")
        return String(text.prefix(140))
    }

    var wordCount: Int {
        plainText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var embedKinds: [Block.Kind] { blocks.map(\.data.kind).filter { $0 != .text } }

    /// Removes an inserted object and stitches the text around it back into one block.
    func removeBlock(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let before = index > 0 ? blocks[index - 1] : nil
        let after = index + 1 < blocks.count ? blocks[index + 1] : nil
        if let before, let after, before.data.kind == .text, after.data.kind == .text {
            var runs = before.data.runs ?? []
            let tail = after.data.runs ?? []
            if !runs.isEmpty, !tail.isEmpty { runs.append(TextRun(t: "\n")) }
            runs.append(contentsOf: tail)
            before.data.runs = runs
            before.revision += 1
            blocks.removeSubrange(index...(index + 1))
        } else {
            blocks.remove(at: index)
        }
        if blocks.isEmpty { blocks = [BlockModel(Block(kind: .text))] }
    }

    /// Brings this node in line with a saved state, reusing the live blocks so views keep their place.
    func apply(_ doc: NodeDoc) {
        if title != doc.title { title = doc.title }
        if symbol != doc.symbol { symbol = doc.symbol }
        let existing = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        var result: [BlockModel] = []
        for data in doc.blocks {
            if let block = existing[data.id] {
                if block.data != data {
                    block.data = data
                    block.revision += 1   // tells a text view to reload what it shows
                }
                result.append(block)
            } else {
                result.append(BlockModel(data))
            }
        }
        if result.isEmpty { result = [BlockModel(Block(kind: .text))] }
        if result.map(\.id) != blocks.map(\.id) { blocks = result }
    }

    func moveBlock(_ id: UUID, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        // Skip over the neighbouring text so an object trades places with the next object-or-text unit.
        let target = index + offset
        guard blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
    }
}

/// One satisfied-or-pending "action → value" link, seen from the value's side.
struct Contribution: Identifiable {
    let id: UUID
    let delta: Double
    let actionTitle: String
    let sourceName: String
    let source: Anchor
    let done: Bool
}

struct ScoreBreakdown {
    var base: Double
    var earned: Double      // own completed actions
    var linked: Double      // completed actions elsewhere that point here
    var potential: Double   // everything still pending

    var value: Double { min(100, max(0, base + earned + linked)) }
    var projected: Double { min(100, max(0, base + earned + linked + potential)) }
    var gap: Double { max(0, 100 - projected) }
}

@MainActor
@Observable
final class SpaceModel: Identifiable {
    let id: UUID
    var info: SpaceInfo
    var nodes: [NodeModel]
    var links: [RefLink]
    var openTabs: [UUID]
    /// nil shows the Space home.
    var activeTab: UUID?

    init(id: UUID, snapshot: SpaceSnapshot) {
        self.id = id
        info = snapshot.info
        nodes = snapshot.nodes.map(NodeModel.init)
        links = snapshot.links
        let known = Set(snapshot.nodes.map(\.id))
        openTabs = snapshot.openTabs.filter(known.contains)
        activeTab = snapshot.activeTab.flatMap { known.contains($0) ? $0 : nil }
    }

    func snapshot() -> SpaceSnapshot {
        SpaceSnapshot(info: info, nodes: nodes.map(\.snapshot), links: links, openTabs: openTabs, activeTab: activeTab)
    }

    /// Replaces settings, nodes and links with a saved state (Undo / Redo). Live node and block
    /// objects are reused wherever they still exist, so the interface updates instead of rebuilding.
    func apply(_ content: SpaceContent) {
        var restoredInfo = content.info
        restoredInfo.isConfigured = info.isConfigured
        if info != restoredInfo { info = restoredInfo }
        let existing = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result: [NodeModel] = []
        for doc in content.nodes {
            if let node = existing[doc.id] {
                node.apply(doc)
                result.append(node)
            } else {
                var revived = doc
                revived.updatedAt = Date()
                result.append(NodeModel(revived))
            }
        }
        if result.map(\.id) != nodes.map(\.id) { nodes = result }
        if links != content.links { links = content.links }
        let known = Set(result.map(\.id))
        if openTabs.contains(where: { !known.contains($0) }) { openTabs = openTabs.filter(known.contains) }
        if let active = activeTab, !known.contains(active) { activeTab = openTabs.last }
    }

    var color: Color { Theme.spaceColor(info.colorIndex) }

    func node(_ id: UUID?) -> NodeModel? {
        guard let id else { return nil }
        return nodes.first { $0.id == id }
    }

    var activeNode: NodeModel? { node(activeTab) }

    // MARK: Nodes & tabs

    @discardableResult
    func addNode() -> NodeModel {
        let node = NodeModel(NodeDoc())
        nodes.append(node)
        openTabs.append(node.id)
        activeTab = node.id
        return node
    }

    func open(_ nodeID: UUID) {
        guard nodes.contains(where: { $0.id == nodeID }) else { return }
        if !openTabs.contains(nodeID) { openTabs.append(nodeID) }
        activeTab = nodeID
    }

    func closeTab(_ nodeID: UUID) {
        guard let index = openTabs.firstIndex(of: nodeID) else { return }
        openTabs.remove(at: index)
        if activeTab == nodeID {
            activeTab = openTabs.isEmpty ? nil : openTabs[min(index, openTabs.count - 1)]
        }
    }

    func deleteNode(_ nodeID: UUID) {
        closeTab(nodeID)
        nodes.removeAll { $0.id == nodeID }
        links.removeAll { $0.from.nodeID == nodeID || $0.to.nodeID == nodeID }
        pruneEffects { $0.nodeID == nodeID }
    }

    func deleteBlock(_ blockID: UUID, in node: NodeModel) {
        node.removeBlock(blockID)
        links.removeAll { $0.from.blockID == blockID || $0.to.blockID == blockID }
        pruneEffects { $0.blockID == blockID }
    }

    /// Drops action effects whose target matches (because the target was deleted).
    func pruneEffects(where matches: (ValueRef) -> Bool) {
        for node in nodes {
            for block in node.blocks where block.data.kind == .analytics {
                guard var analytics = block.data.analytics else { continue }
                var changed = false
                for index in analytics.actions.indices {
                    let before = analytics.actions[index].effects.count
                    analytics.actions[index].effects.removeAll { matches($0.target) }
                    if analytics.actions[index].effects.count != before { changed = true }
                }
                if changed { block.data.analytics = analytics }
            }
        }
    }

    // MARK: Value links

    /// Every action effect in the Space, grouped by the value it feeds.
    func contributions() -> [ValueRef: [Contribution]] {
        var result: [ValueRef: [Contribution]] = [:]
        for node in nodes {
            for block in node.blocks where block.data.kind == .analytics {
                guard let analytics = block.data.analytics else { continue }
                let name = analytics.name.isEmpty ? L("Analytics", "애널리틱스") : analytics.name
                for action in analytics.actions {
                    for effect in action.effects {
                        let title = action.title.isEmpty ? L("Untitled action", "이름 없는 액션") : action.title
                        result[effect.target, default: []].append(
                            Contribution(id: effect.id, delta: effect.delta, actionTitle: title, sourceName: name,
                                         source: Anchor(nodeID: node.id, blockID: block.id), done: action.isDone))
                    }
                }
            }
        }
        return result
    }

    func contributions(for ref: ValueRef) -> [Contribution] {
        contributions()[ref] ?? []
    }

    /// Sum of completed effects pointing at a value.
    func linkedDelta(for ref: ValueRef) -> Double {
        contributions(for: ref).filter(\.done).reduce(0) { $0 + $1.delta }
    }

    func score(of block: BlockModel, in node: NodeModel) -> ScoreBreakdown {
        guard let analytics = block.data.analytics else { return ScoreBreakdown(base: 0, earned: 0, linked: 0, potential: 0) }
        let incoming = contributions(for: ValueRef(nodeID: node.id, blockID: block.id, itemID: nil))
        let earned = analytics.actions.filter(\.isDone).reduce(0) { $0 + $1.scoreDelta }
        let pendingOwn = analytics.actions.filter { !$0.isDone }.reduce(0) { $0 + $1.scoreDelta }
        let linked = incoming.filter(\.done).reduce(0) { $0 + $1.delta }
        let pendingLinked = incoming.filter { !$0.done }.reduce(0) { $0 + $1.delta }
        return ScoreBreakdown(base: analytics.baseScore, earned: earned, linked: linked, potential: pendingOwn + pendingLinked)
    }

    func resolve(_ ref: ValueRef) -> (node: NodeModel, block: BlockModel)? {
        guard let node = node(ref.nodeID), let block = node.block(ref.blockID) else { return nil }
        return (node, block)
    }

    /// Human-readable name of a linked value, e.g. "Engagement › Attention".
    func describe(_ ref: ValueRef) -> String {
        guard let (_, block) = resolve(ref) else { return L("Missing target", "대상 없음") }
        let title = blockTitle(block)
        switch block.data.kind {
        case .analytics:
            return title + " › " + L("Score", "점수")
        case .chart:
            let label = block.data.chart?.points.first { $0.id == ref.itemID }?.label ?? "?"
            return title + " › " + (label.isEmpty ? "?" : label)
        case .table:
            let label = ref.itemID.flatMap { block.data.table?.label(forCell: $0) } ?? "?"
            return title + " › " + label
        case .text:
            return title
        }
    }

    func blockTitle(_ block: BlockModel) -> String {
        let title = block.data.displayTitle
        if !title.isEmpty { return title }
        switch block.data.kind {
        case .table: return L("Table", "표")
        case .chart: return L("Chart", "그래프")
        case .analytics: return L("Analytics", "애널리틱스")
        case .text: return L("Text", "텍스트")
        }
    }

    // MARK: Reference links

    func title(for anchor: Anchor) -> String {
        guard let node = node(anchor.nodeID) else { return L("Missing", "없음") }
        guard let blockID = anchor.blockID, let block = node.block(blockID) else { return node.displayTitle }
        return node.displayTitle + " › " + blockTitle(block)
    }

    func symbol(for anchor: Anchor) -> String {
        guard let node = node(anchor.nodeID) else { return "questionmark" }
        guard let blockID = anchor.blockID, let block = node.block(blockID) else { return node.symbol }
        switch block.data.kind {
        case .table: return "tablecells"
        case .chart: return block.data.chart?.style.symbol ?? "chart.bar"
        case .analytics: return "person.crop.circle.badge.checkmark"
        case .text: return "text.alignleft"
        }
    }

    /// Links touching an anchor, each paired with the anchor on the other end.
    func links(touching anchor: Anchor) -> [(link: RefLink, other: Anchor)] {
        links.compactMap { link in
            if link.from == anchor { return (link, link.to) }
            if link.to == anchor { return (link, link.from) }
            return nil
        }
    }

    func addLink(from: Anchor, to: Anchor) {
        guard from != to else { return }
        let exists = links.contains { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }
        if !exists { links.append(RefLink(from: from, to: to)) }
    }

    func removeLink(_ id: UUID) {
        links.removeAll { $0.id == id }
    }

    /// Reference links plus action→value links, as node-to-node pairs (for the home map and counters).
    var connectionCount: Int {
        links.count + contributions().values.reduce(0) { $0 + $1.count }
    }

    var embedCount: Int {
        nodes.reduce(0) { $0 + $1.embedKinds.count }
    }
}
