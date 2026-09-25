import AppKit
import XCTest
@testable import mdmdmd

/// Clicking a line reveals its Markdown markers and hides the previous line's.
/// The line under the pointer must stay where it was on screen.
final class ScrollStabilityTests: XCTestCase {
    private var window: NSWindow!
    private var scroll: NSScrollView!
    private var textView: MarkdownTextView!

    override func setUp() {
        // A small window: long paragraphs wrap a lot, which is where it jumped.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        (scroll, textView) = EditorView.makeScrollView()
        scroll.frame = window.contentView!.bounds
        scroll.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(scroll)
        textView.frame = NSRect(origin: .zero, size: scroll.contentSize)
        textView.string = Self.document
        textView.restyle()
        spin()
    }

    override func tearDown() { window.close() }

    private static let document: String = (0..<60).map { i in
        """
        ## Section \(i) with a **heading**

        This paragraph is long enough to wrap several times in a narrow window, with **bold words**, some _italics_, a [link](https://example.com) and `inline code` so each line carries markers that collapse.

        ```
        code block \(i)
        ```
        """
    }.joined(separator: "\n\n")

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// Screen y of a character, relative to the visible top of the scroll view.
    private func onScreenY(_ location: Int) -> CGFloat {
        let rect = textView.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
        let inWindow = window.convertFromScreen(rect)
        return scroll.contentView.convert(inWindow, from: nil).minY - scroll.contentView.bounds.minY
    }

    private func click(_ location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.selectionChanged()
        spin()
    }

    func testClickedLineStaysPutWhenAParagraphAboveCollapses() {
        let ns = textView.string as NSString
        // Put the caret in the first section so its markers are revealed.
        click(ns.range(of: "bold words").location)

        // Scroll to the middle and click a word there.
        let target = ns.range(of: "bold words", options: [], range: NSRange(location: ns.length / 2, length: ns.length / 2)).location
        textView.scrollRangeToVisible(NSRange(location: target, length: 1))
        spin()
        let before = onScreenY(target)

        click(target)
        XCTAssertEqual(onScreenY(target), before, accuracy: 1, "clicked word moved on screen")

        // Click again a few sections further down, both directions.
        let next = ns.range(of: "bold words", options: [], range: NSRange(location: target + 400, length: ns.length - target - 400)).location
        textView.scrollRangeToVisible(NSRange(location: next, length: 1))
        spin()
        let beforeNext = onScreenY(next)
        click(next)
        XCTAssertEqual(onScreenY(next), beforeNext, accuracy: 1, "second click moved the word")

        let back = ns.range(of: "bold words", options: .backwards, range: NSRange(location: 0, length: next - 10)).location
        let beforeBack = onScreenY(back)
        click(back)
        XCTAssertEqual(onScreenY(back), beforeBack, accuracy: 1, "clicking upward moved the word")
    }
}
