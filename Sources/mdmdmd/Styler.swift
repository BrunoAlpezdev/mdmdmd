import AppKit
import Markdown

/// Turns Markdown source into attributes laid over the *source text itself*,
/// Typora style: the raw characters stay in the storage, syntax markers are
/// dimmed on the paragraph being edited and collapsed everywhere else.
enum Styler {
    struct Marker {
        let range: NSRange
        /// The node the marker belongs to. When the caret's paragraph touches
        /// the owner, the marker is shown dimmed instead of collapsed.
        let owner: NSRange
    }

    struct Span {
        let range: NSRange
        let apply: (NSMutableAttributedString, NSRange) -> Void
    }

    struct Result {
        var spans: [Span] = []
        var markers: [Marker] = []
        var listMarkers: [NSRange] = []
    }

    static let collapsedFont = NSFont.systemFont(ofSize: 0.1)

    /// Restyles `storage` in place. `activeRange` is the paragraph range holding
    /// the selection; nil means "editing nowhere", so every marker collapses.
    static func apply(to storage: NSMutableAttributedString, baseSize: CGFloat, activeRange: NSRange?) {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        let result = analyze(text, baseSize: baseSize)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(size: baseSize), range: full)
        for span in result.spans { span.apply(storage, span.range) }
        for range in result.listMarkers {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        for marker in result.markers {
            let revealed = activeRange.map { NSIntersectionRange($0, marker.owner).length > 0 || NSLocationInRange($0.location, marker.owner) } ?? false
            if revealed {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: marker.range)
            } else {
                storage.addAttributes([.font: collapsedFont, .foregroundColor: NSColor.clear], range: marker.range)
            }
        }
        storage.endEditing()
    }

    /// The document as a reader sees it: styled, with every syntax marker removed.
    static func rendered(_ text: String, baseSize: CGFloat) -> NSAttributedString {
        let storage = NSMutableAttributedString(string: text)
        apply(to: storage, baseSize: baseSize, activeRange: nil)
        let markers = analyze(text, baseSize: baseSize).markers.map(\.range).sorted { $0.location > $1.location }
        for range in markers { storage.deleteCharacters(in: range) }
        return storage
    }

    /// Words Bruno would say out loud: paragraph text, minus headings, code,
    /// tables and cue lines that are only a file name in backticks.
    static func spokenWords(_ text: String) -> Int {
        var counter = SpokenWordCounter()
        counter.visit(Document(parsing: text))
        return counter.count
    }

    static func baseAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size),
         .foregroundColor: NSColor.textColor,
         .paragraphStyle: paragraphStyle(size: size)]
    }

    static func paragraphStyle(size: CGFloat, headIndent: CGFloat = 0, firstLineIndent: CGFloat = 0, spacingBefore: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.3
        style.paragraphSpacing = size * 0.5
        style.paragraphSpacingBefore = spacingBefore
        style.headIndent = headIndent
        style.firstLineHeadIndent = firstLineIndent
        return style
    }

    static func analyze(_ text: String, baseSize: CGFloat) -> Result {
        var walker = StyleWalker(text: text, baseSize: baseSize)
        walker.visit(Document(parsing: text))
        return walker.result
    }
}

/// Maps swift-markdown's (line, UTF-8 column) locations onto UTF-16 NSRanges.
struct LineMap {
    private let text: String
    private let lineStarts: [Int]  // UTF-8 byte offset of each line start

    init(_ text: String) {
        self.text = text
        var starts = [0]
        for (i, byte) in text.utf8.enumerated() where byte == UInt8(ascii: "\n") { starts.append(i + 1) }
        lineStarts = starts
    }

    func utf16Offset(_ loc: SourceLocation) -> Int {
        guard loc.line >= 1, loc.line <= lineStarts.count else { return text.utf16.count }
        let byteOffset = min(lineStarts[loc.line - 1] + loc.column - 1, text.utf8.count)
        return text.utf8.index(text.utf8.startIndex, offsetBy: byteOffset).utf16Offset(in: text)
    }

    func nsRange(_ range: SourceRange) -> NSRange {
        let start = utf16Offset(range.lowerBound)
        let end = max(start, utf16Offset(range.upperBound))
        return NSRange(location: start, length: end - start)
    }
}

