import SwiftUI

/// Name, subtitle, description, icon and colour of a Space. Shown full-screen right after an
/// account is created, and as a sheet afterwards.
struct SpaceSetupView: View {
    let space: SpaceModel
    var onboarding: Bool

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        @Bindable var space = space
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                SpaceBadge(symbol: space.info.symbol, color: space.color, size: 54)
                    .animation(Motion.spring, value: space.info.symbol)
                    .animation(Motion.spring, value: space.info.colorIndex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(onboarding ? L("Set up your Space", "Space 설정하기") : L("Space Settings", "Space 설정"))
                        .font(.app(20, .bold))
                    Text(onboarding ? L("A Space is your own area for one part of life. You can change all of this later.",
                                        "Space는 삶의 한 영역을 위한 나만의 공간이에요. 나중에 언제든 바꿀 수 있어요.")
                                    : L("Signed in as \(store.account(space.id)?.username ?? "")", "\(store.account(space.id)?.username ?? "") 계정으로 로그인됨"))
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
                    Button(L("Sign Out", "로그아웃")) {
                        ui.dismiss()
                        withAnimation(Motion.spring) { store.logOut(space.id) }
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button(L("Delete Account…", "계정 삭제…")) { confirmDeleteAccount() }
                        .buttonStyle(SoftButtonStyle(tint: Theme.negative))
                } else {
                    Button(L("Use another account", "다른 계정 사용")) {
                        withAnimation(Motion.spring) { store.logOut(space.id) }
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button {
                    if space.info.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        space.info.name = store.account(space.id)?.username ?? "Space"
                    }
                    if onboarding {
                        withAnimation(Motion.spring) { space.info.isConfigured = true }
                    } else {
                        ui.dismiss()
                    }
                } label: {
                    Text(onboarding ? L("Enter Space", "Space 시작하기") : L("Done", "완료"))
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

    private func confirmDeleteAccount() {
        let alert = NSAlert()
        alert.messageText = L("Delete this account and its Space?", "이 계정과 Space를 삭제할까요?")
        alert.informativeText = L("Every node in “\(space.info.name)” will be removed from this Mac. This can't be undone.",
                                  "“\(space.info.name)”의 모든 노드가 이 Mac에서 삭제되며 되돌릴 수 없어요.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("Delete", "삭제"))
        alert.addButton(withTitle: L("Cancel", "취소"))
        if alert.runModal() == .alertFirstButtonReturn {
            ui.dismiss()
            withAnimation(Motion.spring) { store.deleteAccount(space.id) }
        }
    }
}
