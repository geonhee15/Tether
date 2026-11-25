import Foundation
import SwiftUI

/// The part of a Space that Undo covers: its settings, nodes, categories and links.
/// Which tabs are open is navigation, not content, so it is left out.
struct SpaceContent: Equatable {
    var info: SpaceInfo
    var nodes: [NodeDoc]
    var links: [RefLink]
    var categories: [NodeCategory]

    @MainActor
    init(_ space: SpaceModel) {
        info = space.info
        // Finishing first-run setup is not something to undo back out of.
        info.isConfigured = true
        // "Last edited" moves on its own after every save; ignore it when comparing states.
        nodes = space.nodes.map { node in
            var doc = node.snapshot
            doc.updatedAt = .distantPast
            return doc
        }
        links = space.links
        categories = space.categories
    }

    /// The node where two states differ, if the difference is inside a node that exists in `other`.
    func firstChangedNode(comparedTo other: SpaceContent) -> UUID? {
        let mine = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for doc in other.nodes where mine[doc.id] != doc { return doc.id }
        return nil
    }
}

/// Undo / redo for one Space, kept as whole-content snapshots.
///
/// Every edit — typing, formatting, inserting or deleting an object, changing a table cell,
/// ticking an action, adding a link, deleting a node — changes the observed model, so one
/// mechanism covers them all. Changes that arrive in a quick run (typing a phrase, dragging a
/// slider) are folded into a single step.
@MainActor
final class SpaceHistory {
    private var committed: SpaceContent
    private var undoStack: [SpaceContent] = []
    private var redoStack: [SpaceContent] = []
    private var timer: Timer?
    private var burstStart: Date?

    /// A pause this long ends a step.
    private let quiet: TimeInterval = 0.45
    /// Uninterrupted editing is still cut into steps this long.
    private let longestBurst: TimeInterval = 1.6
    private let limit = 200

    init(_ space: SpaceModel) {
        committed = SpaceContent(space)
    }

    var canUndo: Bool { !undoStack.isEmpty || burstStart != nil }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Forgets everything and treats the Space as it is now as the starting point.
    func reset(_ space: SpaceModel) {
        timer?.invalidate()
        burstStart = nil
        undoStack.removeAll()
        redoStack.removeAll()
        committed = SpaceContent(space)
    }

    /// Called whenever anything in the Space changed.
    func noteChange(in space: SpaceModel) {
        let now = Date()
        if burstStart == nil { burstStart = now }
        timer?.invalidate()
        if let start = burstStart, now.timeIntervalSince(start) >= longestBurst {
            commit(space)
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: quiet, repeats: false) { [weak self, weak space] _ in
            DispatchQueue.main.async {
                guard let self, let space else { return }
                self.commit(space)
            }
        }
    }

    /// Closes the current step, if the content really changed.
    func commit(_ space: SpaceModel) {
        timer?.invalidate()
        timer = nil
        burstStart = nil
        let current = SpaceContent(space)
        guard current != committed else { return }
        undoStack.append(committed)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        committed = current
    }

    /// Steps back once. Returns false when there is nothing to undo.
    func undo(_ space: SpaceModel) -> Bool {
        commit(space)
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(committed)
        restore(previous, in: space)
        return true
    }

    func redo(_ space: SpaceModel) -> Bool {
        commit(space)
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(committed)
        restore(next, in: space)
        return true
    }

    private func restore(_ content: SpaceContent, in space: SpaceModel) {
        let changedNode = committed.firstChangedNode(comparedTo: content)
        committed = content
        withAnimation(Motion.spring) {
            space.apply(content)
            // Show the place where something just changed back.
            if let changedNode, space.activeTab != changedNode { space.open(changedNode) }
        }
    }
}
