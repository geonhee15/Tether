import SwiftUI

extension Font {
    /// The writing typeface, so inserted objects speak in the same voice as the text around them.
    @MainActor
    static func doc(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        AppSettings.shared.editorFont.font(size: size, weight: weight)
    }
}

/// Shared frame for every inserted object. It is drawn as a faint inset in the page — no heavy
/// box — and its controls only appear under the pointer, so at rest it reads like part of the text.
struct EmbedFrame<Accessory: View, Content: View>: View {
    let block: BlockModel
    let node: NodeModel
    let space: SpaceModel
    var symbol: String
    var titlePlaceholder: String
    @Binding var title: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var menuOpen = false

    var body: some View {
        let flashing = ui.flashBlock == block.id
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent.opacity(0.13)))
                TextField(titlePlaceholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(.doc(15.5, .semibold))
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    accessory()
                    AddLinkButton(space: space, anchor: anchor)
                    Menu {
                        Button(L("Move Up", "위로 이동"), systemImage: "arrow.up") { withAnimation(Motion.spring) { node.moveBlock(block.id, by: -1) } }
                        Button(L("Move Down", "아래로 이동"), systemImage: "arrow.down") { withAnimation(Motion.spring) { node.moveBlock(block.id, by: 1) } }
                        Divider()
                        Button(L("Delete", "삭제"), systemImage: "trash", role: .destructive) {
                            withAnimation(Motion.spring) { space.deleteBlock(block.id, in: node) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("More", "더 보기"))
                }
                .opacity(hovering ? 1 : 0)
            }
            content()
            LinkChips(space: space, anchor: anchor)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.embedFill(scheme)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(flashing ? Theme.accent : Theme.cardStroke(scheme).opacity(hovering ? 1.6 : 1), lineWidth: flashing ? 2 : 1)
                .allowsHitTesting(false)
        )
        .shadow(color: flashing ? Theme.accent.opacity(0.35) : .clear, radius: 14)
        .padding(.vertical, 10)
        .onHover { hovering = $0 }
        .animation(Motion.smooth, value: hovering)
    }

    private var anchor: Anchor { Anchor(nodeID: node.id, blockID: block.id) }
}

// MARK: Links

/// "See also" chips for a node or an inserted object; each one jumps to the other end.
struct LinkChips: View {
    let space: SpaceModel
    let anchor: Anchor
    @Environment(AppUI.self) private var ui

    var body: some View {
        let links = space.links(touching: anchor)
        if !links.isEmpty {
            FlowLayout(spacing: 6, alignment: .leading) {
                ForEach(links, id: \.link.id) { entry in
                    LinkChip(symbol: space.symbol(for: entry.other), title: space.title(for: entry.other)) {
                        ui.navigate(to: entry.other, in: space)
                    } onRemove: {
                        withAnimation(Motion.spring) { space.removeLink(entry.link.id) }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }
}

struct LinkChip: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    var tint: Color? = nil
    var onOpen: () -> Void
    var onRemove: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        let color = tint ?? Theme.accent
        HStack(spacing: 5) {
            Image(systemName: "link").font(.system(size: 9, weight: .bold))
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            Text(title).font(.app(11.5, .medium)).lineLimit(1)
            if let detail {
                Text(detail).font(.app(11.5, .semibold)).monospacedDigit()
            }
            if let onRemove, hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .help(L("Remove link", "링크 제거"))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(hovering ? 0.20 : 0.12)))
        .contentShape(Capsule())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .help(L("Go to “\(title)”", "“\(title)”(으)로 이동"))
    }
}

/// Opens the picker to connect this anchor to another node or object.
struct AddLinkButton: View {
    let space: SpaceModel
    let anchor: Anchor
    var labeled = false
    @State private var showing = false

