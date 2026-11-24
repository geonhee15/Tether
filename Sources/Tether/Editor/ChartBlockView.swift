import Charts
import SwiftUI

struct ChartBlockView: View {
    let block: BlockModel
    let node: NodeModel
    let space: SpaceModel

    @Environment(EditorController.self) private var editor
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var hoverID: UUID?
    @State private var pieAngle: Double?

    /// A point as drawn: its own value plus whatever linked actions add.
    private struct Item: Identifiable {
        let id: UUID
        let key: String
        let label: String
        let base: Double
        let value: Double
        let color: Color
    }

    private var chart: ChartData { block.data.chart ?? ChartData(style: .bar, points: []) }

    private func items(_ contributions: [ValueRef: [Contribution]]) -> [Item] {
        chart.points.enumerated().map { index, point in
            let linked = contributions[ref(point.id)]?.filter(\.done).reduce(0) { $0 + $1.delta } ?? 0
            return Item(id: point.id, key: String(index), label: point.label.isEmpty ? "—" : point.label,
                        base: point.value, value: point.value + linked, color: Theme.chartColor(point.colorSlot))
        }
    }

    private func ref(_ pointID: UUID) -> ValueRef {
        ValueRef(nodeID: node.id, blockID: block.id, itemID: pointID)
    }

