import SwiftUI

/// Sign in / create account. Full-screen when nobody is signed in, a sheet when adding another account.
struct LoginView: View {
    var isSheet = false

    private enum Mode: Hashable { case signIn, signUp }

    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
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
            withAnimation(Motion.enabled ? .spring(response: 0.55, dampingFraction: 0.8) : nil) { appeared = true }
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                TetherLogo(size: 62)
                Text(AppInfo.name)
                    .font(.app(26, .bold))
                Text(isSheet ? L("Add another Space", "다른 Space 추가")
                             : L("Notes, numbers and people — tethered together.", "노트와 수치, 사람을 하나로 잇는 공간"))
                    .font(.app(12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SlidingPicker(options: [(Mode.signIn, L("Sign In", "로그인"), nil), (Mode.signUp, L("Create Account", "계정 만들기"), nil)],
                          selection: $mode)

            VStack(spacing: 10) {
                GlassField(symbol: "person", placeholder: L("Username", "유저네임"), text: $username, onSubmit: submit)
                GlassField(symbol: "lock", placeholder: L("Password", "비밀번호"), text: $password, secure: true, onSubmit: submit)
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: submit) {
                Text(mode == .signIn ? L("Sign In", "로그인") : L("Create Account", "계정 만들기"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(mode == .signUp && !store.canAddAccount)

            if mode == .signIn, !store.signedOutAccounts.isEmpty {
                VStack(spacing: 7) {
                    Text(L("On this Mac", "이 Mac의 계정"))
                        .font(.app(11)).foregroundStyle(.tertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(store.signedOutAccounts) { account in
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

    private func submit() {
        do {
            if mode == .signIn {
                try store.signIn(username: username, password: password)
            } else {
                try store.signUp(username: username, password: password, email: email)
            }
            error = nil
            if isSheet { ui.dismiss() }
        } catch let failure as AuthError {
            error = failure.message
            withAnimation(Motion.enabled ? .linear(duration: 0.4) : nil) { attempts += 1 }
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
