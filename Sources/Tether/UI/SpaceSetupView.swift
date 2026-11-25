import SwiftUI

/// Name, subtitle, description, icon and colour of a Space. Shown full-screen right after a
/// Space is created (with a new account, or added to one), and as a sheet afterwards.
struct SpaceSetupView: View {
    let space: SpaceModel
    var onboarding: Bool

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    /// The account this Space belongs to, and how many Spaces it has.
    private var owner: Account? { store.owner(of: space.id) }
    private var isFirstSpace: Bool { (owner?.spaceIDs.count ?? 1) < 2 }

    private var heading: String {
        if !onboarding { return L("Space Settings", "Space 설정") }
        return isFirstSpace ? L("Set up your Space", "Space 설정하기") : L("New Space", "새 Space 만들기")
    }

    private var caption: String {
        let name = owner?.username ?? ""
        if !onboarding {
            return L("In the account “\(name)”", "“\(name)” 계정의 Space")
        }
        return isFirstSpace
            ? L("A Space is your own area for one part of life. You can change all of this later.",
                "Space는 삶의 한 영역을 위한 나만의 공간이에요. 나중에 언제든 바꿀 수 있어요.")
            : L("Another area in the account “\(name)”, with its own nodes, files and links.",
                "“\(name)” 계정 안의 또 다른 공간이에요. 노드와 파일, 링크를 따로 가져요.")
    }

    var body: some View {
        @Bindable var space = space
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                SpaceBadge(symbol: space.info.symbol, color: space.color, size: 54)
                    .animation(Motion.spring, value: space.info.symbol)
                    .animation(Motion.spring, value: space.info.colorIndex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading)
                        .font(.app(20, .bold))
                    Text(caption)
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                field(L("Name", "이름")) {
                    GlassField(placeholder: L("e.g. Studio, Journal, Research", "예: 스튜디오, 저널, 리서치"), text: $space.info.name)
                }
                field(L("Subtitle", "부제목"), optional: true) {
                    GlassField(placeholder: L("A short line under the name", "이름 아래에 보일 짧은 한 줄"), text: $space.info.subtitle)
                }
                field(L("Description", "설명"), optional: true) {
                    TextField(L("What is this Space for?", "이 Space는 무엇을 위한 곳인가요?"), text: $space.info.about, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(13))
                        .lineLimit(3...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1))
                }
            }

            field(L("Icon", "아이콘")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 9), alignment: .leading, spacing: 8) {
                    ForEach(SymbolSets.space, id: \.self) { symbol in
                        let selected = space.info.symbol == symbol
                        Button {
                            withAnimation(Motion.snappy) { space.info.symbol = symbol }
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? AnyShapeStyle(space.color) : AnyShapeStyle(Theme.chipFill(scheme)))
                                )
                        }
                        .buttonStyle(.plain)
                        .hoverLift(1.08)
                    }
                }
            }

            field(L("Colour", "색상")) {
                HStack(spacing: 10) {
                    ForEach(Theme.spaceColors.indices, id: \.self) { index in
                        let selected = space.info.colorIndex == index
                        Button {
                            withAnimation(Motion.snappy) { space.info.colorIndex = index }
                        } label: {
                            Circle()
                                .fill(Theme.spaceColors[index])
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: selected ? 2 : 0).padding(2))
                                .overlay(Circle().strokeBorder(Theme.spaceColors[index], lineWidth: selected ? 2 : 0).padding(-2))
                        }
                        .buttonStyle(.plain)
                        .hoverLift(1.12)
                    }
                }
            }

            HStack(spacing: 10) {
                if !onboarding {
                    Button(L("Delete Space…", "Space 삭제…")) {
                        ui.dismiss()
                        SpaceActions.confirmDelete(space, store: store, ui: ui)
                    }
                    .buttonStyle(SoftButtonStyle(tint: Theme.negative))
                    .disabled(isFirstSpace)
                    .help(isFirstSpace ? L("An account keeps at least one Space.", "계정에는 Space가 하나 이상 있어야 해요.") : "")
                    Button(L("Account…", "계정 관리…")) { ui.present(.account) }
                        .buttonStyle(SoftButtonStyle())
                } else if isFirstSpace {
                    Button(L("Use another account", "다른 계정 사용")) {
                        if let owner { withAnimation(Motion.spring) { store.logOut(owner.id) } }
                    }
                    .buttonStyle(SoftButtonStyle())
                } else {
                    Button(L("Cancel", "취소")) {
                        withAnimation(Motion.spring) { _ = store.deleteSpace(space.id) }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button {
                    if space.info.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        let position = (owner?.spaceIDs.firstIndex(of: space.id) ?? 0) + 1
                        space.info.name = isFirstSpace ? (owner?.username ?? "Space") : "Space \(position)"
                    }
                    if onboarding {
                        withAnimation(Motion.spring) { space.info.isConfigured = true }
                        store.resetHistory(for: space)
                    } else {
                        ui.dismiss()
                    }
                } label: {
                    Text(onboarding ? (isFirstSpace ? L("Enter Space", "Space 시작하기") : L("Create Space", "Space 만들기")) : L("Done", "완료"))
                        .padding(.horizontal, 10)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .glass(radius: 28, frost: 0.35)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Motion.spring) { appeared = true } }
    }

    private func field<Content: View>(_ label: String, optional: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(text: label)
                if optional {
                    Text(L("optional", "선택")).font(.app(10)).foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }
}
