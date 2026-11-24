import AppKit
import SwiftUI

/// System preferences, shown as a glass sheet over the app.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var exportMessage: String?

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 0) {
            sidebar(selection: $ui.settingsTab)
            Rectangle().fill(Theme.cardStroke(scheme)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch ui.settingsTab {
                    case .general: general
                    case .appearance: appearance
                    case .editor: editorTab
                    case .data: data
                    case .about: about
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(ui.settingsTab)
                .transition(.opacity.combined(with: .offset(x: 10)))
            }
            .animation(Motion.smooth, value: ui.settingsTab)
        }
        .frame(width: 780, height: 560)
        .glass(radius: 28, frost: 0.8)
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", size: 11, side: 26, help: L("Close", "닫기")) { ui.dismiss() }
                .padding(12)
        }
    }

    // MARK: Sidebar

    private func sidebar(selection: Binding<SettingsTab>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Settings", "설정"))
                .font(.app(18, .bold))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            ForEach(SettingsTab.allCases) { tab in
                let selected = selection.wrappedValue == tab
                Button {
                    withAnimation(Motion.snappy) { selection.wrappedValue = tab }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: symbol(tab))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.accent))
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Theme.accent : Theme.accent.opacity(0.14)))
                        Text(title(tab)).font(.app(13, selected ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.hoverFill(scheme).opacity(1.4) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            CreditFooter()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(width: 196)
    }

    private func title(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return L("General", "일반")
        case .appearance: return L("Appearance", "모양")
        case .editor: return L("Editor", "에디터")
        case .data: return L("Data", "데이터")
        case .about: return L("About", "정보")
        }
    }

    private func symbol(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .editor: return "textformat"
        case .data: return "externaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }

    // MARK: General

    private var general: some View {
        let settings = AppSettings.shared
        return Group {
            header(L("General", "일반"), L("Language and how the app behaves.", "언어와 앱 동작 방식"))
            group {
                SettingsRow(title: L("Language", "언어"), subtitle: L("Applies immediately.", "바로 적용돼요.")) {
                    SlidingPicker(options: AppLanguage.allCases.map { ($0, $0.title, nil) },
                                  selection: Binding(get: { settings.language }, set: { settings.language = $0 }))
                }
                rowDivider
                SettingsRow(title: L("Animations", "애니메이션"), subtitle: L("Transitions, springs and hover effects.", "전환·스프링·호버 효과")) {
                    Toggle("", isOn: Binding(get: { settings.animations }, set: { settings.animations = $0 })).labelsHidden().toggleStyle(.switch)
                }
                rowDivider
                SettingsRow(title: L("Ambient light", "배경 조명 움직임"), subtitle: L("Slowly drifting colour behind the glass.", "글래스 뒤에서 천천히 흐르는 색")) {
                    Toggle("", isOn: Binding(get: { settings.ambientMotion }, set: { settings.ambientMotion = $0 })).labelsHidden().toggleStyle(.switch)
                }
            }
            header(L("Shortcuts", "단축키"), nil)
            group {
                shortcut(L("New node", "새 노드"), "⌘T")
                rowDivider
                shortcut(L("Close node tab", "노드 탭 닫기"), "⌘W")
                rowDivider
                shortcut(L("Space home", "Space 홈"), "⇧⌘H")
                rowDivider
                shortcut(L("Undo · Redo (any edit in the Space)", "실행 취소 · 다시 실행 (Space의 모든 편집)"), "⌘Z  ⇧⌘Z")
                rowDivider
                shortcut(L("Save now", "지금 저장"), "⌘S")
                rowDivider
                shortcut(L("Keep awake mode", "절전 방지 모드"), "⇧⌘K")
                rowDivider
                shortcut(L("Bold · Italic · Underline", "굵게 · 기울임 · 밑줄"), "⌘B  ⌘I  ⌘U")
                rowDivider
                shortcut(L("Strikethrough · Clear formatting", "취소선 · 서식 지우기"), "⇧⌘X  ⇧⌘\\")
            }
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        SettingsRow(title: title, subtitle: nil) {
            Text(keys).font(.app(12, .medium)).foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        let settings = AppSettings.shared
        return Group {
            header(L("Appearance", "모양"), L("Light or dark, colour theme and the glass itself.", "라이트/다크, 색 테마, 글래스 질감"))
            group {
                SettingsRow(title: L("Mode", "모드"), subtitle: nil) {
                    SlidingPicker(options: [(AppearanceMode.system, L("System", "시스템"), "circle.lefthalf.filled"),
                                            (AppearanceMode.light, L("Light", "라이트"), "sun.max"),
                                            (AppearanceMode.dark, L("Dark", "다크"), "moon")],
                                  selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0 }))
                }
                rowDivider
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Theme", "테마")).font(.app(13, .medium))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(Skin.allCases) { skin in
                            SkinSwatch(skin: skin, selected: settings.skin == skin) {
                                withAnimation(Motion.spring) { settings.skin = skin }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                rowDivider
                SettingsRow(title: L("Glass clarity", "글래스 투명도"), subtitle: L("How much of what's behind shows through.", "뒤 배경이 비치는 정도")) {
                    Slider(value: Binding(get: { settings.glassClarity }, set: { settings.glassClarity = $0 }), in: 0...1)
                        .frame(width: 180)
                }
                rowDivider
                SettingsRow(title: L("Interface font", "인터페이스 글꼴"), subtitle: nil) {
                    fontPicker(FontChoice.interface, Binding(get: { settings.uiFont }, set: { settings.uiFont = $0 }))
                }
            }
        }
    }

    private func fontPicker(_ choices: [FontChoice], _ selection: Binding<FontChoice>) -> some View {
        Picker("", selection: selection) {
            ForEach(choices) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .frame(width: 190)
    }

    // MARK: Editor

    private var editorTab: some View {
        let settings = AppSettings.shared
        return Group {
            header(L("Editor", "에디터"), L("Defaults for text in every node. Text you styled by hand keeps its own font and size.",
                                           "모든 노드 글의 기본값이에요. 직접 지정한 글꼴·크기는 그대로 유지돼요."))
            group {
                SettingsRow(title: L("Writing font", "본문 글꼴"), subtitle: nil) {
                    fontPicker(FontChoice.allCases, Binding(get: { settings.editorFont }, set: { settings.editorFont = $0 }))
                }
                rowDivider
                SettingsRow(title: L("Text size", "글자 크기"), subtitle: "\(formatNumber(settings.editorFontSize)) pt") {
                    Slider(value: Binding(get: { settings.editorFontSize }, set: { settings.editorFontSize = $0 }), in: 12...22, step: 1)
                        .frame(width: 180)
                }
                rowDivider
                SettingsRow(title: L("Line spacing", "줄 간격"), subtitle: nil) {
                    SlidingPicker(options: [(LineSpacingChoice.compact, L("Compact", "좁게"), nil), (LineSpacingChoice.normal, L("Normal", "보통"), nil),
                                            (LineSpacingChoice.relaxed, L("Relaxed", "넓게"), nil)],
                                  selection: Binding(get: { settings.lineSpacing }, set: { settings.lineSpacing = $0 }))
                }
                rowDivider
                SettingsRow(title: L("Page width", "페이지 너비"), subtitle: L("Shorter lines are easier to read.", "줄이 짧을수록 읽기 편해요.")) {
                    SlidingPicker(options: [(ContentWidthChoice.narrow, L("Narrow", "좁게"), nil), (ContentWidthChoice.regular, L("Regular", "보통"), nil),
                                            (ContentWidthChoice.wide, L("Wide", "넓게"), nil)],
                                  selection: Binding(get: { settings.contentWidth }, set: { settings.contentWidth = $0 }))
                }
                rowDivider
                SettingsRow(title: L("Check spelling while typing", "입력 중 맞춤법 검사"), subtitle: nil) {
                    Toggle("", isOn: Binding(get: { settings.spellCheck }, set: { settings.spellCheck = $0 })).labelsHidden().toggleStyle(.switch)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Preview", "미리보기")).font(.app(11, .semibold)).foregroundStyle(.secondary)
                Text(L("The quick brown fox jumps over the lazy dog. 다람쥐 헌 쳇바퀴에 타고파.",
                       "다람쥐 헌 쳇바퀴에 타고파. The quick brown fox jumps over the lazy dog."))
                    .font(settings.editorFont.font(size: settings.editorFontSize))
                    .lineSpacing(settings.lineSpacing.points)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .card()
        }
    }

    // MARK: Data

    private var data: some View {
        Group {
            header(L("Data", "데이터"), L("Everything stays on this Mac as plain JSON files.", "모든 데이터는 이 Mac에 JSON 파일로만 저장돼요."))
            group {
                SettingsRow(title: L("Data folder", "데이터 폴더"), subtitle: store.dataDir.path) {
                    Button(L("Show in Finder", "Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([store.dataDir]) }
                        .buttonStyle(SoftButtonStyle())
                }
                rowDivider
                SettingsRow(title: L("Back up", "백업"), subtitle: exportMessage ?? L("Copy every account and Space to a folder you choose.", "모든 계정과 Space를 원하는 폴더에 복사해요.")) {
                    Button(L("Export…", "내보내기…")) { export() }
                        .buttonStyle(SoftButtonStyle())
                }
                rowDivider
                SettingsRow(title: L("Accounts", "계정"),
                            subtitle: L("\(store.accounts.count) of \(AppInfo.maxAccounts) used · \(store.session.loggedIn.count) signed in",
                                        "\(AppInfo.maxAccounts)개 중 \(store.accounts.count)개 사용 · \(store.session.loggedIn.count)개 로그인됨")) {
                    Button(L("Add account", "계정 추가")) { ui.present(.addAccount) }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(!store.canAddAccount && store.signedOutAccounts.isEmpty)
                }
            }
            group {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { rowDivider }
                    let space = store.spaces[account.id]
                    SettingsRow(title: space?.info.name ?? account.username,
                                subtitle: "@\(account.username)" + (account.email.isEmpty ? "" : " · \(account.email)")) {
                        if space != nil {
                            Button(L("Sign Out", "로그아웃")) { withAnimation(Motion.spring) { store.logOut(account.id) } }
                                .buttonStyle(SoftButtonStyle())
                        } else {
                            Chip(text: L("Signed out", "로그아웃됨"))
                        }
                    }
                }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tether Backup \(Date().formatted(.iso8601.year().month().day()))"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportBackup(to: url)
            exportMessage = L("Saved to \(url.lastPathComponent).", "\(url.lastPathComponent)에 저장했어요.")
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    // MARK: About

    private var about: some View {
        Group {
            VStack(spacing: 10) {
                TetherLogo(size: 76)
                Text(AppInfo.name).font(.app(26, .bold))
                Text(L("Version \(AppInfo.version)", "버전 \(AppInfo.version)") + "  (\(AppInfo.build))")
                    .font(.app(12, .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Developed by \(AppInfo.developer)").font(.app(13, .medium))
                    GitHubButton(url: AppInfo.developerURL, size: 16)
                }
                Text(AppInfo.aiCreditLine)
                    .font(.app(12.5, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent.opacity(0.13)))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            header(L("Built with", "사용 기술"), nil)
            group {
                ForEach(Array(AppInfo.stack.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { rowDivider }
                    techRow(entry.0, entry.1)
                }
            }
            header(L("Design & tooling", "디자인 · 도구"), nil)
            group {
                ForEach(Array(AppInfo.designNotes.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { rowDivider }
                    techRow(entry.0, entry.1)
                }
            }
            group {
                SettingsRow(title: L("Source code", "소스 코드"), subtitle: AppInfo.repositoryURL.absoluteString.replacingOccurrences(of: "https://", with: "")) {
                    GitHubButton(url: AppInfo.repositoryURL, size: 18)
                }
            }
            Text("© 2026 \(AppInfo.developer)")
                .font(.app(10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func techRow(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).font(.app(13, .medium)).frame(width: 170, alignment: .leading)
            Text(detail).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Building blocks

    private func header(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(16, .bold))
            if let subtitle {
                Text(subtitle).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .card()
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.cardStroke(scheme)).frame(height: 1).padding(.leading, 14)
    }
}

struct SettingsRow<Control: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(13, .medium))
                if let subtitle {
                    Text(subtitle).font(.app(11.5)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 46)
    }
}

private struct SkinSwatch: View {
    var skin: Skin
    var selected: Bool
    var action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: skin.glow, startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(scheme == .dark ? 0.22 : 0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    Circle().fill(skin.accent).frame(width: 10, height: 10)
                }
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? skin.accent : Theme.cardStroke(scheme), lineWidth: selected ? 2.5 : 1)
                )
                Text(skin.title).font(.app(11.5, selected ? .semibold : .regular)).foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift(1.04)
    }
}
