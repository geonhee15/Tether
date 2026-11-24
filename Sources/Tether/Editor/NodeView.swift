import SwiftUI

/// One node: a continuous page of text with inserted objects flowing inline.
struct NodeView: View {
    let node: NodeModel
    let space: SpaceModel

    @Environment(EditorController.self) private var editor
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var node = node
        let settings = AppSettings.shared
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(title: $node.title)
                        ForEach(node.blocks) { block in
                            blockView(block)
                                .id(block.id)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                                        removal: .opacity.combined(with: .scale(scale: 0.98))))
                        }
                        // Clicking the empty page below the content continues writing at the end.
                        Color.clear
                            .frame(height: 260)
                            .contentShape(Rectangle())
                            .onTapGesture { editor.focusEnd(of: node) }
                    }
                    .frame(maxWidth: settings.contentWidth.points, alignment: .leading)
                    .padding(.horizontal, 48)
                    .padding(.top, 84)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: ui.scrollTarget) { _, target in
                    if let target { withAnimation(Motion.smooth) { proxy.scrollTo(target, anchor: .center) } }
                }
                .onChange(of: editor.lastInserted) { _, inserted in
                    guard let inserted, node.block(inserted) != nil else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(Motion.smooth) { proxy.scrollTo(inserted, anchor: .center) }
                    }
                }
            }
            FormatToolbar(node: node)
                .padding(.top, 14)
                .padding(.horizontal, 16)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.pageFill(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.08), radius: 18, y: 6)
        .padding(.trailing, 12)
        .padding(.bottom, 4)
        .onAppear { editor.node = node }
    }

    private func header(title: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Menu {
                    ForEach(SymbolSets.node, id: \.self) { symbol in
                        Button { node.symbol = symbol } label: { Image(systemName: symbol) }
                    }
                } label: {
                    Image(systemName: node.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.12)))
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("Change icon", "아이콘 변경"))
                TextField(L("Untitled", "제목 없음"), text: title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.doc(30, .bold))
                    .lineLimit(1...3)
                    .onSubmit { editor.focus(node.blocks.first { $0.data.kind == .text }?.id ?? UUID(), atEnd: false) }
            }
            HStack(spacing: 8) {
                Text(L("Edited ", "수정 ") + formatDate(node.updatedAt, date: .abbreviated, time: .shortened))
                    .font(.app(11.5))
                    .foregroundStyle(.tertiary)
                AddLinkButton(space: space, anchor: Anchor(nodeID: node.id, blockID: nil), labeled: true)
            }
            LinkChips(space: space, anchor: Anchor(nodeID: node.id, blockID: nil))
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func blockView(_ block: BlockModel) -> some View {
        switch block.data.kind {
        case .text:
            TextBlockView(block: block, placeholder: placeholder(for: block))
        case .table:
            TableBlockView(block: block, node: node, space: space)
        case .chart:
            ChartBlockView(block: block, node: node, space: space)
        case .analytics:
            AnalyticsBlockView(block: block, node: node, space: space)
        }
    }

    /// Only a completely empty page shows a prompt.
    private func placeholder(for block: BlockModel) -> String? {
        guard node.blocks.count == 1, node.blocks.first?.id == block.id else { return nil }
        return L("Start writing — or use Insert to add a table, chart or analytics.",
                 "글을 써 보세요 — ‘삽입’으로 표, 그래프, 애널리틱스를 넣을 수 있어요.")
    }
}

// MARK: Toolbar

/// Floating glass bar: text styles on the left, Insert on the right.
struct FormatToolbar: View {
    let node: NodeModel
    @Environment(EditorController.self) private var editor
    @Environment(\.colorScheme) private var scheme
    @State private var showColor = false
    @State private var showHighlight = false

