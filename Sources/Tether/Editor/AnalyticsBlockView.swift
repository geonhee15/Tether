import SwiftUI

/// A profile of one relationship: who they are, what you have observed, a score out of 100 and
/// the actions that would raise it. Completing an action can also push values elsewhere in the Space.
struct AnalyticsBlockView: View {
    let block: BlockModel
    let node: NodeModel
    let space: SpaceModel

    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme

    private var data: AnalyticsData { block.data.analytics ?? AnalyticsData() }

    private func edit(_ change: (inout AnalyticsData) -> Void) {
        var copy = data
        change(&copy)
        block.data.analytics = copy
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AnalyticsData, T>) -> Binding<T> {
        Binding(get: { data[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        let score = space.score(of: block, in: node)
        EmbedFrame(block: block, node: node, space: space, symbol: "person.crop.circle.badge.checkmark",
                   titlePlaceholder: L("Name", "이름"), title: binding(\.name)) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 18) {
                summary(score)
                HStack(alignment: .top, spacing: 10) {
                    TagSection(title: L("Traits", "특징"), symbol: "sparkle", tags: binding(\.traits),
                               placeholder: L("Add a trait", "특징 추가"))
                    TagSection(title: L("What works", "좋아하는 것"), symbol: "hand.thumbsup", tint: Theme.positive, tags: binding(\.likes),
                               placeholder: L("Add what lands well", "효과적인 것 추가"))
                    TagSection(title: L("Watch out", "주의할 점"), symbol: "exclamationmark.triangle", tint: Theme.negative, tags: binding(\.cautions),
                               placeholder: L("Add a caution", "주의점 추가"))
                }
                .fixedSize(horizontal: false, vertical: true)
                attitude
                actions(score)
                observations
            }
        }
    }

    // MARK: Summary

    private func summary(_ score: ScoreBreakdown) -> some View {
        HStack(alignment: .center, spacing: 22) {
            ScoreRing(value: score.value, projected: score.projected)
                .frame(width: 108, height: 108)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "person.2").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField(L("Relationship — mentor, teammate, client…", "관계 — 멘토, 팀원, 고객…"), text: binding(\.relation))
                        .textFieldStyle(.plain)
                        .font(.doc(13.5))
                }
                PathBar(score: score)
                Text(insight(score))
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(L("My baseline", "내 기준 평가")).font(.app(11.5)).foregroundStyle(.secondary)
                    Slider(value: binding(\.baseScore), in: 0...100, step: 1)
                        .controlSize(.small)
                        .frame(maxWidth: 220)
                    Text(formatNumber(data.baseScore)).font(.app(11.5, .semibold)).monospacedDigit().frame(width: 28, alignment: .leading)
                }
            }
        }
    }

    private func insight(_ score: ScoreBreakdown) -> String {
        let now = formatNumber(score.value)
        if score.value >= 100 {
            return L("At 100. Keep doing what works.", "100점이에요. 지금 잘 되는 걸 계속 이어가세요.")
        }
        if data.actions.isEmpty {
            return L("Now \(now). Add actions below to plan the way to 100.", "현재 \(now)점. 아래에 액션을 추가해 100점까지의 길을 계획해 보세요.")
        }
        let planned = score.projected - score.value
        var text = planned > 0
            ? L("Now \(now). Finishing every open action adds \(formatNumber(planned)) → \(formatNumber(score.projected)).",
                "현재 \(now)점. 남은 액션을 모두 마치면 +\(formatNumber(planned)) → \(formatNumber(score.projected))점.")
            : L("Now \(now). Every action is done.", "현재 \(now)점. 모든 액션을 마쳤어요.")
        if score.gap > 0 {
            text += L(" Still \(formatNumber(score.gap)) short of 100 — plan another action.", " 100점까지 \(formatNumber(score.gap))점 부족해요 — 액션을 더 계획해 보세요.")
        } else {
            text += L(" That reaches 100.", " 100점에 도달해요.")
        }
        return text
    }

    private var attitude: some View {
        VStack(alignment: .leading, spacing: 7) {
            SubsectionLabel(text: L("How they see me", "나를 향한 태도"), symbol: "arrow.left.arrow.right")
            TextField(L("What does their behaviour towards you suggest? What changed recently?",
                        "나를 대하는 태도에서 무엇이 보이나요? 최근에 달라진 점은?"), text: binding(\.attitude), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.doc(13.5))
                .lineSpacing(3)
                .lineLimit(2...10)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.embedFill(scheme)))
        }
    }

    // MARK: Actions

    private func actions(_ score: ScoreBreakdown) -> some View {
        let done = data.actions.filter(\.isDone).count
        let ideas = data.likes.filter { like in
            !like.text.isEmpty && !data.actions.contains { $0.title.caseInsensitiveCompare(like.text) == .orderedSame }
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                SubsectionLabel(text: L("Action plan", "액션 플랜"), symbol: "target")
                Spacer()
                if !data.actions.isEmpty {
                    Text(L("\(done) of \(data.actions.count) done", "\(data.actions.count)개 중 \(done)개 완료"))
                        .font(.app(11)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(data.actions) { action in
                ActionRow(action: actionBinding(action.id), space: space, ownBlock: block.id) {
                    withAnimation(Motion.spring) { edit { $0.actions.removeAll { $0.id == action.id } } }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 6) {
                Button {
                    withAnimation(Motion.spring) { edit { $0.actions.append(ActionItem()) } }
                } label: {
                    Label(L("Add action", "액션 추가"), systemImage: "plus").font(.app(11.5, .medium))
                }
                .buttonStyle(SoftButtonStyle())
                if !ideas.isEmpty {
                    Text(L("Ideas from “What works”:", "‘좋아하는 것’에서:")).font(.app(11)).foregroundStyle(.tertiary).padding(.leading, 4)
                    ForEach(ideas.prefix(3)) { idea in
                        Button {
                            withAnimation(Motion.spring) { edit { $0.actions.append(ActionItem(title: idea.text)) } }
                        } label: {
                            Chip(text: idea.text, symbol: "plus", tint: Theme.positive)
                        }
                        .buttonStyle(.plain)
                        .help(L("Turn this into an action", "이걸 액션으로 만들기"))
                    }
                }
            }
        }
    }

    private func actionBinding(_ id: UUID) -> Binding<ActionItem> {
        Binding(get: { data.actions.first { $0.id == id } ?? ActionItem(id: id) },
                set: { value in edit { data in
                    if let index = data.actions.firstIndex(where: { $0.id == id }) { data.actions[index] = value }
                } })
    }

    // MARK: Observations

    private var observations: some View {
        VStack(alignment: .leading, spacing: 7) {
            SubsectionLabel(text: L("Observations", "관찰 기록"), symbol: "eye")
            ForEach(data.observations) { entry in
                LogRow(entry: logBinding(entry.id)) {
                    withAnimation(Motion.spring) { edit { $0.observations.removeAll { $0.id == entry.id } } }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button {
                withAnimation(Motion.spring) { edit { $0.observations.append(LogEntry()) } }
            } label: {
                Label(L("Add observation", "관찰 추가"), systemImage: "plus").font(.app(11.5, .medium))
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    private func logBinding(_ id: UUID) -> Binding<LogEntry> {
        Binding(get: { data.observations.first { $0.id == id } ?? LogEntry(id: id) },
                set: { value in edit { data in
                    if let index = data.observations.firstIndex(where: { $0.id == id }) { data.observations[index] = value }
                } })
    }
}

// MARK: Pieces

private struct SubsectionLabel: View {
    var text: String
    var symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.app(11.5, .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

/// Current score as a ring; the lighter arc is where finishing every open action would land.
struct ScoreRing: View {
    var value: Double
    var projected: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().stroke(Theme.chipFill(scheme), lineWidth: 10)
            Circle()
                .trim(from: 0, to: projected / 100)
                .stroke(Theme.accent.opacity(0.28), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: value / 100)
                .stroke(AngularGradient(colors: [Theme.accent.opacity(0.7), Theme.accent], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, value / 100))),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(formatNumber(value))
                    .font(.app(30, .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: value))
                Text("/ 100").font(.app(10.5, .medium)).foregroundStyle(.secondary)
            }
        }
        .padding(5)
        .animation(Motion.spring, value: value)
        .animation(Motion.spring, value: projected)
        .accessibilityLabel(L("Score \(formatNumber(value)) of 100", "점수 100점 중 \(formatNumber(value))점"))
    }
}

/// Baseline → earned → planned → gap, as one bar towards 100.
private struct PathBar: View {
    var score: ScoreBreakdown
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = min(max(0, score.base), score.value)
        let earned = max(0, score.value - base)
        let planned = max(0, score.projected - score.value)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let unit = geo.size.width / 100
                HStack(spacing: 2) {
                    segment(Theme.accent.opacity(0.55), width: base * unit)
                    segment(Theme.accent, width: earned * unit)
                    segment(Theme.accent.opacity(0.26), width: planned * unit)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Capsule().fill(Theme.chipFill(scheme)))
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                legend(Theme.accent.opacity(0.55), L("Baseline", "기준"), formatNumber(score.base))
                legend(Theme.accent, L("Earned", "획득"), formatDelta(score.earned + score.linked))
                legend(Theme.accent.opacity(0.26), L("Planned", "계획"), formatDelta(score.potential))
                if score.gap > 0 {
                    legend(Theme.chipFill(scheme), L("Gap", "부족"), formatNumber(score.gap))
                }
            }
        }
        .animation(Motion.spring, value: score.value)
        .animation(Motion.spring, value: score.projected)
    }

    private func segment(_ color: Color, width: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func legend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.app(11))
    }
}

/// A titled group of short tags with an inline "add" field.
private struct TagSection: View {
    var title: String
    var symbol: String
    var tint: Color? = nil
    @Binding var tags: [Tag]
    var placeholder: String
    @State private var draft = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.app(11.5, .semibold))
                .foregroundStyle(tint ?? .secondary)
                .labelStyle(.titleAndIcon)
            FlowLayout(spacing: 5, alignment: .leading) {
                ForEach(tags) { tag in
                    TagChip(text: tag.text, tint: tint) {
                        withAnimation(Motion.spring) { tags.removeAll { $0.id == tag.id } }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.doc(12.5))
                .onSubmit(add)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.embedFill(scheme)))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(Motion.spring) { tags.append(Tag(text: text)) }
        draft = ""
    }
}

