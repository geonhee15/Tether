import SwiftUI
import Observation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, editor, data, about
    var id: String { rawValue }
}

/// Window-level interface state: which sheet is up, where to scroll, what to highlight.
@MainActor
@Observable
final class AppUI {
    enum Overlay: Equatable { case settings, spaceSettings, account, addAccount }

    var overlay: Overlay?
    var settingsTab: SettingsTab = .general
    /// Block to bring into view in the open node.
    var scrollTarget: UUID?
    /// Block that briefly glows after being navigated to.
    var flashBlock: UUID?
    /// Forces the insert menu open (used for screenshots).
    var demoInsertMenu = false
    /// Opens the login screen on "reset password" (used for screenshots).
    var demoResetPassword = false

    /// Whether the notes column beside a file is hidden.
    var fileNotesHidden = false

    /// A short confirmation shown in the footer ("Saved", "Undone"…), cleared on its own.
    var status: Status?
    /// When keep-awake mode was switched on; nil while it is off.
    var awakeSince: Date?

    struct Status: Equatable {
        var text: String
        var symbol: String
        var stamp = UUID()
    }

    var isAwake: Bool { awakeSince != nil }

    func flash(_ text: String, symbol: String) {
        let status = Status(text: text, symbol: symbol)
        withAnimation(Motion.snappy) { self.status = status }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.status?.stamp == status.stamp else { return }
            withAnimation(Motion.smooth) { self.status = nil }
        }
    }

    /// Keep-awake mode: the Mac and display stay on and the window shows only a calm screen.
    func setAwake(_ on: Bool) {
        guard on != isAwake else { return }
        if on {
            guard SleepGuard.shared.start() else {
                flash(L("Couldn't keep the Mac awake", "절전 방지를 켤 수 없어요"), symbol: "exclamationmark.triangle.fill")
                return
            }
            withAnimation(Motion.gentle) { awakeSince = Date() }
        } else {
            SleepGuard.shared.stop()
            withAnimation(Motion.smooth) { awakeSince = nil }
        }
    }

    func present(_ overlay: Overlay) {
        withAnimation(Motion.spring) { self.overlay = overlay }
    }

    func dismiss() {
        withAnimation(Motion.smooth) { overlay = nil }
    }

    func showSettings(_ tab: SettingsTab = .general) {
        settingsTab = tab
        present(.settings)
    }

    /// Opens the node an anchor lives in and, for an inserted object, scrolls to it and flashes it.
    func navigate(to anchor: Anchor, in space: SpaceModel) {
        withAnimation(Motion.spring) { space.open(anchor.nodeID) }
        guard let blockID = anchor.blockID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.scrollTarget = blockID
            withAnimation(Motion.smooth) { self.flashBlock = blockID }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.flashBlock == blockID else { return }
                withAnimation(Motion.gentle) { self.flashBlock = nil }
                self.scrollTarget = nil
            }
        }
    }
}
