import AppKit
import SwiftUI

/// Plain-text NSTextView whose storage gets Markdown styling laid over it.
final class MarkdownTextView: NSTextView, NSTextStorageDelegate {
    var baseSize: CGFloat = 16 { didSet { restyle() } }
    var topMargin: CGFloat = 32 { didSet { updateInsets() } }
    var columnWidth: CGFloat = 760 { didSet { updateInsets() } }
    var theme: Theme = .system {
        didSet {
            backgroundColor = theme.backgroundColor
            insertionPointColor = theme.textColor
            restyle()
        }
    }
    var onChange: ((String) -> Void)?
    private var lastActiveParagraph = NSRange(location: NSNotFound, length: 0)
    private var isRestyling = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: 24, height: 32)
        textStorage?.delegate = self
        typingAttributes = Styler.baseAttributes(size: baseSize)
    }

    // Center the column, Typora style.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let side = max(24, (frame.width - columnWidth) / 2)
        let inset = NSSize(width: side, height: topMargin)
        if textContainerInset != inset { textContainerInset = inset }
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isRestyling else { return }
        // Attribute edits inside didProcessEditing are legal; character edits are not.
        DispatchQueue.main.async { [self] in
            restyle()
            onChange?(string)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        typingAttributes = Styler.baseAttributes(size: baseSize, theme: theme)
    }

    func selectionChanged() {
        let active = (string as NSString).paragraphRange(for: selectedRange())
        guard active != lastActiveParagraph else { return }
        restyle()
    }

    // ponytail: full reparse on every edit; scripts are a few KB. Go incremental past ~100 KB.
    func restyle() {
        guard let storage = textStorage else { return }
        isRestyling = true
        let active = (string as NSString).paragraphRange(for: selectedRange())
        lastActiveParagraph = active
        Styler.apply(to: storage, baseSize: baseSize, activeRange: active, theme: theme)
        typingAttributes = Styler.baseAttributes(size: baseSize, theme: theme)
        isRestyling = false
    }

    // Continue lists on Enter; an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let line = ns.lineRange(for: selectedRange())
        let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
        let regex = try! NSRegularExpression(pattern: "^(\\s*)(?:([-*+])|(\\d+)\\.)(\\s+(?:\\[[ x]\\]\\s+)?)(.*)$")
        guard let m = regex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)),
              NSMaxRange(selectedRange()) >= NSMaxRange(line) - (ns.substring(with: line).hasSuffix("\n") ? 1 : 0) else {
            return super.insertNewline(sender)
        }
        let c = content as NSString
        let indent = c.substring(with: m.range(at: 1))
        let body = c.substring(with: m.range(at: 5))
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: remove the marker and leave the list.
            insertText("", replacementRange: NSRange(location: line.location, length: c.length))
            return super.insertNewline(sender)
        }
        let bullet: String
        if m.range(at: 2).location != NSNotFound {
            bullet = c.substring(with: m.range(at: 2))
        } else {
            bullet = "\(Int(c.substring(with: m.range(at: 3)))! + 1)."
        }
        let spacing = c.substring(with: m.range(at: 4)).replacingOccurrences(of: "[x]", with: "[ ]")
        insertText("\n" + indent + bullet + spacing, replacementRange: selectedRange())
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

struct EditorView: NSViewRepresentable {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var prefs: Prefs

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: MarkdownTextView?
        func textViewDidChangeSelection(_ notification: Notification) { textView?.selectionChanged() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layout = NSTextLayoutManager()
        layout.textContainer = container
        let content = NSTextContentStorage()
        content.addTextLayoutManager(layout)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.delegate = context.coordinator
        textView.onChange = { [weak workspace] text in workspace?.editorChanged(text) }
        context.coordinator.textView = textView
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? MarkdownTextView else { return }
        let size = prefs.editorSize
        if textView.baseSize != size { textView.baseSize = size }
        let theme = prefs.theme
        if textView.theme != theme { textView.theme = theme }
        if textView.topMargin != prefs.topMargin { textView.topMargin = prefs.topMargin }
        if textView.columnWidth != prefs.columnWidth { textView.columnWidth = prefs.columnWidth }
        if textView.string != workspace.text {
            textView.string = workspace.text
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
            textView.restyle()
        }
    }
}
