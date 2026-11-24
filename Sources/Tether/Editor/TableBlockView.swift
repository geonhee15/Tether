import SwiftUI

struct TableBlockView: View {
    let block: BlockModel
    let node: NodeModel
    let space: SpaceModel
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var table: TableData { block.data.table ?? .blank() }

    var body: some View {
        let table = table
        let contributions = space.contributions()
        EmbedFrame(block: block, node: node, space: space, symbol: "tablecells",
                   titlePlaceholder: L("Table title", "표 제목"), title: titleBinding) {
            IconButton(symbol: "rectangle.topthird.inset.filled", size: 12, active: table.hasHeader,
                       help: L("Header row", "머리글 행")) {
                withAnimation(Motion.snappy) { block.data.table?.hasHeader.toggle() }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                grid(table, contributions: contributions)
                HStack(spacing: 8) {
                    Button { withAnimation(Motion.spring) { addRow() } } label: {
                        Label(L("Row", "행"), systemImage: "plus").font(.app(11.5, .medium))
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button { withAnimation(Motion.spring) { addColumn() } } label: {
                        Label(L("Column", "열"), systemImage: "plus").font(.app(11.5, .medium))
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(table.columnCount >= 8)
                    Spacer()
                    Text("\(table.rows.count) × \(table.columnCount)")
                        .font(.app(11)).foregroundStyle(.tertiary).monospacedDigit()
                }
                .opacity(hovering ? 1 : 0)
                .frame(height: hovering ? nil : 0)
                .clipped()
                ContributionNotes(space: space, entries: notes(table, contributions))
            }
        }
        .onHover { inside in withAnimation(Motion.smooth) { hovering = inside } }
    }

    private func grid(_ table: TableData, contributions: [ValueRef: [Contribution]]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { r, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { c, cell in
                        let isHeader = table.hasHeader && r == 0
                        let linked = contributions[ValueRef(nodeID: node.id, blockID: block.id, itemID: cell.id)]?
                            .filter(\.done).reduce(0) { $0 + $1.delta } ?? 0
                        TableCellView(text: cellBinding(r, c), isHeader: isHeader,
                                      effective: effectiveText(cell.text, linked: linked))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isHeader ? Theme.chipFill(scheme) : Color.clear)
                            .contextMenu { cellMenu(r, c) }
                        if c < row.count - 1 {
                            Rectangle().fill(Theme.cardStroke(scheme)).frame(width: 1)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if r < table.rows.count - 1 {
                    Rectangle().fill(Theme.cardStroke(scheme)).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardStroke(scheme).opacity(1.5), lineWidth: 1))
    }

    /// For a numeric cell that an action feeds, the value after the link is applied.
    private func effectiveText(_ text: String, linked: Double) -> String? {
        guard linked != 0, let base = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return formatNumber(base + linked)
    }

    private func notes(_ table: TableData, _ contributions: [ValueRef: [Contribution]]) -> [(label: String, contribution: Contribution)] {
        var result: [(String, Contribution)] = []
        for row in table.rows {
            for cell in row {
                for contribution in contributions[ValueRef(nodeID: node.id, blockID: block.id, itemID: cell.id)] ?? [] {
                    result.append((table.label(forCell: cell.id) ?? "?", contribution))
                }
            }
        }
        return result
    }

    @ViewBuilder
    private func cellMenu(_ r: Int, _ c: Int) -> some View {
        Button(L("Insert Row Above", "위에 행 삽입")) { withAnimation(Motion.spring) { insertRow(at: r) } }
        Button(L("Insert Row Below", "아래에 행 삽입")) { withAnimation(Motion.spring) { insertRow(at: r + 1) } }
        Button(L("Insert Column Left", "왼쪽에 열 삽입")) { withAnimation(Motion.spring) { insertColumn(at: c) } }
        Button(L("Insert Column Right", "오른쪽에 열 삽입")) { withAnimation(Motion.spring) { insertColumn(at: c + 1) } }
        Divider()
        Button(L("Delete Row", "행 삭제"), role: .destructive) { withAnimation(Motion.spring) { deleteRow(r) } }
            .disabled(table.rows.count <= 1)
        Button(L("Delete Column", "열 삭제"), role: .destructive) { withAnimation(Motion.spring) { deleteColumn(c) } }
            .disabled(table.columnCount <= 1)
    }

    // MARK: Editing

    private var titleBinding: Binding<String> {
        Binding(get: { block.data.table?.title ?? "" }, set: { block.data.table?.title = $0 })
    }

    private func cellBinding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(get: {
            guard let rows = block.data.table?.rows, rows.indices.contains(r), rows[r].indices.contains(c) else { return "" }
            return rows[r][c].text
        }, set: { value in
            guard let rows = block.data.table?.rows, rows.indices.contains(r), rows[r].indices.contains(c) else { return }
            block.data.table?.rows[r][c].text = value
        })
    }

    private func addRow() { insertRow(at: table.rows.count) }
    private func addColumn() { insertColumn(at: table.columnCount) }

    private func insertRow(at index: Int) {
        guard var table = block.data.table else { return }
        table.rows.insert((0..<max(1, table.columnCount)).map { _ in TableCell() }, at: min(index, table.rows.count))
        block.data.table = table
    }

    private func insertColumn(at index: Int) {
        guard var table = block.data.table, table.columnCount < 8 else { return }
        for r in table.rows.indices { table.rows[r].insert(TableCell(), at: min(index, table.rows[r].count)) }
        block.data.table = table
    }

    private func deleteRow(_ index: Int) {
        guard var table = block.data.table, table.rows.count > 1, table.rows.indices.contains(index) else { return }
        let removed = Set(table.rows[index].map(\.id))
        table.rows.remove(at: index)
        block.data.table = table
        space.pruneEffects { ref in ref.itemID.map(removed.contains) ?? false }
    }

    private func deleteColumn(_ index: Int) {
        guard var table = block.data.table, table.columnCount > 1 else { return }
        var removed = Set<UUID>()
        for r in table.rows.indices where table.rows[r].indices.contains(index) {
            removed.insert(table.rows[r][index].id)
            table.rows[r].remove(at: index)
        }
        block.data.table = table
        space.pruneEffects { ref in ref.itemID.map(removed.contains) ?? false }
    }
}

private struct TableCellView: View {
    @Binding var text: String
    var isHeader: Bool
    var effective: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.doc(13.5, isHeader ? .semibold : .regular))
                .lineLimit(1...6)
                .focused($focused)
            if let effective {
                HStack(spacing: 3) {
                    Image(systemName: "link").font(.system(size: 8, weight: .bold))
                    Text(effective).font(.app(11.5, .semibold)).monospacedDigit()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.opacity(0.13)))
                .help(L("Value after linked actions", "링크된 액션이 반영된 값"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 34, alignment: .topLeading)
        .background(focused ? Theme.accent.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
