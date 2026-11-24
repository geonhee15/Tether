import SwiftUI

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui

    var body: some View {
        ZStack {
            Backdrop(spaceColor: store.activeSpace.map { $0.color })

            Group {
                if let space = store.activeSpace {
                    if space.info.isConfigured {
                        MainView(space: space)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    } else {
                        SpaceSetupView(space: space, onboarding: true)
                            .id(space.id)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                } else {
                    LoginView()
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }

            overlayLayer
        }
        .ignoresSafeArea()
        .font(.app(13))
        .tint(Theme.accent)
        .environment(\.locale, Locale(identifier: AppSettings.shared.language.rawValue))
        .animation(Motion.spring, value: store.session.active)
        .animation(Motion.spring, value: store.activeSpace?.info.isConfigured)
    }

    @ViewBuilder
    private var overlayLayer: some View {
        if let overlay = ui.overlay {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { ui.dismiss() }
                    .transition(.opacity)
                Group {
                    switch overlay {
                    case .settings:
                        SettingsView()
                    case .spaceSettings:
                        if let space = store.activeSpace { SpaceSetupView(space: space, onboarding: false) }
                    case .addAccount:
                        LoginView(isSheet: true)
                    }
                }
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            .zIndex(10)
            .onExitCommand { ui.dismiss() }
        }
    }
}

// MARK: Main layout

struct MainView: View {
    let space: SpaceModel
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            TabBar(space: space)
            HStack(spacing: 0) {
                SpaceRail()
                ZStack {
                    if let node = space.activeNode {
                        NodeView(node: node, space: space)
                            .id(node.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    } else {
                        SpaceHomeView(space: space)
                            .id(space.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(Motion.smooth, value: space.activeTab)
            }
            StatusFooter(space: space)
        }
    }
}

// MARK: Tabs

/// Browser-style strip: Space home, one tab per open node, and "+" for a new node.
struct TabBar: View {
    let space: SpaceModel
    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            homeTab
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(space.openTabs, id: \.self) { id in
                            if let node = space.node(id) {
                                NodeTab(node: node, space: space, namespace: namespace)
                                    .id(id)
                                    .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                            }
                        }
                        IconButton(symbol: "plus", size: 13, side: 30, help: L("New node  ⌘T", "새 노드  ⌘T")) {
                            withAnimation(Motion.spring) { _ = space.addNode() }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onChange(of: space.activeTab) { _, id in
                    if let id { withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            Spacer(minLength: 12)
        }
        .padding(.leading, 84)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(WindowDragArea())
    }

    private var homeTab: some View {
        let active = space.activeTab == nil
        return Button {
            withAnimation(Motion.spring) { space.activeTab = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 11, weight: .semibold))
                Text(space.info.name).font(.app(12, .semibold)).lineLimit(1)
            }
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                if active {
                    TabPlate().matchedGeometryEffect(id: "activeTab", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Space home  ⇧⌘H", "Space 홈  ⇧⌘H"))
    }
}

private struct TabPlate: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.82))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.08), radius: 4, y: 1)
    }
}

private struct NodeTab: View {
    let node: NodeModel
    let space: SpaceModel
    var namespace: Namespace.ID
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let active = space.activeTab == node.id
        HStack(spacing: 6) {
            Image(systemName: node.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            Text(node.displayTitle)
                .font(.app(12, active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Button {
                withAnimation(Motion.spring) { space.closeTab(node.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Theme.hoverFill(scheme)))
            }
            .buttonStyle(.plain)
            .opacity(hovering || active ? 1 : 0)
            .help(L("Close tab  ⌘W", "탭 닫기  ⌘W"))
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(minWidth: 104, maxWidth: 220)
        .frame(height: 30)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            if active {
                TabPlate().matchedGeometryEffect(id: "activeTab", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.hoverFill(scheme))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.spring) { space.activeTab = node.id } }
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contextMenu {
            Button(L("Close Tab", "탭 닫기")) { withAnimation(Motion.spring) { space.closeTab(node.id) } }
            Divider()
            Button(L("Delete Node…", "노드 삭제…"), role: .destructive) {
                confirmDelete(node: node, in: space)
            }
        }
    }
}

@MainActor
func confirmDelete(node: NodeModel, in space: SpaceModel) {
    let alert = NSAlert()
    alert.messageText = L("Delete “\(node.displayTitle)”?", "“\(node.displayTitle)” 노드를 삭제할까요?")
    alert.informativeText = L("The node, everything inserted in it and its links will be removed. This can't be undone.",
                              "노드와 그 안의 삽입물, 연결된 링크가 모두 삭제되며 되돌릴 수 없어요.")
    alert.alertStyle = .warning
    alert.addButton(withTitle: L("Delete", "삭제"))
    alert.addButton(withTitle: L("Cancel", "취소"))
    if alert.runModal() == .alertFirstButtonReturn {
        withAnimation(Motion.spring) { space.deleteNode(node.id) }
    }
}

// MARK: Space rail

/// Vertical switcher for every signed-in Space, plus "add account" and Settings.
struct SpaceRail: View {
    @Environment(Store.self) private var store
    @Environment(AppUI.self) private var ui
    @Namespace private var namespace

    var body: some View {
        VStack(spacing: 10) {
            ForEach(store.loggedInSpaces) { space in
                railItem(space)
            }
            if store.loggedInSpaces.count < AppInfo.maxAccounts {
                IconButton(symbol: "plus", size: 14, side: 38, help: L("Add or sign in to another account", "다른 계정 추가 / 로그인")) {
                    ui.present(.addAccount)
                }
            }
            Spacer(minLength: 8)
            IconButton(symbol: "gearshape", size: 15, side: 38, help: L("Settings  ⌘,", "설정  ⌘,")) {
                ui.showSettings(ui.settingsTab)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 54)
        .glass(radius: 20)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }

    private func railItem(_ space: SpaceModel) -> some View {
        let active = store.session.active == space.id
        return Button {
            withAnimation(Motion.spring) { store.switchTo(space.id) }
        } label: {
            SpaceBadge(symbol: space.info.symbol, color: space.color, size: 36)
                .saturation(active ? 1 : 0.75)
                .opacity(active ? 1 : 0.72)
                .padding(3)
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(space.color.opacity(0.9), lineWidth: 2)
                            .matchedGeometryEffect(id: "activeSpace", in: namespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverLift(1.07)
        .help(space.info.name + (space.info.subtitle.isEmpty ? "" : " — " + space.info.subtitle))
        .contextMenu {
            Button(L("Space Settings…", "Space 설정…")) {
                store.switchTo(space.id)
                ui.present(.spaceSettings)
            }
            Divider()
            Button(L("Sign Out", "로그아웃")) { withAnimation(Motion.spring) { store.logOut(space.id) } }
        }
    }
}

// MARK: Footer

struct StatusFooter: View {
    let space: SpaceModel
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if let node = space.activeNode {
                Label(L("\(node.wordCount) words", "단어 \(node.wordCount)개"), systemImage: "text.alignleft")
            } else {
                Label(L("\(space.nodes.count) nodes", "노드 \(space.nodes.count)개"), systemImage: "square.stack.3d.up")
            }
            if let saved = store.lastSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive.opacity(0.85))
                    Text(L("Saved ", "저장됨 ") + formatDate(saved, date: .omitted, time: .shortened))
                }
                .transition(.opacity)
            }
            Spacer()
            CreditFooter(compact: true)
        }
        .font(.app(11))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 28)
    }
}
