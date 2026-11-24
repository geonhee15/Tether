import AppKit
import SwiftUI

/// Character-level style of a run. This is the source of truth; fonts and colours are derived from it,
/// so text follows the app's typography settings unless a family or size was picked explicitly.
struct RunStyle: Equatable, Hashable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var color: String?
    var highlight: String?
    var family: String?
    var size: Double?
}

/// Carries a `RunStyle` inside attributed text.
final class StyleBox: NSObject {
    let style: RunStyle
    init(_ style: RunStyle) { self.style = style }
    override func isEqual(_ object: Any?) -> Bool { (object as? StyleBox)?.style == style }
    override var hash: Int { style.hashValue }
}

extension NSAttributedString.Key {
    static let tetherStyle = NSAttributedString.Key("TetherStyle")
}

enum TextPreset: String, CaseIterable, Identifiable {
    case title, heading, subheading, body
    var id: String { rawValue }

    var size: Double? {
        switch self {
        case .title: return 28
        case .heading: return 21
        case .subheading: return 17
        case .body: return nil
        }
    }

    var bold: Bool { self != .body }

    @MainActor var label: String {
        switch self {
        case .title: return L("Title", "제목")
        case .heading: return L("Heading", "머리글")
        case .subheading: return L("Subheading", "소제목")
        case .body: return L("Body", "본문")
        }
    }

    static func matching(_ style: RunStyle) -> TextPreset? {
        allCases.first { $0.size == style.size && $0.bold == style.bold }
    }
}

/// Colours offered in the toolbar (mid-tones that read on both light and dark pages;
/// highlights are translucent so the text stays legible).
enum TextPalette {
    static let text: [String] = ["E64040", "F28C26", "9E7333", "33A659", "4080F2", "9966E6", "E65999", "80858F"]
    static let highlight: [String] = ["FFE0408C", "73E68080", "73B8FF80", "FF8CB880", "FFAD598C", "BF99FF80"]
}

/// Converts between saved runs and attributed text.
@MainActor
enum TextCodec {
    static func paragraphStyle(alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spacing = AppSettings.shared.lineSpacing.points
        style.lineSpacing = spacing
        style.paragraphSpacing = spacing * 0.6 + 2
        style.alignment = alignment
        return style
    }

    static func font(for style: RunStyle) -> NSFont {
        let settings = AppSettings.shared
        let choice = style.family.flatMap(FontChoice.init(rawValue:)) ?? settings.editorFont
        return choice.nsFont(size: CGFloat(style.size ?? settings.editorFontSize), bold: style.bold)
    }

    static func attributes(_ style: RunStyle, alignment: NSTextAlignment = .natural) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .tetherStyle: StyleBox(style),
            .font: font(for: style),
            .foregroundColor: style.color.flatMap { NSColor(hex: $0) } ?? NSColor.labelColor,
            .paragraphStyle: paragraphStyle(alignment: alignment),
        ]
        if let highlight = style.highlight, let color = NSColor(hex: highlight) { attributes[.backgroundColor] = color }
        if style.italic { attributes[.obliqueness] = 0.18 }
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    static func style(from attributes: [NSAttributedString.Key: Any]) -> RunStyle {
        (attributes[.tetherStyle] as? StyleBox)?.style ?? RunStyle()
    }

    static func alignment(from attributes: [NSAttributedString.Key: Any]) -> NSTextAlignment {
        (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
    }

    static func decode(_ runs: [TextRun]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs where !run.t.isEmpty {
            let style = RunStyle(bold: run.b ?? false, italic: run.i ?? false, underline: run.u ?? false, strike: run.s ?? false,
                                 color: run.c, highlight: run.h, family: run.f, size: run.z)
            let alignment: NSTextAlignment = run.a == 1 ? .center : run.a == 2 ? .right : .natural
            result.append(NSAttributedString(string: run.t, attributes: attributes(style, alignment: alignment)))
        }
        return result
    }

    static func encode(_ text: NSAttributedString) -> [TextRun] {
        var runs: [TextRun] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let style = style(from: attributes)
            let alignment = alignment(from: attributes)
            var run = TextRun(t: (text.string as NSString).substring(with: range))
            if style.bold { run.b = true }
            if style.italic { run.i = true }
            if style.underline { run.u = true }
            if style.strike { run.s = true }
            run.c = style.color
            run.h = style.highlight
            run.f = style.family
            run.z = style.size
            if alignment == .center { run.a = 1 } else if alignment == .right { run.a = 2 }
            if let last = runs.last, last.sameStyle(as: run) {
                runs[runs.count - 1].t += run.t
            } else {
                runs.append(run)
            }
        }
        return runs
    }
}

