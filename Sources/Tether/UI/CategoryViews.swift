import SwiftUI

/// Menu rows that file a node under one of the Space's categories. Used by the node header,
/// the tab strip and the cards on the Space home.
struct CategoryMenuItems: View {
    let node: NodeModel
    let space: SpaceModel

    var body: some View {
        let current = space.category(of: node)?.id
        Button {
            withAnimation(Motion.spring) { node.categoryID = nil }
        } label: {
            row(L("No Category", "카테고리 없음"), selected: current == nil)
        }
        if !space.categories.isEmpty { Divider() }
        ForEach(space.categories) { category in
            Button {
                withAnimation(Motion.spring) { node.categoryID = category.id }
            } label: {
                row(category.name.isEmpty ? L("Untitled category", "이름 없는 카테고리") : category.name, selected: current == category.id)
            }
        }
        Divider()
        Button(L("New Category", "새 카테고리")) {
            withAnimation(Motion.spring) {
                node.categoryID = space.addCategory(named: L("New category", "새 카테고리")).id
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// The category a node is filed under, as a small pill that opens the category menu.
struct CategoryChip: View {
    let node: NodeModel
    let space: SpaceModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let category = space.category(of: node)
        Menu {
            CategoryMenuItems(node: node, space: space)
        } label: {
            HStack(spacing: 5) {
                if let category {
                    Circle().fill(Theme.spaceColor(category.colorIndex)).frame(width: 7, height: 7)
                    Text(category.name.isEmpty ? L("Untitled category", "이름 없는 카테고리") : category.name)
                } else {
                    Image(systemName: "folder").font(.system(size: 10, weight: .medium))
                    Text(L("Category", "카테고리"))
                }
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.tertiary)
            }
            .font(.app(11.5, .medium))
            .lineLimit(1)
            .foregroundStyle(category == nil ? .secondary : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chipFill(scheme)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("File this node under a category", "이 노드를 카테고리에 넣기"))
    }
}

/// One category on the Space home: a header that renames, recolours, folds and reorders it,
/// and the cards of the nodes filed under it. `category == nil` is the unfiled group.
struct CategorySection<Card: View>: View {
    let category: NodeCategory?
    let space: SpaceModel
    let nodes: [NodeModel]
    @ViewBuilder var card: (NodeModel) -> Card

    @Environment(\.colorScheme) private var scheme
    @State private var pickingColor = false

    private var collapsed: Bool { category.map { space.collapsedCategories.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !collapsed {
                if nodes.isEmpty {
                    emptyRow
                        .transition(.opacity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(nodes) { node in
                            card(node).transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let category {
                Button {
                    withAnimation(Motion.spring) { space.setCollapsed(!collapsed, category: category.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? L("Show nodes", "노드 펼치기") : L("Hide nodes", "노드 접기"))

                Button { pickingColor = true } label: {
                    Circle().fill(Theme.spaceColor(category.colorIndex))
                        .frame(width: 11, height: 11)
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Change colour", "색상 변경"))
                .popover(isPresented: $pickingColor, arrowEdge: .bottom) { swatches(category) }

                TextField(L("Category name", "카테고리 이름"), text: Binding(
                    get: { space.category(category.id)?.name ?? "" },
                    set: { name in space.updateCategory(category.id) { $0.name = name } }))
                    .textFieldStyle(.plain)
                    .font(.app(14, .semibold))
                    .fixedSize()
                    .frame(maxWidth: 360, alignment: .leading)
                    .fixedSize()
            } else {
                Image(systemName: "tray").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18, height: 22)
                Text(L("No category", "미분류")).font(.app(14, .semibold)).foregroundStyle(.secondary)
            }
            Text("\(nodes.count)")
                .font(.app(11, .medium)).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.chipFill(scheme)))
            Spacer(minLength: 8)
            IconButton(symbol: "plus", size: 12, help: category == nil ? L("New node", "새 노드") : L("New node in this category", "이 카테고리에 새 노드")) {
                withAnimation(Motion.spring) {
                    if let category { space.setCollapsed(false, category: category.id) }
                    _ = space.addNode(in: category?.id)
                }
            }
            if let category {
                Menu {
                    Button(L("Move Up", "위로 이동")) { withAnimation(Motion.spring) { space.moveCategory(category.id, by: -1) } }
                        .disabled(space.categories.first?.id == category.id)
                    Button(L("Move Down", "아래로 이동")) { withAnimation(Motion.spring) { space.moveCategory(category.id, by: 1) } }
                        .disabled(space.categories.last?.id == category.id)
                    Divider()
                    Button(L("Delete Category", "카테고리 삭제"), role: .destructive) {
                        withAnimation(Motion.spring) { space.deleteCategory(category.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Reorder or delete — deleting keeps the nodes", "순서 변경 · 삭제 — 삭제해도 노드는 남아요"))
            }
        }
    }

    private var emptyRow: some View {
        Button {
            withAnimation(Motion.spring) { _ = space.addNode(in: category?.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                Text(L("Nothing here yet — add a node, or move one in from its menu.",
                       "아직 비어 있어요 — 노드를 추가하거나, 노드 메뉴에서 이 카테고리로 옮겨 보세요."))
                    .font(.app(12))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatches(_ category: NodeCategory) -> some View {
        HStack(spacing: 9) {
            ForEach(Theme.spaceColors.indices, id: \.self) { index in
                let selected = category.colorIndex == index
                Button {
                    withAnimation(Motion.snappy) { space.updateCategory(category.id) { $0.colorIndex = index } }
                    pickingColor = false
                } label: {
                    Circle().fill(Theme.spaceColors[index])
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.8 : 0), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .hoverLift(1.12)
            }
        }
        .padding(14)
    }
}