    var body: some View {
        Group {
            if labeled {
                Button { showing = true } label: {
                    Label(L("Link", "링크"), systemImage: "link.badge.plus").font(.app(11.5, .medium))
                }
                .buttonStyle(SoftButtonStyle())
            } else {
                IconButton(symbol: "link.badge.plus", size: 12, help: L("Link to a node or object", "노드나 삽입물에 링크")) { showing = true }
            }
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            LinkPicker(space: space, mode: .anchor(excluding: anchor)) { picked in
                if case .anchor(let target) = picked {
                    withAnimation(Motion.spring) { space.addLink(from: anchor, to: target) }
                }
                showing = false
            }
        }
    }
}

/// Searchable list of everything in the Space that can be linked to.
struct LinkPicker: View {
    enum Mode {
        /// Pick a node or an inserted object.
        case anchor(excluding: Anchor)
        /// Pick a single number: a chart point, a numeric table cell or an analytics score.
        case value(excludingBlock: UUID?)
    }

    enum Pick {
        case anchor(Anchor)
        case value(ValueRef)
    }

    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let indent: Bool
        let pick: Pick?
    }

    let space: SpaceModel
    let mode: Mode
    var onPick: (Pick) -> Void

    @State private var query = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline).font(.app(12, .semibold))
            GlassField(symbol: "magnifyingglass", placeholder: L("Search", "검색"), text: $query)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let rows = filteredRows
                    if rows.isEmpty {
                        Text(emptyText)
                            .font(.app(12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .multilineTextAlignment(.center)
                    }
                    ForEach(rows) { row in
                        PickerRow(symbol: row.symbol, title: row.title, detail: row.detail, indent: row.indent, enabled: row.pick != nil) {
                            if let pick = row.pick { onPick(pick) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, height: 360)
    }

    private var headline: String {
        switch mode {
        case .anchor: return L("Link to…", "링크할 대상")
        case .value: return L("Which value should change?", "어떤 값을 바꿀까요?")
        }
    }

    private var emptyText: String {
        switch mode {
        case .anchor: return L("Nothing to link to yet.\nCreate another node or insert an object.", "아직 링크할 대상이 없어요.\n다른 노드를 만들거나 삽입물을 추가해 보세요.")
        case .value: return L("No values yet.\nInsert a chart, a table with numbers, or another analytics.", "아직 연결할 값이 없어요.\n그래프나 숫자가 있는 표, 다른 애널리틱스를 삽입해 보세요.")
        }
    }

    private var filteredRows: [Row] {
        let rows = allRows
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.pick != nil && ($0.title + " " + $0.detail).lowercased().contains(needle) }
    }

    private var allRows: [Row] {
        var rows: [Row] = []
        for node in space.nodes {
            switch mode {
            case .anchor(let excluded):
                let nodeAnchor = Anchor(nodeID: node.id, blockID: nil)
                var section: [Row] = []
                if nodeAnchor != excluded {
                    section.append(Row(id: node.id.uuidString, symbol: node.symbol, title: node.displayTitle,
                                       detail: L("Node", "노드"), indent: false, pick: .anchor(nodeAnchor)))
                } else {
                    section.append(Row(id: node.id.uuidString, symbol: node.symbol, title: node.displayTitle, detail: "", indent: false, pick: nil))
                }
                for block in node.blocks where block.data.isEmbed {
                    let anchor = Anchor(nodeID: node.id, blockID: block.id)
                    guard anchor != excluded else { continue }
                    section.append(Row(id: block.id.uuidString, symbol: space.symbol(for: anchor), title: space.blockTitle(block),
                                       detail: kindName(block.data.kind), indent: true, pick: .anchor(anchor)))
                }
                if section.contains(where: { $0.pick != nil }) { rows.append(contentsOf: section) }
            case .value(let excludedBlock):
                var section: [Row] = []
                for block in node.blocks where block.data.isEmbed && block.id != excludedBlock {
                    let anchor = Anchor(nodeID: node.id, blockID: block.id)
                    let title = space.blockTitle(block)
                    switch block.data.kind {
                    case .analytics:
                        let score = space.score(of: block, in: node).value
                        section.append(Row(id: block.id.uuidString, symbol: space.symbol(for: anchor), title: title + " › " + L("Score", "점수"),
                                           detail: formatNumber(score), indent: true,
                                           pick: .value(ValueRef(nodeID: node.id, blockID: block.id, itemID: nil))))
                    case .chart:
                        for point in block.data.chart?.points ?? [] {
                            section.append(Row(id: point.id.uuidString, symbol: space.symbol(for: anchor),
                                               title: title + " › " + (point.label.isEmpty ? "?" : point.label),
                                               detail: formatNumber(point.value), indent: true,
                                               pick: .value(ValueRef(nodeID: node.id, blockID: block.id, itemID: point.id))))
                        }
                    case .table:
                        guard let table = block.data.table else { continue }
                        for row in table.rows {
                            for cell in row where Double(cell.text.trimmingCharacters(in: .whitespaces)) != nil {
                                section.append(Row(id: cell.id.uuidString, symbol: "tablecells",
                                                   title: title + " › " + (table.label(forCell: cell.id) ?? "?"),
                                                   detail: cell.text, indent: true,
                                                   pick: .value(ValueRef(nodeID: node.id, blockID: block.id, itemID: cell.id))))
                            }
                        }
                    case .text:
                        break
                    }
                }
                if !section.isEmpty {
                    rows.append(Row(id: node.id.uuidString, symbol: node.symbol, title: node.displayTitle, detail: "", indent: false, pick: nil))
                    rows.append(contentsOf: section)
                }
            }
        }
        return rows
    }

    private func kindName(_ kind: Block.Kind) -> String {
        switch kind {
        case .table: return L("Table", "표")
        case .chart: return L("Chart", "그래프")
        case .analytics: return L("Analytics", "애널리틱스")
        case .text: return ""
        }
    }
}

private struct PickerRow: View {
    var symbol: String
    var title: String
    var detail: String
    var indent: Bool
    var enabled: Bool
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(title)
                .font(.app(12.5, enabled ? .regular : .semibold))
                .foregroundStyle(enabled ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(detail).font(.app(11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .padding(.leading, indent ? 18 : 6)
        .padding(.trailing, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering && enabled ? Theme.hoverFill(scheme) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { action() } }
        .onHover { hovering = $0 }
    }
}

/// Dates in the app's language rather than the system's.
@MainActor
func formatDate(_ value: Date, date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
    let locale = Locale(identifier: AppSettings.shared.language == .ko ? "ko_KR" : "en_US")
    return value.formatted(Date.FormatStyle(date: date, time: time, locale: locale))
}

/// Trims trailing zeros: 12, 12.5, 12.25.
func formatNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e12 { return String(Int(value)) }
    return String(format: "%.2f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
}

/// "+5" / "−3".
func formatDelta(_ value: Double) -> String {
    (value >= 0 ? "+" : "−") + formatNumber(abs(value))
}

/// Notes under a chart or table listing which actions currently feed its values.
struct ContributionNotes: View {
    let space: SpaceModel
    var entries: [(label: String, contribution: Contribution)]
    @Environment(AppUI.self) private var ui

    var body: some View {
        if !entries.isEmpty {
            FlowLayout(spacing: 6, alignment: .leading) {
                ForEach(entries, id: \.contribution.id) { entry in
                    let c = entry.contribution
                    LinkChip(symbol: c.done ? "checkmark.circle.fill" : "circle.dashed",
                             title: entry.label + " ← " + c.sourceName + " · " + c.actionTitle,
                             detail: formatDelta(c.delta),
                             tint: c.done ? Theme.accent : .secondary) {
                        ui.navigate(to: c.source, in: space)
                    }
                    .opacity(c.done ? 1 : 0.75)
                }
            }
        }
    }
}
