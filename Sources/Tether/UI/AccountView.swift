import SwiftUI

/// The account in front: its Spaces (open, add, delete), the other signed-in accounts, and the
/// account's own password, sign-out and deletion.
struct AccountView: View {
    let account: Account

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false
    @State private var changingPassword = false
    @State private var newPassword = ""
    @State private var newPasswordAgain = ""
    @State private var passwordError: String?
    @State private var passwordChanged = false

    var body: some View {
        let spaces = store.spaces(of: account.id)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AccountAvatar(name: account.username, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.username).font(.app(20, .bold)).lineLimit(1)
                    Text((account.email.isEmpty ? "" : account.email + "  ·  ")
                         + L("since ", "가입 ") + formatDate(account.createdAt, date: .abbreviated, time: .omitted))
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SectionLabel(text: L("Spaces", "Space"))
                    Text("\(spaces.count)/\(AppInfo.maxSpaces)").font(.app(10.5, .medium)).monospacedDigit().foregroundStyle(.tertiary)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                            if index > 0 { rowDivider }
                            spaceRow(space, onlyOne: spaces.count < 2)
                        }
                        if store.canAddSpace(to: account.id) {
                            rowDivider
                            Button {
                                SpaceActions.create(in: account.id, store: store, ui: ui)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(0.14)))
                                    Text(L("New Space", "새 Space")).font(.app(13, .medium))
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 292)
                .fixedSize(horizontal: false, vertical: true)
                .card()
            }

            if store.session.loggedIn.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: L("Signed-in accounts", "로그인된 계정"))
                    FlowLayout(spacing: 6, alignment: .leading) {
                        ForEach(store.session.loggedIn, id: \.self) { id in
                            if let other = store.account(id) {
                                Button {
                                    withAnimation(Motion.spring) { store.switchTo(id) }
                                } label: {
                                    Chip(text: other.username, symbol: id == account.id ? "checkmark" : "person.fill",
                                         tint: id == account.id ? Theme.accent : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button(L("Sign Out", "로그아웃")) {
                    ui.dismiss()
                    withAnimation(Motion.spring) { store.logOut(account.id) }
                }
                .buttonStyle(SoftButtonStyle())
                Button(passwordChanged ? L("Password Changed", "비밀번호 변경됨") : L("Change Password…", "비밀번호 변경…")) {
                    passwordChanged = false
                    changingPassword = true
                }
                .buttonStyle(SoftButtonStyle(tint: passwordChanged ? Theme.positive : nil))
                .popover(isPresented: $changingPassword, arrowEdge: .top) { passwordForm }
                Button(L("Delete Account…", "계정 삭제…")) { confirmDeleteAccount(spaces) }
                    .buttonStyle(SoftButtonStyle(tint: Theme.negative))
                Spacer()
                Button { ui.dismiss() } label: {
                    Text(L("Done", "완료")).padding(.horizontal, 10)
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

    private var rowDivider: some View {
        Rectangle().fill(Theme.cardStroke(scheme)).frame(height: 1).padding(.leading, 52)
    }

    private func spaceRow(_ space: SpaceModel, onlyOne: Bool) -> some View {
        let current = store.activeSpace?.id == space.id
        let name = space.info.name.isEmpty ? L("Untitled Space", "이름 없는 Space") : space.info.name
        let detail = [space.info.subtitle, L("\(space.nodes.count) nodes", "노드 \(space.nodes.count)개")]
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
        return HStack(spacing: 10) {
            Button {
                ui.dismiss()
                withAnimation(Motion.spring) { store.selectSpace(space.id) }
            } label: {
                HStack(spacing: 10) {
                    SpaceBadge(symbol: space.info.symbol, color: space.color, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.app(13, .semibold)).lineLimit(1)
                        Text(detail).font(.app(11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if current { Chip(text: L("Open", "열려 있음"), tint: Theme.accent) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open this Space", "이 Space 열기"))
            IconButton(symbol: "slider.horizontal.3", size: 12, help: L("Space settings", "Space 설정")) {
                store.selectSpace(space.id)
                ui.present(.spaceSettings)
            }
            IconButton(symbol: "trash", size: 12, tint: Theme.negative,
                       help: onlyOne ? L("An account keeps at least one Space.", "계정에는 Space가 하나 이상 있어야 해요.") : L("Delete this Space", "이 Space 삭제")) {
                SpaceActions.confirmDelete(space, store: store, ui: ui)
            }
            .disabled(onlyOne)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    /// You are already signed in here, so a new password is all it takes.
    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("New password for “\(account.username)”", "“\(account.username)” 계정의 새 비밀번호"))
                .font(.app(12, .semibold))
            GlassField(symbol: "lock", placeholder: L("New password", "새 비밀번호"), text: $newPassword, secure: true, onSubmit: savePassword)
            GlassField(symbol: "lock.rotation", placeholder: L("New password again", "새 비밀번호 다시 입력"), text: $newPasswordAgain, secure: true, onSubmit: savePassword)
            if let passwordError {
                Text(passwordError).font(.app(11.5)).foregroundStyle(Theme.negative)
            }
            Button(action: savePassword) {
                Text(L("Save", "저장")).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .frame(width: 280)
    }

    private func savePassword() {
        guard !newPassword.isEmpty else { passwordError = AuthError.emptyFields.message; return }
        guard newPassword == newPasswordAgain else { passwordError = AuthError.passwordMismatch.message; return }
        do {
            try store.setPassword(for: account.id, to: newPassword)
            newPassword = ""
            newPasswordAgain = ""
            passwordError = nil
            changingPassword = false
            withAnimation(Motion.snappy) { passwordChanged = true }
        } catch let failure as AuthError {
            passwordError = failure.message
        } catch {
            passwordError = error.localizedDescription
        }
    }

    private func confirmDeleteAccount(_ spaces: [SpaceModel]) {
        let nodes = spaces.reduce(0) { $0 + $1.nodes.count }
        let alert = NSAlert()
        alert.messageText = L("Delete the account “\(account.username)”?", "“\(account.username)” 계정을 삭제할까요?")
        alert.informativeText = L("Its \(spaces.count) Spaces and their \(nodes) nodes will be removed from this Mac. This can't be undone.",
                                  "Space \(spaces.count)개와 그 안의 노드 \(nodes)개가 이 Mac에서 삭제되며 되돌릴 수 없어요.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("Delete", "삭제"))
        alert.addButton(withTitle: L("Cancel", "취소"))
        if alert.runModal() == .alertFirstButtonReturn {
            ui.dismiss()
            withAnimation(Motion.spring) { store.deleteAccount(account.id) }
        }
    }
}