private struct TagChip: View {
    var text: String
    var tint: Color?
    var onRemove: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.doc(12.5)).lineLimit(1)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill((tint ?? .primary).opacity(tint == nil ? (scheme == .dark ? 0.11 : 0.07) : 0.13)))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}

/// One condition: a counter towards a target, the points it is worth, and any values it feeds.
private struct ActionRow: View {
    @Binding var action: ActionItem
    let space: SpaceModel
    let ownBlock: UUID
    var onDelete: () -> Void

    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var picking = false

    var body: some View {
        let done = action.isDone
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                progressControl(done: done)
                TextField(L("What will you do?", "무엇을 할 건가요?"), text: $action.title)
                    .textFieldStyle(.plain)
                    .font(.doc(13.5, done ? .medium : .regular))
                Spacer(minLength: 6)
                numberPill(prefix: "×", value: Binding(get: { Double(action.target) }, set: { action.target = max(1, min(99, Int($0))) }),
                           help: L("How many times", "목표 횟수"))
                numberPill(prefix: action.scoreDelta >= 0 ? "+" : "", value: $action.scoreDelta, suffix: L("pts", "점"), tint: Theme.accent,
                           help: L("Points added to this score when done", "완료하면 이 점수에 더해지는 값"))
                IconButton(symbol: "link.badge.plus", size: 12, side: 26, help: L("Also change another value when done", "완료 시 다른 값도 변경")) {
                    picking = true
                }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    LinkPicker(space: space, mode: .value(excludingBlock: ownBlock)) { picked in
                        if case .value(let ref) = picked, !action.effects.contains(where: { $0.target == ref }) {
                            withAnimation(Motion.spring) { action.effects.append(LinkEffect(target: ref)) }
                        }
                        picking = false
                    }
                }
                IconButton(symbol: "trash", size: 11, side: 26, tint: .secondary, help: L("Delete action", "액션 삭제"), action: onDelete)
                    .opacity(hovering ? 1 : 0)
            }
            if !action.effects.isEmpty {
                FlowLayout(spacing: 6, alignment: .leading) {
                    ForEach(action.effects) { effect in
                        EffectChip(effect: effectBinding(effect.id), title: space.describe(effect.target), active: done) {
                            ui.navigate(to: Anchor(nodeID: effect.target.nodeID, blockID: effect.target.blockID), in: space)
                        } onRemove: {
                            withAnimation(Motion.spring) { action.effects.removeAll { $0.id == effect.id } }
                        }
                    }
                }
                .padding(.leading, 35)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(done ? Theme.accent.opacity(0.09) : Theme.embedFill(scheme)))
        .onHover { hovering = $0 }
        .animation(Motion.spring, value: done)
        .animation(Motion.snappy, value: hovering)
    }

    private func progressControl(done: Bool) -> some View {
        let target = max(1, action.target)
        return HStack(spacing: 5) {
            Button {
                withAnimation(Motion.spring) {
                    if done {
                        if target == 1 { action.progress = 0 }
                    } else {
                        action.progress += 1
                    }
                }
            } label: {
                ZStack {
                    Circle().stroke(Theme.chipFill(scheme), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(1, CGFloat(action.progress) / CGFloat(target)))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else if target > 1 {
                        Text("\(action.progress)").font(.app(10.5, .semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(done ? L("Done", "완료") : L("Count one more", "한 번 더 완료"))
            .contextMenu {
                Button(L("Reset Progress", "진행 초기화")) { withAnimation(Motion.spring) { action.progress = 0 } }
            }
            if target > 1 {
                Text("\(min(action.progress, target))/\(target)")
                    .font(.app(11, .medium)).monospacedDigit()
                    .foregroundStyle(done ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 26, alignment: .leading)
                if hovering, action.progress > 0 {
                    Button {
                        withAnimation(Motion.spring) { action.progress = max(0, action.progress - 1) }
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Undo one", "한 번 취소"))
                    .transition(.opacity)
                }
            }
        }
    }

    private func numberPill(prefix: String, value: Binding<Double>, suffix: String = "", tint: Color? = nil, help: String) -> some View {
        HStack(spacing: 1) {
            Text(prefix)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .frame(width: 24)
            if !suffix.isEmpty { Text(suffix).padding(.leading, 1) }
        }
        .font(.app(11.5, .semibold)).monospacedDigit()
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Capsule().fill((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.13)))
        .help(help)
    }

    private func effectBinding(_ id: UUID) -> Binding<LinkEffect> {
        Binding(get: { action.effects.first { $0.id == id } ?? LinkEffect(id: id, target: ValueRef(nodeID: UUID(), blockID: UUID(), itemID: nil)) },
                set: { value in
                    if let index = action.effects.firstIndex(where: { $0.id == id }) { action.effects[index] = value }
                })
    }
}

/// "When done, add N to that value" — click the name to jump there.
private struct EffectChip: View {
    @Binding var effect: LinkEffect
    var title: String
    var active: Bool
    var onOpen: () -> Void
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        let color: Color = active ? Theme.accent : .secondary
        HStack(spacing: 5) {
            Image(systemName: active ? "link" : "link").font(.system(size: 9, weight: .bold))
            Text(title).font(.app(11.5, .medium)).lineLimit(1)
                .onTapGesture(perform: onOpen)
                .help(L("Go to this value", "이 값으로 이동"))
            HStack(spacing: 0) {
                Text(effect.delta >= 0 ? "+" : "")
                TextField("0", value: $effect.delta, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: 26)
            }
            .font(.app(11.5, .bold)).monospacedDigit()
            .padding(.horizontal, 4)
            .background(Capsule().fill(color.opacity(0.16)))
            if hovering {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(color)
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.11)))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.spring, value: active)
    }
}

private struct LogRow: View {
    @Binding var entry: LogEntry
    var onDelete: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Button {
                withAnimation(Motion.snappy) { entry.impact = entry.impact == 1 ? -1 : entry.impact + 1 }
            } label: {
                Image(systemName: entry.impact > 0 ? "arrow.up.circle.fill" : entry.impact < 0 ? "arrow.down.circle.fill" : "circle.dotted")
                    .font(.system(size: 14))
                    .foregroundStyle(entry.impact > 0 ? AnyShapeStyle(Theme.positive) : entry.impact < 0 ? AnyShapeStyle(Theme.negative) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(L("Positive, neutral or negative sign — click to change", "긍정·중립·부정 신호 — 클릭해서 변경"))
            DatePicker("", selection: $entry.date, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            TextField(L("What happened?", "무슨 일이 있었나요?"), text: $entry.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.doc(13.5))
                .lineLimit(1...4)
            IconButton(symbol: "trash", size: 11, side: 24, tint: .secondary, help: L("Delete", "삭제"), action: onDelete)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.embedFill(scheme)))
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
    }
}
