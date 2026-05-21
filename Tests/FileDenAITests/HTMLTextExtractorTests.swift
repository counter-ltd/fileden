import XCTest
@testable import FileDenAI

final class HTMLTextExtractorTests: XCTestCase {
    func testStripsTagsScriptsStylesAndDecodesEntities() {
        let html = """
        <html><head><style>p{color:red}</style></head>
        <body><h1>Title</h1><p>Hello &amp; welcome</p>
        <script>alert(1)</script><p>Line&#33;</p>
        <p>Caf&#xe9;</p></body></html>
        """
        let text = HTMLTextExtractor.strip(html)

        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("Hello & welcome"))
        XCTAssertTrue(text.contains("Line!"))
        XCTAssertTrue(text.contains("Café"))
        XCTAssertFalse(text.contains("color:red"), "style contents must be dropped")
        XCTAssertFalse(text.contains("alert"), "script contents must be dropped")
        XCTAssertFalse(text.contains("<"), "no raw tags should survive")
    }

    func testBlockElementsBecomeLineBreaks() {
        let text = HTMLTextExtractor.strip("<p>one</p><p>two</p>")
        XCTAssertTrue(text.contains("one"))
        XCTAssertTrue(text.contains("two"))
        XCTAssertTrue(text.contains("\n"), "block boundaries should produce newlines")
    }
}
