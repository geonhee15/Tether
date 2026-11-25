import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    let ui = AppUI()
    let editor = EditorController()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
        Demo.prepare(store: store, ui: ui)
        NSApp.mainMenu = buildMenu()

        let env = ProcessInfo.processInfo.environment
        let size = Demo.windowSize ?? NSSize(width: 1180, height: 760)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 940, height: 620)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let root = RootView()
            .environment(store)
            .environment(ui)
            .environment(editor)
        window.contentView = NSHostingView(rootView: root)
        window.center()
        if env["TETHER_DATA_DIR"] == nil { window.setFrameAutosaveName("TetherMainWindow") }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        Demo.runScene(store: store, ui: ui, editor: editor, window: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        SleepGuard.shared.stop()
        store.flushAll(closing: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item(L("About Tether", "Tether에 관하여"), #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Settings…", "설정…"), #selector(showSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("Hide Tether", "Tether 가리기"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: L("Quit Tether", "Tether 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        main.addItem(submenu(AppInfo.name, appMenu))

        let file = NSMenu(title: L("File", "파일"))
        file.addItem(item(L("New Node", "새 노드"), #selector(newNode), "t"))
        file.addItem(item(L("Add File…", "파일 추가…"), #selector(addFile), "o"))
        let newSpace = item(L("New Space", "새 Space"), #selector(newSpace), "n")
        newSpace.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(newSpace)
        file.addItem(item(L("Close Node", "노드 닫기"), #selector(closeNode), "w"))
        file.addItem(item(L("Save", "저장"), #selector(saveNow), "s"))
        file.addItem(.separator())
        let home = item(L("Space Home", "Space 홈"), #selector(goHome), "h")
        home.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(home)
        main.addItem(submenu(file.title, file))

        let edit = NSMenu(title: L("Edit", "편집"))
        edit.addItem(item(L("Undo", "실행 취소"), #selector(undoEdit(_:)), "z"))
        let redo = item(L("Redo", "실행 복귀"), #selector(redoEdit(_:)), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: L("Cut", "오려두기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: L("Copy", "복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: L("Paste", "붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: L("Select All", "전체 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        main.addItem(submenu(edit.title, edit))

        let view = NSMenu(title: L("View", "보기"))
        let awake = item(L("Keep Awake Mode", "절전 방지 모드"), #selector(toggleAwake), "k")
        awake.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(awake)
        main.addItem(submenu(view.title, view))

        let windowMenu = NSMenu(title: L("Window", "윈도우"))
        windowMenu.addItem(NSMenuItem(title: L("Minimize", "최소화"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L("Zoom", "확대/축소"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        main.addItem(submenu(windowMenu.title, windowMenu))
        NSApp.windowsMenu = windowMenu
        return main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    @objc private func showAbout() { ui.showSettings(.about) }
    @objc private func showSettings() { ui.showSettings(ui.settingsTab) }

    /// The Space currently on screen, when edits to it can be made (not in a sheet, not asleep).
    private var editableSpace: SpaceModel? {
        guard ui.overlay == nil, !ui.isAwake, let space = store.activeSpace, space.info.isConfigured else { return nil }
        return space
    }

    @objc private func saveNow() {
        guard let space = store.activeSpace else { return }
        store.save(space)
        ui.flash(L("Saved", "저장했어요"), symbol: "checkmark.circle.fill")
    }

    /// ⌘Z steps the whole Space back: typing, formatting, objects, links, deleted nodes.
    /// In a sheet (login, settings) it falls back to the text field's own undo.
    @objc private func undoEdit(_ sender: Any?) {
        guard let space = editableSpace else {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: sender)
            return
        }
        if store.undo(in: space) {
            ui.flash(L("Undone", "실행 취소됨"), symbol: "arrow.uturn.backward.circle.fill")
        } else {
            NSSound.beep()
        }
    }

    @objc private func redoEdit(_ sender: Any?) {
        guard let space = editableSpace else {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: sender)
            return
        }
        if store.redo(in: space) {
            ui.flash(L("Redone", "다시 실행됨"), symbol: "arrow.uturn.forward.circle.fill")
        } else {
            NSSound.beep()
        }
    }

    @objc private func addFile() {
        guard let space = editableSpace else { return }
        FileImporter.pick(into: space, store: store, ui: ui)
    }

    @objc private func newSpace() {
        guard editableSpace != nil, let account = store.activeAccount else { return }
        SpaceActions.create(in: account.id, store: store, ui: ui)
    }

    @objc private func toggleAwake() {
        ui.setAwake(!ui.isAwake)
    }

    @objc private func newNode() {
        guard !ui.isAwake, let space = store.activeSpace, space.info.isConfigured else { return }
        withAnimation(Motion.spring) { _ = space.addNode() }
    }

    @objc private func closeNode() {
        if ui.isAwake { return }
        if ui.overlay != nil { ui.dismiss(); return }
        if let space = store.activeSpace, let active = space.activeTab {
            withAnimation(Motion.spring) { space.closeTab(active) }
        } else {
            window?.performClose(nil)
        }
    }

    @objc private func goHome() {
        guard let space = store.activeSpace else { return }
        withAnimation(Motion.spring) { space.activeTab = nil }
    }
}
