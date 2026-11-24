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
    enum Overlay: Equatable { case settings, spaceSettings, addAccount }

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
