import SwiftUI

/// Landing page of a Space: who it is, its nodes, and how they connect.
struct SpaceHomeView: View {
    let space: SpaceModel
    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                stats
                nodesSection
                if space.nodes.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: L("Connections", "연결"))
                        ConnectionMap(space: space)
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .onAppear { withAnimation(Motion.gentle) { appeared = true } }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            SpaceBadge(symbol: space.info.symbol, color: space.color, size: 68)
                .shadow(color: space.color.opacity(0.35), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(space.info.name).font(.app(30, .bold)).lineLimit(2)
                if !space.info.subtitle.isEmpty {
                    Text(space.info.subtitle).font(.app(15, .medium)).foregroundStyle(.secondary)
                }
                if !space.info.about.isEmpty {
                    Text(space.info.about)
                        .font(.app(13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    withAnimation(Motion.spring) { _ = space.addNode() }
                } label: {
                    Label(L("New Node", "새 노드"), systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { FileImporter.pick(into: space, store: store, ui: ui) } label: {
                    Label(L("Add File", "파일 추가"), systemImage: "paperclip")
                }
                .buttonStyle(SoftButtonStyle())
                Button { ui.present(.spaceSettings) } label: {
                    Label(L("Space Settings", "Space 설정"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatTile(symbol: "square.stack.3d.up", title: L("Nodes", "노드"), value: space.nodes.count)
            StatTile(symbol: "rectangle.3.group", title: L("Inserted objects", "삽입물"), value: space.embedCount)
            StatTile(symbol: "link", title: L("Links", "링크"), value: space.connectionCount)
        }
    }

    private var nodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: space.fileCount > 0 ? L("Nodes & files", "노드와 파일") : L("Nodes", "노드"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(space.nodes.sorted { $0.updatedAt > $1.updatedAt }) { node in
                    NodeCard(node: node, space: space)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                Button {
                    withAnimation(Motion.spring) { _ = space.addNode() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                        Text(L("New Node", "새 노드")).font(.app(12, .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 132)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLift(1.015)
            }
        }
    }
}

private struct StatTile: View {
    var symbol: String
    var title: String
    var value: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.app(20, .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(title).font(.app(11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .card(radius: 16)
        .animation(Motion.spring, value: value)
    }
}

private struct NodeCard: View {
    let node: NodeModel
    let space: SpaceModel
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: node.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                Text(node.displayTitle).font(.app(14, .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if space.openTabs.contains(node.id) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6).help(L("Open in a tab", "탭에 열려 있음"))
                }
            }
            Text(node.preview.isEmpty ? L("Empty node", "빈 노드") : (node.isFile ? L("File", "파일") + " · " + node.preview : node.preview))
                .font(.app(12))
                .foregroundStyle(node.preview.isEmpty ? .tertiary : .secondary)
                .lineSpacing(2)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
            HStack(spacing: 6) {
                Text(formatDate(node.updatedAt, date: .abbreviated, time: .omitted))
                    .font(.app(11)).foregroundStyle(.tertiary)
                Spacer()
                ForEach(Array(Set(node.embedKinds.map(\.rawValue))).sorted(), id: \.self) { kind in
                    Image(systemName: kind == "table" ? "tablecells" : kind == "chart" ? "chart.bar" : "person.crop.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .card(radius: 16, fill: hovering ? Theme.cardFill(scheme).opacity(1.35) : nil)
        .shadow(color: .black.opacity(hovering ? (scheme == .dark ? 0.35 : 0.12) : 0), radius: 14, y: 6)
        .scaleEffect(hovering ? 1.015 : 1)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.spring) { space.open(node.id) } }
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            Button(L("Open", "열기")) { withAnimation(Motion.spring) { space.open(node.id) } }
            Divider()
            Button(L("Delete Node…", "노드 삭제…"), role: .destructive) { confirmDelete(node: node, in: space) }
        }
    }
}

/// Nodes on a ring, with a line for every link between them (reference links and action → value links).
private struct ConnectionMap: View {
    let space: SpaceModel
    @Environment(\.colorScheme) private var scheme
    @State private var hover: UUID?

    private struct Edge: Hashable {
        let a: UUID
        let b: UUID
    }

    private var edges: [Edge: Int] {
        var result: [Edge: Int] = [:]
        func add(_ x: UUID, _ y: UUID) {
            guard x != y else { return }
            let edge = x.uuidString < y.uuidString ? Edge(a: x, b: y) : Edge(a: y, b: x)
            result[edge, default: 0] += 1
        }
        for link in space.links { add(link.from.nodeID, link.to.nodeID) }
        for (ref, contributions) in space.contributions() {
            for contribution in contributions { add(contribution.source.nodeID, ref.nodeID) }
        }
        return result
    }

    var body: some View {
        let nodes = Array(space.nodes.prefix(12))
        let edges = edges
        GeometryReader { geo in
            let positions = layout(nodes, in: geo.size)
            ZStack {
                ForEach(Array(edges.keys), id: \.self) { edge in
                    if let p = positions[edge.a], let q = positions[edge.b] {
                        let active = hover == nil || hover == edge.a || hover == edge.b
                        Path { path in
                            path.move(to: p)
                            let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
                            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            path.addQuadCurve(to: q, control: CGPoint(x: mid.x + (centre.x - mid.x) * 0.45, y: mid.y + (centre.y - mid.y) * 0.45))
                        }
                        .stroke(Theme.accent.opacity(active ? 0.65 : 0.15),
                                style: StrokeStyle(lineWidth: min(4, 1.2 + CGFloat(edges[edge] ?? 1) * 0.6), lineCap: .round))
                    }
                }
                ForEach(nodes) { node in
                    if let position = positions[node.id] {
                        HStack(spacing: 6) {
                            Image(systemName: node.symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text(node.displayTitle).font(.app(11.5, .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .frame(maxWidth: 170)
                        .fixedSize()
                        .background(Capsule().fill(scheme == .dark ? Color(white: 0.17) : .white))
                        .overlay(Capsule().strokeBorder(hover == node.id ? Theme.accent.opacity(0.8) : Theme.cardStroke(scheme), lineWidth: 1))
                        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                        .scaleEffect(hover == node.id ? 1.06 : 1)
                        .position(position)
                        .onHover { inside in withAnimation(Motion.snappy) { hover = inside ? node.id : nil } }
                        .onTapGesture { withAnimation(Motion.spring) { space.open(node.id) } }
                    }
                }
                if edges.isEmpty {
                    Text(L("No links yet — connect nodes, objects or action results to see them here.",
                           "아직 링크가 없어요 — 노드, 삽입물, 액션 결과를 연결하면 여기에 보여요."))
                        .font(.app(11.5))
                        .foregroundStyle(.tertiary)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 230)
        .card(radius: 16)
    }

    private func layout(_ nodes: [NodeModel], in size: CGSize) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        let count = max(1, nodes.count)
        let rx = max(60, size.width / 2 - 110), ry = max(40, size.height / 2 - 34)
        for (index, node) in nodes.enumerated() {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count) + (count == 2 ? Double.pi / 2 : 0)
            positions[node.id] = CGPoint(x: size.width / 2 + rx * CGFloat(cos(angle)), y: size.height / 2 + ry * CGFloat(sin(angle)))
        }
        return positions
    }
}