    var body: some View {
        let contributions = space.contributions()
        let items = items(contributions)
        EmbedFrame(block: block, node: node, space: space, symbol: chart.style.symbol,
                   titlePlaceholder: L("Chart title", "그래프 제목"), title: titleBinding) {
            SlidingPicker(options: ChartStyle.allCases.map { ($0, "", Optional($0.symbol)) }, selection: styleBinding)
                .padding(.trailing, 4)
            IconButton(symbol: "slider.horizontal.3", size: 12, active: editing, help: L("Edit values", "값 편집")) {
                withAnimation(Motion.spring) { editing.toggle() }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if items.isEmpty {
                        emptyState
                    } else {
                        switch chart.style {
                        case .bar: barChart(items)
                        case .line: lineChart(items)
                        case .pie: pieChart(items)
                        }
                    }
                }
                .frame(height: 220)
                .animation(Motion.spring, value: items.map(\.value))
                .animation(Motion.spring, value: chart.style)

                ContributionNotes(space: space, entries: notes(contributions))

                if editing {
                    dataEditor(items)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onAppear {
            if editor.lastInserted == block.id { editing = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: chart.style.symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(L("Add values to draw this chart.", "값을 추가하면 그래프가 그려져요."))
                .font(.app(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Charts

    private func dimmed(_ item: Item) -> Double {
        hoverID == nil || hoverID == item.id ? 1 : 0.4
    }

    private func barChart(_ items: [Item]) -> some View {
        Chart(items) { item in
            BarMark(x: .value("Label", item.key), y: .value("Value", item.value), width: .ratio(0.52))
                .foregroundStyle(item.color)
                .opacity(dimmed(item))
                .cornerRadius(5)
                .annotation(position: item.value >= 0 ? .top : .bottom, spacing: 4) {
                    Text(formatNumber(item.value))
                        .font(.app(11, .medium)).monospacedDigit()
                        .foregroundStyle(hoverID == item.id ? .primary : .secondary)
                }
        }
        .chartXAxis { categoryAxis(items) }
        .chartYAxis { valueAxis }
        .chartOverlay { proxy in hoverLayer(proxy, items) }
    }

    private func lineChart(_ items: [Item]) -> some View {
        let series = Theme.chartColor(0)
        return Chart(items) { item in
            AreaMark(x: .value("Label", item.key), y: .value("Value", item.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [series.opacity(0.26), series.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Label", item.key), y: .value("Value", item.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(series)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("Label", item.key), y: .value("Value", item.value))
                .foregroundStyle(series)
                .symbolSize(hoverID == item.id ? 110 : 46)
            if hoverID == item.id {
                RuleMark(x: .value("Label", item.key))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(item)
                    }
            }
        }
        .chartXAxis { categoryAxis(items) }
        .chartYAxis { valueAxis }
        .chartOverlay { proxy in hoverLayer(proxy, items) }
        .padding(.top, 14)
    }

    private func pieChart(_ items: [Item]) -> some View {
        let total = items.reduce(0) { $0 + max(0, $1.value) }
        let focus = items.first { $0.id == hoverID }
        return HStack(spacing: 22) {
            Chart(items) { item in
                SectorMark(angle: .value("Value", max(0, item.value)), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(item.color)
                    .opacity(dimmed(item))
            }
            .chartAngleSelection(value: $pieAngle)
            .chartLegend(.hidden)
            .chartBackground { _ in
                VStack(spacing: 1) {
                    Text(focus.map { percent($0.value, of: total) } ?? formatNumber(total))
                        .font(.app(20, .bold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(focus?.label ?? L("Total", "합계"))
                        .font(.app(11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 96)
            }
            .frame(width: 200)
            .onChange(of: pieAngle) { _, angle in
                guard let angle else { hoverID = nil; return }
                var running = 0.0
                for item in items {
                    running += max(0, item.value)
                    if angle <= running { hoverID = item.id; return }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(item.color).frame(width: 10, height: 10)
                        Text(item.label).font(.doc(13)).lineLimit(1)
                        Spacer(minLength: 10)
                        Text(formatNumber(item.value)).font(.app(12, .medium)).monospacedDigit()
                        Text(percent(item.value, of: total))
                            .font(.app(11)).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .opacity(dimmed(item))
                    .contentShape(Rectangle())
                    .onHover { inside in hoverID = inside ? item.id : (hoverID == item.id ? nil : hoverID) }
                }
            }
            .frame(maxWidth: 300)
            Spacer(minLength: 0)
        }
        .animation(Motion.snappy, value: hoverID)
    }

    private func percent(_ value: Double, of total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", max(0, value) / total * 100)
    }

    private func tooltip(_ item: Item) -> some View {
        HStack(spacing: 6) {
            Text(item.label).foregroundStyle(.secondary)
            Text(formatNumber(item.value)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.app(11.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1))
    }

    private func categoryAxis(_ items: [Item]) -> some AxisContent {
        AxisMarks(values: items.map(\.key)) { value in
            AxisValueLabel {
                if let key = value.as(String.self), let item = items.first(where: { $0.key == key }) {
                    Text(item.label).font(.doc(11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var valueAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
            AxisValueLabel().font(.system(size: 10.5)).foregroundStyle(Color.secondary)
        }
    }

    private func hoverLayer(_ proxy: ChartProxy, _ items: [Item]) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geo[frame].origin.x
                        if let key: String = proxy.value(atX: x) {
                            let id = items.first { $0.key == key }?.id
                            if id != hoverID { withAnimation(Motion.snappy) { hoverID = id } }
                        }
                    case .ended:
                        withAnimation(Motion.snappy) { hoverID = nil }
                    }
                }
        }
    }

    private func notes(_ contributions: [ValueRef: [Contribution]]) -> [(label: String, contribution: Contribution)] {
        chart.points.flatMap { point in
            (contributions[ref(point.id)] ?? []).map { (point.label.isEmpty ? "—" : point.label, $0) }
        }
    }

    // MARK: Data editor

    private func dataEditor(_ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Menu {
                        ForEach(0..<8, id: \.self) { slot in
                            Button(L("Colour \(slot + 1)", "색상 \(slot + 1)")) { update(item.id) { $0.colorSlot = slot } }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(item.color).frame(width: 14, height: 14)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    TextField(L("Label", "이름"), text: labelBinding(item.id))
                        .textFieldStyle(.plain)
                        .font(.doc(13))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fieldFill(scheme)))
                    TextField("0", value: valueBinding(item.id), format: .number)
                        .textFieldStyle(.plain)
                        .font(.app(13)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 9)
                        .frame(width: 92, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fieldFill(scheme)))
                    if item.value != item.base {
                        HStack(spacing: 3) {
                            Image(systemName: "link").font(.system(size: 8, weight: .bold))
                            Text(formatDelta(item.value - item.base) + " = " + formatNumber(item.value))
                                .font(.app(11.5, .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                    }
                    IconButton(symbol: "minus.circle", size: 12, side: 24, tint: .secondary, help: L("Remove", "삭제")) {
                        withAnimation(Motion.spring) { remove(item.id) }
                    }
                }
            }
            Button {
                withAnimation(Motion.spring) { addPoint() }
            } label: {
                Label(L("Add value", "값 추가"), systemImage: "plus").font(.app(11.5, .medium))
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(chart.points.count >= 8)
            .padding(.top, 2)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.embedFill(scheme)))
    }

    private var titleBinding: Binding<String> {
        Binding(get: { block.data.chart?.title ?? "" }, set: { block.data.chart?.title = $0 })
    }

    private var styleBinding: Binding<ChartStyle> {
        Binding(get: { block.data.chart?.style ?? .bar }, set: { block.data.chart?.style = $0 })
    }

    private func update(_ id: UUID, _ change: (inout ChartPoint) -> Void) {
        guard let index = block.data.chart?.points.firstIndex(where: { $0.id == id }) else { return }
        if var point = block.data.chart?.points[index] {
            change(&point)
            block.data.chart?.points[index] = point
        }
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { block.data.chart?.points.first { $0.id == id }?.label ?? "" },
                set: { value in update(id) { $0.label = value } })
    }

    private func valueBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { block.data.chart?.points.first { $0.id == id }?.value ?? 0 },
                set: { value in update(id) { $0.value = value } })
    }

    private func addPoint() {
        guard var chart = block.data.chart, chart.points.count < 8 else { return }
        chart.points.append(ChartPoint(label: "", value: 10, colorSlot: chart.nextColorSlot))
        block.data.chart = chart
    }

    private func remove(_ id: UUID) {
        block.data.chart?.points.removeAll { $0.id == id }
        space.pruneEffects { $0.itemID == id }
    }
}