    var body: some View {
        let format = editor.format
        let style = format.style
        HStack(spacing: 4) {
            Group {
                presetMenu(format)
                divider
                fontMenu(style)
                sizeMenu(style)
                divider
                IconButton(symbol: "bold", active: style.bold, help: L("Bold  ⌘B", "굵게  ⌘B")) { editor.perform { $0.toggle(\.bold) } }
                IconButton(symbol: "italic", active: style.italic, help: L("Italic  ⌘I", "기울임  ⌘I")) { editor.perform { $0.toggle(\.italic) } }
                IconButton(symbol: "underline", active: style.underline, help: L("Underline  ⌘U", "밑줄  ⌘U")) { editor.perform { $0.toggle(\.underline) } }
                IconButton(symbol: "strikethrough", active: style.strike, help: L("Strikethrough  ⇧⌘X", "취소선  ⇧⌘X")) { editor.perform { $0.toggle(\.strike) } }
                divider
                colorButton(style)
                highlightButton(style)
                divider
                alignmentButtons(format.alignment)
                IconButton(symbol: "eraser", help: L("Clear formatting  ⇧⌘\\", "서식 지우기  ⇧⌘\\")) { editor.perform { $0.clearFormatting() } }
            }
            .disabled(!format.hasEditor)
            Spacer(minLength: 10)
            InsertMenu(node: node)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .frame(maxWidth: 860)
        .glass(radius: 22, frost: 0.6)
        .zIndex(5)
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardStroke(scheme).opacity(1.6)).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    private func menuLabel(_ text: String, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.app(12, .medium)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.hoverFill(scheme)))
        .contentShape(Rectangle())
    }

    private func presetMenu(_ format: FormatState) -> some View {
        Menu {
            ForEach(TextPreset.allCases) { preset in
                Button(preset.label) { editor.perform { $0.applyPreset(preset) } }
            }
        } label: {
            menuLabel(format.preset?.label ?? L("Custom", "사용자 지정"), width: 96)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Paragraph style", "문단 스타일"))
    }

    private func fontMenu(_ style: RunStyle) -> some View {
        let current = style.family.flatMap(FontChoice.init(rawValue:))
        return Menu {
            Button(L("Default (\(AppSettings.shared.editorFont.title))", "기본 (\(AppSettings.shared.editorFont.title))")) {
                editor.perform { $0.mutateStyle { $0.family = nil } }
            }
            Divider()
            ForEach(FontChoice.allCases) { choice in
                Button(choice.title) { editor.perform { $0.mutateStyle { $0.family = choice.rawValue } } }
            }
        } label: {
            menuLabel(current?.title ?? L("Default", "기본"), width: 116)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Font", "글꼴"))
    }

    private func sizeMenu(_ style: RunStyle) -> some View {
        let sizes: [Double] = [11, 12, 13, 14, 15, 16, 18, 20, 24, 28, 32, 40]
        let current = style.size ?? AppSettings.shared.editorFontSize
        return Menu {
            Button(L("Default (\(formatNumber(AppSettings.shared.editorFontSize)))", "기본 (\(formatNumber(AppSettings.shared.editorFontSize)))")) {
                editor.perform { $0.mutateStyle { $0.size = nil } }
            }
            Divider()
            ForEach(sizes, id: \.self) { size in
                Button(formatNumber(size)) { editor.perform { $0.mutateStyle { $0.size = size } } }
            }
        } label: {
            menuLabel(formatNumber(current), width: 54)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Size", "크기"))
    }

    private func colorButton(_ style: RunStyle) -> some View {
        Button { showColor = true } label: {
            VStack(spacing: 2) {
                Image(systemName: "textformat").font(.system(size: 12, weight: .medium))
                Capsule().fill(style.color.map { Color(hex: $0) } ?? Color.primary).frame(width: 14, height: 3)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Text colour", "글자 색"))
        .popover(isPresented: $showColor, arrowEdge: .bottom) {
            SwatchGrid(title: L("Text colour", "글자 색"), colors: TextPalette.text, selected: style.color,
                       clearLabel: L("Default", "기본")) { hex in
                editor.perform { $0.mutateStyle { $0.color = hex } }
                showColor = false
            }
        }
    }

    private func highlightButton(_ style: RunStyle) -> some View {
        Button { showHighlight = true } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(style.highlight.map { Color(hex: $0) } ?? .clear).padding(3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Highlight", "형광펜"))
        .popover(isPresented: $showHighlight, arrowEdge: .bottom) {
            SwatchGrid(title: L("Highlight", "형광펜"), colors: TextPalette.highlight, selected: style.highlight,
                       clearLabel: L("None", "없음")) { hex in
                editor.perform { $0.mutateStyle { $0.highlight = hex } }
                showHighlight = false
            }
        }
    }

    private func alignmentButtons(_ alignment: Int) -> some View {
        HStack(spacing: 0) {
            IconButton(symbol: "text.alignleft", size: 12, active: alignment == 0, help: L("Align left", "왼쪽 정렬")) { editor.perform { $0.applyAlignment(.natural) } }
            IconButton(symbol: "text.aligncenter", size: 12, active: alignment == 1, help: L("Centre", "가운데 정렬")) { editor.perform { $0.applyAlignment(.center) } }
            IconButton(symbol: "text.alignright", size: 12, active: alignment == 2, help: L("Align right", "오른쪽 정렬")) { editor.perform { $0.applyAlignment(.right) } }
        }
    }
}

private struct SwatchGrid: View {
    var title: String
    var colors: [String]
    var selected: String?
    var clearLabel: String
    var onPick: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.app(12, .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 4), spacing: 8) {
                ForEach(colors, id: \.self) { hex in
                    Button { onPick(hex) } label: {
                        Circle().fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(selected == hex ? 0.8 : 0.12), lineWidth: selected == hex ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .hoverLift(1.12)
                }
            }
            Button { onPick(nil) } label: {
                Label(clearLabel, systemImage: "arrow.uturn.backward").font(.app(11.5, .medium)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle())
        }
        .padding(14)
        .frame(width: 162)
    }
}

// MARK: Insert menu

/// Drop-down that opens when the pointer rests on "Insert". Graph fans out into its three kinds.
struct InsertMenu: View {
    let node: NodeModel
    @Environment(EditorController.self) private var editor
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var open = false
    @State private var showCharts = false
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        let visible = open || ui.demoInsertMenu
        Button {
            withAnimation(Motion.snappy) { open.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 13, weight: .semibold))
                Text(L("Insert", "삽입")).font(.app(12.5, .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(visible ? 180 : 0))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.8)], startPoint: .top, endPoint: .bottom)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover($0) }
        .overlay(alignment: .topTrailing) {
            if visible {
                panel
                    .fixedSize()
                    .offset(y: 38)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: visible)
        .animation(Motion.snappy, value: showCharts)
    }

    private var panel: some View {
        let charts = showCharts || ui.demoInsertMenu
        return HStack(alignment: .top, spacing: 8) {
            if charts {
                VStack(spacing: 2) {
                    InsertRow(symbol: "chart.pie.fill", title: L("Pie chart", "파이 차트"), subtitle: L("Parts of a whole", "전체에서의 비율")) { insertChart(.pie) }
                    InsertRow(symbol: "chart.bar.fill", title: L("Bar graph", "바 그래프"), subtitle: L("Compare values", "값 비교")) { insertChart(.bar) }
                    InsertRow(symbol: "chart.xyaxis.line", title: L("Line graph", "라인 그래프"), subtitle: L("Change over time", "시간에 따른 변화")) { insertChart(.line) }
                }
                .padding(6)
                .frame(width: 214)
                .glass(radius: 16, frost: 0.8)
                .padding(.top, 50)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            VStack(spacing: 2) {
                InsertRow(symbol: "tablecells", title: L("Table", "테이블"), subtitle: L("Rows and columns", "행과 열로 정리")) {
                    insert(Block(kind: .table, table: .blank()))
                }
                .onHover { if $0 { showCharts = false } }
                InsertRow(symbol: "chart.bar.xaxis", title: L("Graph", "그래프"), subtitle: L("Pie, bar or line", "파이 · 바 · 라인"), chevron: true, highlighted: charts) {
                    withAnimation(Motion.snappy) { showCharts.toggle() }
                }
                .onHover { if $0 { showCharts = true } }
                InsertRow(symbol: "person.crop.circle.badge.checkmark", title: L("Analytics", "애널리틱스"),
                          subtitle: L("Understand a relationship", "관계를 분석하고 계획")) {
                    insert(Block(kind: .analytics, analytics: AnalyticsData()))
                }
                .onHover { if $0 { showCharts = false } }
            }
            .padding(6)
            .frame(width: 232)
            .glass(radius: 16, frost: 0.8)
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onHover { hover($0) }
    }

    /// Opens at once; closes after a short grace period so the pointer can cross the gap.
    private func hover(_ inside: Bool) {
        closeTask?.cancel()
        if inside {
            if !open { withAnimation(Motion.snappy) { open = true } }
        } else {
            closeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.snappy) {
                    open = false
                    showCharts = false
                }
            }
        }
    }

    private func insertChart(_ style: ChartStyle) {
        let labels = [L("First", "첫째"), L("Second", "둘째"), L("Third", "셋째")]
        let values: [Double] = [40, 25, 35]
        let points = zip(labels, values).enumerated().map { ChartPoint(label: $1.0, value: $1.1, colorSlot: $0) }
        insert(Block(kind: .chart, chart: ChartData(style: style, points: points)))
    }

    private func insert(_ block: Block) {
        closeTask?.cancel()
        open = false
        showCharts = false
        ui.demoInsertMenu = false
        editor.insert(block, into: node)
    }
}

private struct InsertRow: View {
    var symbol: String
    var title: String
    var subtitle: String
    var chevron = false
    var highlighted = false
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(12.5, .semibold))
                    Text(subtitle).font(.app(11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if chevron {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering || highlighted ? Theme.hoverFill(scheme) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}
