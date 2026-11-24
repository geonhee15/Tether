import SwiftUI

/// Sign in / create account / reset a forgotten password.
/// Full-screen when nobody is signed in, a sheet when adding another account.
struct LoginView: View {
    var isSheet = false

    private enum Mode: Hashable { case signIn, signUp, reset }

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var confirmation = ""
    @State private var verifying = false
    @State private var error: String?
    @State private var attempts = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            card
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
            if !isSheet {
                VStack {
                    Spacer()
                    CreditFooter()
                        .padding(.bottom, 22)
                        .opacity(appeared ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if store.accounts.isEmpty { mode = .signUp }
            if ui.demoResetPassword {
                mode = .reset
                username = store.accounts.first?.username ?? ""
            }
            withAnimation(Motion.enabled ? .spring(response: 0.55, dampingFraction: 0.8) : nil) { appeared = true }
        }
    }

    private var subtitle: String {
        if mode == .reset { return L("Choose a new password for an account on this Mac.", "이 Mac에 있는 계정의 새 비밀번호를 정하세요.") }
        return isSheet ? L("Add another Space", "다른 Space 추가")
                       : L("Notes, numbers and people — tethered together.", "노트와 수치, 사람을 하나로 잇는 공간")
    }

    private var actionTitle: String {
        switch mode {
        case .signIn: return L("Sign In", "로그인")
        case .signUp: return L("Create Account", "계정 만들기")
        case .reset: return verifying ? L("Waiting for confirmation…", "본인 확인 중…") : L("Confirm & Reset", "본인 확인 후 재설정")
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                TetherLogo(size: 62)
                Text(mode == .reset ? L("Reset Password", "비밀번호 재설정") : AppInfo.name)
                    .font(.app(26, .bold))
                Text(subtitle)
                    .font(.app(12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode != .reset {
                SlidingPicker(options: [(Mode.signIn, L("Sign In", "로그인"), nil), (Mode.signUp, L("Create Account", "계정 만들기"), nil)],
                              selection: $mode)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                GlassField(symbol: "person", placeholder: L("Username", "유저네임"), text: $username, onSubmit: submit)
                GlassField(symbol: "lock", placeholder: mode == .reset ? L("New password", "새 비밀번호") : L("Password", "비밀번호"),
                           text: $password, secure: true, onSubmit: submit)
                if mode == .reset {
                    GlassField(symbol: "lock.rotation", placeholder: L("New password again", "새 비밀번호 다시 입력"),
                               text: $confirmation, secure: true, onSubmit: submit)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if mode == .signUp {
                    GlassField(symbol: "envelope", placeholder: L("Email (optional)", "이메일 (선택)"), text: $email, onSubmit: submit)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .modifier(Shake(animatableData: CGFloat(attempts)))

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.app(12))
                    .foregroundStyle(Theme.negative)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: submit) {
                HStack(spacing: 7) {
                    if mode == .reset { Image(systemName: "touchid") }
                    Text(actionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((mode == .signUp && !store.canAddAccount) || verifying)

            if mode == .reset {
                VStack(spacing: 10) {
                    Text(L("macOS will ask for Touch ID or your Mac login password — the same thing that protects the files on this Mac.",
                           "macOS가 Touch ID 또는 Mac 로그인 암호를 물어봐요. 이 Mac의 파일을 지키는 바로 그 인증이에요."))
                        .font(.app(11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    textButton(L("Back to sign in", "로그인으로 돌아가기"), symbol: "chevron.left") { switchMode(.signIn) }
                }
                .transition(.opacity)
            }

            if mode == .signIn, !store.accounts.isEmpty {
                textButton(L("Forgot password?", "비밀번호를 잊으셨나요?")) { switchMode(.reset) }
                    .transition(.opacity)
            }

            if mode != .signUp, !chipAccounts.isEmpty {
                VStack(spacing: 7) {
                    Text(L("On this Mac", "이 Mac의 계정"))
                        .font(.app(11)).foregroundStyle(.tertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(chipAccounts) { account in
                            Button {
                                username = account.username
                                error = nil
                            } label: {
                                Chip(text: account.username, symbol: "person.fill",
                                     tint: username == account.username ? Theme.accent : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity)
            }

            if mode == .signUp {
                Text(L("\(store.accounts.count) of \(AppInfo.maxAccounts) accounts used · each account is its own Space",
                       "계정 \(store.accounts.count)/\(AppInfo.maxAccounts)개 사용 중 · 계정마다 하나의 Space"))
                    .font(.app(11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }

            if isSheet {
                CreditFooter().padding(.top, 2)
            }
        }
        .padding(28)
        .frame(width: 380)
        .glass(radius: 28, frost: 0.35)
        .overlay(alignment: .topTrailing) {
            if isSheet {
                IconButton(symbol: "xmark", size: 11, side: 26, help: L("Close", "닫기")) { ui.dismiss() }
                    .padding(12)
            }
        }
        .animation(Motion.spring, value: mode)
        .animation(Motion.snappy, value: error)
    }

    /// Signing in offers the signed-out accounts; resetting offers every account.
    private var chipAccounts: [Account] {
        mode == .reset ? store.accounts : store.signedOutAccounts
    }

    private func textButton(_ title: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
                Text(title).font(.app(12, .medium))
            }
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func switchMode(_ next: Mode) {
        error = nil
        password = ""
        confirmation = ""
        mode = next
    }

    private func fail(_ message: String) {
        error = message
        withAnimation(Motion.enabled ? .linear(duration: 0.4) : nil) { attempts += 1 }
    }

    private func submit() {
        guard !verifying else { return }
        do {
            switch mode {
            case .signIn:
                try store.signIn(username: username, password: password)
            case .signUp:
                try store.signUp(username: username, password: password, email: email)
            case .reset:
                try beginReset()
                return
            }
            error = nil
            if isSheet { ui.dismiss() }
        } catch let failure as AuthError {
            fail(failure.message)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Checks the form, then has macOS confirm the Mac's owner before the password is replaced.
    private func beginReset() throws {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else { throw AuthError.emptyFields }
        guard let account = store.account(named: username) else { throw AuthError.unknownUser }
        guard password == confirmation else { throw AuthError.passwordMismatch }
        error = nil
        verifying = true
        let newPassword = password
        MacAuth.confirm(reason: L("reset the password for “\(account.username)”", "“\(account.username)” 계정의 비밀번호를 재설정")) { outcome in
            verifying = false
            switch outcome {
            case .confirmed:
                finishReset(account, newPassword)
            case .unavailable:
                // Nothing on this Mac to authenticate against, so the Mac itself is the only gate.
                finishReset(account, newPassword)
            case .cancelled:
                break
            case .failed(let message):
                fail(message.isEmpty ? L("macOS couldn't confirm it's you.", "macOS가 본인 확인을 하지 못했어요.") : message)
            }
        }
    }

    private func finishReset(_ account: Account, _ newPassword: String) {
        do {
            try store.setPassword(for: account.id, to: newPassword)
            try store.signIn(username: account.username, password: newPassword)
            confirmation = ""
            if isSheet { ui.dismiss() }
        } catch let failure as AuthError {
            fail(failure.message)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Horizontal wiggle for a failed attempt.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, max(width, 0)) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = alignment == .leading ? bounds.minX : bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + size.width
            if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