/// What the toolbar shows for the caret / selection.
struct FormatState: Equatable {
    var style = RunStyle()
    var alignment = 0
    var hasEditor = false

    var preset: TextPreset? { TextPreset.matching(style) }
}

// MARK: Text view

/// A self-sizing, non-scrolling rich text view. One per text block; several of them plus the
/// inserted objects between them read as a single continuous page.
final class TetherTextView: NSTextView {
    var blockID: UUID?
    weak var controller: EditorController?
    var placeholder: String? { didSet { if placeholder != oldValue { needsDisplay = true } } }
    var onLayoutChange: (() -> Void)?

    // MARK: Focus & selection

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { controller?.textViewDidFocus(self) }
        return ok
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { controller?.selectionChanged(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if abs(oldWidth - newSize.width) > 0.5 { onLayoutChange?() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { controller?.textViewDidAttach(self) }
    }

    func fittingHeight() -> CGFloat {
        guard let layoutManager, let textContainer else { return 24 }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        let line = layoutManager.defaultLineHeight(for: font)
        return ceil(max(used, line) + textContainerInset.height * 2)
    }

    // MARK: Style reading

    func currentAttributes() -> [NSAttributedString.Key: Any] {
        let range = selectedRange()
        if range.length > 0, let storage = textStorage, range.location < storage.length {
            return storage.attributes(at: range.location, effectiveRange: nil)
        }
        return typingAttributes
    }

    func currentStyle() -> RunStyle { TextCodec.style(from: currentAttributes()) }

    func currentAlignment() -> NSTextAlignment { TextCodec.alignment(from: currentAttributes()) }

    // MARK: Style editing

    /// Applies a change to every run in the range (default: the selection) and to what is typed next.
    func mutateStyle(in override: NSRange? = nil, _ change: (inout RunStyle) -> Void) {
        let range = override ?? selectedRange()
        if range.length > 0, let storage = textStorage, shouldChangeText(in: range, replacementString: nil) {
            storage.beginEditing()
            var pieces: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: range) { attributes, subrange, _ in
                var style = TextCodec.style(from: attributes)
                change(&style)
                pieces.append((subrange, TextCodec.attributes(style, alignment: TextCodec.alignment(from: attributes))))
            }
            for (subrange, attributes) in pieces { storage.setAttributes(attributes, range: subrange) }
            storage.endEditing()
            didChangeText()
        }
        var style = TextCodec.style(from: typingAttributes)
        change(&style)
        typingAttributes = TextCodec.attributes(style, alignment: TextCodec.alignment(from: typingAttributes))
        controller?.selectionChanged(self)
    }

    func toggle(_ keyPath: WritableKeyPath<RunStyle, Bool>) {
        let turnOn = !currentStyle()[keyPath: keyPath]
        mutateStyle { $0[keyPath: keyPath] = turnOn }
    }

    func applyPreset(_ preset: TextPreset) {
        let paragraphs = (string as NSString).paragraphRange(for: selectedRange())
        mutateStyle(in: paragraphs) { style in
            style.size = preset.size
            style.bold = preset.bold
        }
    }

    func applyAlignment(_ alignment: NSTextAlignment) {
        let range = (string as NSString).paragraphRange(for: selectedRange())
        let paragraph = TextCodec.paragraphStyle(alignment: alignment)
        if range.length > 0, let storage = textStorage, shouldChangeText(in: range, replacementString: nil) {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
            didChangeText()
        }
        typingAttributes[.paragraphStyle] = paragraph
        onLayoutChange?()
        controller?.selectionChanged(self)
    }

    func clearFormatting() {
        mutateStyle { $0 = RunStyle() }
    }

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command] {
            switch key {
            case "b": toggle(\.bold); return true
            case "i": toggle(\.italic); return true
            case "u": toggle(\.underline); return true
            default: break
            }
        }
        if flags == [.command, .shift] {
            switch key {
            case "x": toggle(\.strike); return true
            case "\\", "|": clearFormatting(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Pasted text takes on the surrounding style so the page stays consistent.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func moveUp(_ sender: Any?) {
        if selectedRange().length == 0, caretIsOnFirstLine, controller?.moveFocus(from: self, direction: -1) == true { return }
        super.moveUp(sender)
    }

    override func moveDown(_ sender: Any?) {
        if selectedRange().length == 0, caretIsOnLastLine, controller?.moveFocus(from: self, direction: 1) == true { return }
        super.moveDown(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        let range = selectedRange()
        if range.location == 0, range.length == 0, controller?.backspaceAtStart(of: self) == true { return }
        super.deleteBackward(sender)
    }

    private func lineOrigin(forCharacterAt index: Int) -> CGFloat? {
        guard let layoutManager, layoutManager.numberOfGlyphs > 0 else { return nil }
        let clamped = min(max(0, index), (string as NSString).length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    private var caretIsOnFirstLine: Bool {
        let length = (string as NSString).length
        let location = selectedRange().location
        if length == 0 { return true }
        if location == length, string.hasSuffix("\n") { return false }
        return lineOrigin(forCharacterAt: location) == lineOrigin(forCharacterAt: 0)
    }

    private var caretIsOnLastLine: Bool {
        let length = (string as NSString).length
        let location = selectedRange().location
        if length == 0 || location == length { return true }
        if string.hasSuffix("\n") { return false }
        return lineOrigin(forCharacterAt: location) == lineOrigin(forCharacterAt: length - 1)
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder, string.isEmpty else { return }
        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
    }
}

// MARK: Controller

/// Routes toolbar actions to whichever text block has the caret, and moves the caret between blocks.
@MainActor
@Observable
final class EditorController {
    private final class WeakTextView {
        weak var view: TetherTextView?
        init(_ view: TetherTextView) { self.view = view }
    }

    @ObservationIgnored weak var activeTextView: TetherTextView?
    @ObservationIgnored weak var node: NodeModel?
    @ObservationIgnored private var textViews: [UUID: WeakTextView] = [:]
    @ObservationIgnored private var pendingFocus: (id: UUID, atEnd: Bool)?

    var format = FormatState()
    /// The object most recently inserted (the page scrolls to it).
    var lastInserted: UUID?

    func register(_ view: TetherTextView, for id: UUID) {
        textViews[id] = WeakTextView(view)
    }

    /// A freshly created block can only take the caret once its view is in the window.
    func textViewDidAttach(_ view: TetherTextView) {
        guard let pending = pendingFocus, pending.id == view.blockID, view.window != nil else { return }
        pendingFocus = nil
        DispatchQueue.main.async { [weak self] in self?.focus(pending.id, atEnd: pending.atEnd) }
    }

    func unregister(_ view: TetherTextView, for id: UUID) {
        if textViews[id]?.view === view { textViews[id] = nil }
        if activeTextView === view {
            activeTextView = nil
            format = FormatState()
        }
    }

    func textViewDidFocus(_ view: TetherTextView) {
        activeTextView = view
        selectionChanged(view)
    }

    func selectionChanged(_ view: TetherTextView) {
        guard view === activeTextView else { return }
        let alignment = view.currentAlignment()
        let state = FormatState(style: view.currentStyle(), alignment: alignment == .center ? 1 : alignment == .right ? 2 : 0, hasEditor: true)
        if state != format { format = state }
    }

    /// Runs a toolbar action against the active text view and keeps the keyboard there.
    func perform(_ action: (TetherTextView) -> Void) {
        guard let view = activeTextView else { return }
        action(view)
        refocus()
    }

    func refocus() {
        guard let view = activeTextView, view.window?.firstResponder !== view else { return }
        view.window?.makeFirstResponder(view)
    }

    func focus(_ id: UUID, atEnd: Bool) {
        guard let view = textViews[id]?.view, view.window != nil else {
            pendingFocus = (id, atEnd)
            return
        }
        view.window?.makeFirstResponder(view)
        let location = atEnd ? (view.string as NSString).length : 0
        view.setSelectedRange(NSRange(location: location, length: 0))
        view.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    /// Focuses the last text block of the page (clicking the empty area under the content).
    func focusEnd(of node: NodeModel) {
        if let last = node.blocks.last(where: { $0.data.kind == .text }) { focus(last.id, atEnd: true) }
    }

    /// Arrow-key travel between text blocks, skipping over inserted objects.
    func moveFocus(from view: TetherTextView, direction: Int) -> Bool {
        guard let node, let id = view.blockID, var index = node.blocks.firstIndex(where: { $0.id == id }) else { return false }
        index += direction
        while node.blocks.indices.contains(index) {
            if node.blocks[index].data.kind == .text {
                focus(node.blocks[index].id, atEnd: direction < 0)
                return true
            }
            index += direction
        }
        return false
    }

    /// Backspace at the very start of a block joins it to a text block directly above.
    func backspaceAtStart(of view: TetherTextView) -> Bool {
        guard let node, let id = view.blockID, let index = node.blocks.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        let previous = node.blocks[index - 1]
        guard previous.data.kind == .text else { return false }
        let head = previous.data.runs ?? []
        let joinAt = head.reduce(0) { $0 + ($1.t as NSString).length }
        previous.data.runs = head + (node.blocks[index].data.runs ?? [])
        previous.revision += 1
        node.blocks.remove(at: index)
        DispatchQueue.main.async { [weak self] in
            guard let target = self?.textViews[previous.id]?.view else { return }
            target.window?.makeFirstResponder(target)
            target.setSelectedRange(NSRange(location: joinAt, length: 0))
        }
        return true
    }

    /// Inserts an object at the caret: the text block is split around it so the page keeps flowing.
    func insert(_ block: Block, into node: NodeModel) {
        let embed = BlockModel(block)
        if let view = activeTextView, let id = view.blockID, let index = node.blocks.firstIndex(where: { $0.id == id }) {
            let full = view.attributedString()
            let location = min(view.selectedRange().location, full.length)
            var before = full.attributedSubstring(from: NSRange(location: 0, length: location))
            var after = full.attributedSubstring(from: NSRange(location: location, length: full.length - location))
            // The object replaces the line break it was dropped on.
            if before.string.hasSuffix("\n") { before = before.attributedSubstring(from: NSRange(location: 0, length: before.length - 1)) }
            if after.string.hasPrefix("\n") { after = after.attributedSubstring(from: NSRange(location: 1, length: after.length - 1)) }
            let current = node.blocks[index]
            current.data.runs = TextCodec.encode(before)
            current.revision += 1
            let tail = BlockModel(Block(kind: .text, runs: TextCodec.encode(after)))
            pendingFocus = (tail.id, false)
            withAnimation(Motion.spring) {
                node.blocks.insert(contentsOf: [embed, tail], at: index + 1)
            }
        } else {
            let tail = BlockModel(Block(kind: .text))
            pendingFocus = (tail.id, false)
            withAnimation(Motion.spring) {
                node.blocks.append(contentsOf: [embed, tail])
            }
        }
        lastInserted = embed.id
    }
}

// MARK: SwiftUI bridge

struct TextBlockView: View {
    let block: BlockModel
    var placeholder: String?
    @Environment(EditorController.self) private var editor
    @State private var height: CGFloat = 24

    var body: some View {
        let settings = AppSettings.shared
        TextBlockRepresentable(block: block, editor: editor, placeholder: placeholder, revision: block.revision,
                               stamp: settings.typographyStamp, spellCheck: settings.spellCheck,
                               accent: NSColor(Theme.accent), height: $height)
            .frame(height: height)
    }
}

private struct TextBlockRepresentable: NSViewRepresentable {
    let block: BlockModel
    let editor: EditorController
    var placeholder: String?
    var revision: Int
    var stamp: String
    var spellCheck: Bool
    var accent: NSColor
    @Binding var height: CGFloat

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextBlockRepresentable
        var loadedRevision = -1
        var loadedStamp = ""
        weak var textView: TetherTextView?

        init(parent: TextBlockRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.block.data.runs = TextCodec.encode(textView.attributedString())
            textView.needsDisplay = true
            reportHeight()
        }

        func reportHeight() {
            guard let textView else { return }
            let fitting = textView.fittingHeight()
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.height - fitting) > 0.5 else { return }
                self.parent.height = fitting
            }
        }

        func load() {
            guard let textView else { return }
            loadedRevision = parent.revision
            loadedStamp = parent.stamp
            let selection = textView.selectedRange()
            let previous = textView.string as NSString
            let text = TextCodec.decode(parent.block.data.runs ?? [])
            textView.textStorage?.setAttributedString(text)
            let length = text.length
            // When the words themselves changed underneath (Undo / Redo), leave the caret at the end
            // of what changed; otherwise keep it where it was.
            var caret = min(selection.location, length)
            let current = text.string as NSString
            if previous.length > 0, !previous.isEqual(to: current as String) {
                let shared = min(previous.length, current.length)
                var prefix = 0
                while prefix < shared, previous.character(at: prefix) == current.character(at: prefix) { prefix += 1 }
                var suffix = 0
                while suffix < shared - prefix,
                      previous.character(at: previous.length - 1 - suffix) == current.character(at: current.length - 1 - suffix) { suffix += 1 }
                caret = max(prefix, current.length - suffix)
            }
            if length > 0 {
                textView.typingAttributes = text.attributes(at: caret > 0 ? caret - 1 : 0, effectiveRange: nil)
            } else {
                textView.typingAttributes = TextCodec.attributes(RunStyle())
            }
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            textView.needsDisplay = true
            reportHeight()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> TetherTextView {
        let textView = TetherTextView(usingTextLayoutManager: false)
        textView.blockID = block.id
        textView.controller = editor
        textView.delegate = context.coordinator
        textView.isRichText = true
        // Undo is kept for the whole Space (SpaceHistory), so typing, objects and links share one ⌘Z.
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = textView
        textView.onLayoutChange = { [weak coordinator = context.coordinator] in coordinator?.reportHeight() }
        apply(to: textView)
        context.coordinator.load()
        editor.register(textView, for: block.id)
        return textView
    }

    func updateNSView(_ textView: TetherTextView, context: Context) {
        context.coordinator.parent = self
        apply(to: textView)
        if context.coordinator.loadedRevision != revision || context.coordinator.loadedStamp != stamp {
            context.coordinator.load()
        }
    }

    private func apply(to textView: TetherTextView) {
        textView.placeholder = placeholder
        textView.insertionPointColor = accent
        if textView.isContinuousSpellCheckingEnabled != spellCheck { textView.isContinuousSpellCheckingEnabled = spellCheck }
        textView.isGrammarCheckingEnabled = false
    }

    static func dismantleNSView(_ textView: TetherTextView, coordinator: Coordinator) {
        if let id = textView.blockID { coordinator.parent.editor.unregister(textView, for: id) }
    }
}