private struct StyleWalker: MarkupWalker {
    let text: String
    let ns: NSString
    let baseSize: CGFloat
    let map: LineMap
    var result = Styler.Result()
    var listDepth = 0

    init(text: String, baseSize: CGFloat) {
        self.text = text
        self.ns = text as NSString
        self.baseSize = baseSize
        self.map = LineMap(text)
    }

    // MARK: helpers

    func range(_ node: Markup) -> NSRange? { node.range.map(map.nsRange) }

    mutating func span(_ range: NSRange, _ apply: @escaping (NSMutableAttributedString, NSRange) -> Void) {
        result.spans.append(.init(range: range, apply: apply))
    }

    mutating func marker(_ range: NSRange, owner: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return }
        result.markers.append(.init(range: range, owner: owner))
    }

    /// Symmetric delimiters like `**`, `_`, `~~`, `` ` ``.
    mutating func wrap(_ node: Markup, width: Int) {
        guard let r = range(node), r.length >= width * 2 else { return }
        marker(NSRange(location: r.location, length: width), owner: r)
        marker(NSRange(location: NSMaxRange(r) - width, length: width), owner: r)
    }

    static func modifyFont(_ s: NSMutableAttributedString, _ r: NSRange, _ change: (NSFont) -> NSFont) {
        s.enumerateAttribute(.font, in: r) { value, sub, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            s.addAttribute(.font, value: change(font), range: sub)
        }
    }

    static func withTrait(_ font: NSFont, _ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    static func mono(_ font: NSFont) -> NSFont {
        let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
        return NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: bold ? .semibold : .regular)
    }

    // MARK: blocks

    mutating func visitHeading(_ heading: Heading) {
        if let r = range(heading) {
            let scale: CGFloat = [2.0, 1.55, 1.3, 1.15, 1.05, 1.0][min(heading.level, 6) - 1]
            let size = baseSize * scale
            span(r) { s, r in
                Self.modifyFont(s, r) { Self.withTrait(NSFont(descriptor: $0.fontDescriptor, size: size) ?? $0, .bold) }
                s.addAttribute(.paragraphStyle, value: Styler.paragraphStyle(size: size, spacingBefore: size * 0.6), range: r)
            }
            // ATX heading: "## " at the start. Setext headings have no leading marker.
            let prefix = heading.level + 1
            if r.length > prefix, ns.character(at: r.location) == UInt16(UInt8(ascii: "#")) {
                marker(NSRange(location: r.location, length: prefix), owner: r)
            }
        }
        descendInto(heading)
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) {
        if let r = range(quote) {
            span(r) { s, r in
                s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                Self.modifyFont(s, r) { Self.withTrait($0, .italic) }
                s.enumerateAttribute(.paragraphStyle, in: r) { value, sub, _ in
                    let style = ((value as? NSParagraphStyle) ?? NSParagraphStyle.default).mutableCopy() as! NSMutableParagraphStyle
                    style.headIndent += 18
                    style.firstLineHeadIndent += 18
                    s.addAttribute(.paragraphStyle, value: style, range: sub)
                }
            }
            // Every line's leading "> " is a marker.
            let regex = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]?", options: .anchorsMatchLines)
            for match in regex.matches(in: text, range: r) { marker(match.range, owner: r) }
        }
        descendInto(quote)
    }

    mutating func visitCodeBlock(_ block: CodeBlock) {
        guard let r = range(block) else { return }
        let size = baseSize
        span(r) { s, r in
            Self.modifyFont(s, r, Self.mono)
            s.addAttribute(.backgroundColor, value: NSColor.quaternarySystemFill, range: r)
            s.addAttribute(.paragraphStyle, value: Styler.paragraphStyle(size: size, headIndent: 12, firstLineIndent: 12), range: r)
        }
        // Fenced blocks: the opening and closing fence lines collapse.
        let firstLine = ns.lineRange(for: NSRange(location: r.location, length: 0))
        let source = ns.substring(with: firstLine)
        if source.hasPrefix("```") || source.hasPrefix("~~~") {
            marker(NSRange(location: firstLine.location, length: min(firstLine.length, NSMaxRange(r) - firstLine.location)), owner: r)
            let lastLine = ns.lineRange(for: NSRange(location: max(r.location, NSMaxRange(r) - 1), length: 0))
            if lastLine.location > firstLine.location {
                marker(NSRange(location: lastLine.location, length: NSMaxRange(r) - lastLine.location), owner: r)
            }
        }
    }

    mutating func visitListItem(_ item: ListItem) {
        listDepth += 1
        if let r = range(item) {
            let depth = CGFloat(listDepth)
            let size = baseSize
            span(r) { s, r in
                s.addAttribute(.paragraphStyle, value: Styler.paragraphStyle(size: size, headIndent: 22 * depth, firstLineIndent: 22 * (depth - 1)), range: r)
            }
            if let first = item.children.first(where: { $0.range != nil }), let fr = range(first), fr.location > r.location {
                result.listMarkers.append(NSRange(location: r.location, length: fr.location - r.location))
            }
        }
        descendInto(item)
        listDepth -= 1
    }

    mutating func visitTable(_ table: Table) {
        if let r = range(table) {
            span(r) { s, r in Self.modifyFont(s, r, Self.mono) }
        }
        descendInto(table)
    }

    mutating func visitTableHead(_ head: Table.Head) {
        if let r = range(head) {
            span(r) { s, r in Self.modifyFont(s, r) { Self.withTrait($0, .bold) } }
        }
        descendInto(head)
    }

    mutating func visitThematicBreak(_ rule: ThematicBreak) {
        if let r = range(rule) {
            span(r) { s, r in s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r) }
        }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let r = range(html) {
            span(r) { s, r in
                Self.modifyFont(s, r, Self.mono)
                s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
            }
        }
    }

    // MARK: inlines

    mutating func visitStrong(_ strong: Strong) {
        if let r = range(strong) { span(r) { s, r in Self.modifyFont(s, r) { Self.withTrait($0, .bold) } } }
        wrap(strong, width: 2)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let r = range(emphasis) { span(r) { s, r in Self.modifyFont(s, r) { Self.withTrait($0, .italic) } } }
        wrap(emphasis, width: 1)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strike: Strikethrough) {
        if let r = range(strike) {
            span(r) { s, r in s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
        }
        wrap(strike, width: 2)
        descendInto(strike)
    }

    mutating func visitInlineCode(_ code: InlineCode) {
        guard let r = range(code) else { return }
        span(r) { s, r in
            Self.modifyFont(s, r, Self.mono)
            s.addAttribute(.backgroundColor, value: NSColor.quaternarySystemFill, range: r)
        }
        var ticks = 0
        while ticks < r.length, ns.character(at: r.location + ticks) == UInt16(UInt8(ascii: "`")) { ticks += 1 }
        wrap(code, width: ticks)
    }

    mutating func visitLink(_ link: Link) {
        if let r = range(link), r.length > 0, ns.character(at: r.location) == UInt16(UInt8(ascii: "[")) {
            let inner = link.children.compactMap(range)
            if let first = inner.first, let last = inner.last {
                marker(NSRange(location: r.location, length: first.location - r.location), owner: r)
                marker(NSRange(location: NSMaxRange(last), length: NSMaxRange(r) - NSMaxRange(last)), owner: r)
                let textRange = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
                let destination = link.destination.flatMap(URL.init(string:))
                span(textRange) { s, r in
                    s.addAttribute(.foregroundColor, value: NSColor.linkColor, range: r)
                    s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                    if let destination { s.addAttribute(.link, value: destination, range: r) }
                }
            }
        }
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        if let r = range(image) {
            span(r) { s, r in s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r) }
        }
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        if let r = range(html) {
            span(r) { s, r in
                Self.modifyFont(s, r, Self.mono)
                s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
            }
        }
    }
}

private struct SpokenWordCounter: MarkupWalker {
    var count = 0

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // A paragraph that is only code (a file-name cue) or only a link is not spoken.
        let spoken = paragraph.children.contains { $0 is Text || $0 is Strong || $0 is Emphasis }
        guard spoken else { return }
        var text = ""
        for child in paragraph.children {
            if child is InlineCode { continue }
            text += " " + ((child as? PlainTextConvertibleMarkup)?.plainText ?? "")
        }
        count += text.split(whereSeparator: { $0.isWhitespace }).count
    }

    mutating func visitHeading(_ heading: Heading) {}
    mutating func visitCodeBlock(_ block: CodeBlock) {}
    mutating func visitTable(_ table: Table) {}
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
}
