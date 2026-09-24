import AppKit
import XCTest
@testable import mdmdmd

final class StylerTests: XCTestCase {
    private func styled(_ text: String, active: NSRange?) -> NSMutableAttributedString {
        let s = NSMutableAttributedString(string: text)
        Styler.apply(to: s, baseSize: 16, activeRange: active)
        return s
    }

    private func font(_ s: NSAttributedString, _ at: Int) -> NSFont {
        s.attribute(.font, at: at, effectiveRange: nil) as! NSFont
    }

    func testStrongMarkersCollapseAwayFromTheCaretAndShowOnIt() {
        let text = "plain\n\n**bold** text"
        let away = styled(text, active: NSRange(location: 0, length: 5))
        XCTAssertEqual(font(away, 7).pointSize, 0.1, "opening ** collapses")
        XCTAssertEqual(font(away, 13).pointSize, 0.1, "closing ** collapses")
        XCTAssertTrue(font(away, 9).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(font(away, 9).pointSize, 16)

        let on = styled(text, active: NSRange(location: 7, length: 0))
        XCTAssertEqual(font(on, 7).pointSize, 16, "markers on the caret's paragraph stay visible")
        XCTAssertEqual(on.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor, .tertiaryLabelColor)
    }

    func testUTF8ColumnsMapOntoUTF16Offsets() {
        // The emoji is 4 UTF-8 bytes but 2 UTF-16 units; the bold must still land on "b".
        let s = styled("😀 **b**", active: nil)
        XCTAssertTrue(font(s, 5).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(font(s, 3).pointSize, 0.1)
        XCTAssertEqual(font(s, 6).pointSize, 0.1)
    }

    func testHeadingAndFenceMarkersAreStripped() {
        let rendered = Styler.rendered("# Title\n\n```swift\nlet x = 1\n```\n\nsee `code`", baseSize: 16)
        XCTAssertEqual(rendered.string, "Title\n\nlet x = 1\n\n\nsee code")
        XCTAssertEqual(font(rendered, 0).pointSize, 32)
    }

    func testSpokenWordsIgnoreHeadingsCuesAndCode() {
        let script = """
        # ENG-1 Loom script

        Three minutes, screen on the PR.

        ## Walk the diff

        `Foo.kt`

        This file does two things and I say so.

        ```
        not spoken
        ```
        """
        XCTAssertEqual(Styler.spokenWords(script), 6 + 9)
    }
}
