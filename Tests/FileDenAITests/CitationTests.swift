import XCTest
@testable import FileDenAI

final class CitationTests: XCTestCase {
    private func citation(locator: ChunkLocator, text: String = "Some passage text.") -> Citation {
        let chunk = StoredChunk(id: 1, chunk: Chunk(
            sourceURL: URL(fileURLWithPath: "/tmp/doc.pdf"),
            ordinal: 0, text: text, locator: locator))
        return Citation(id: 1, chunk: chunk, score: 0.5)
    }

    func testPDFPageLabelIsOneBased() {
        XCTAssertEqual(citation(locator: .pdfPage(index: 11, charRange: nil)).locationLabel, "p. 12")
    }

    func testTextLineRangeLabels() {
        XCTAssertEqual(citation(locator: .textRange(charRange: 0..<10, lineRange: 40...48)).locationLabel, "lines 40–48")
        XCTAssertEqual(citation(locator: .textRange(charRange: 0..<10, lineRange: 5...5)).locationLabel, "line 5")
    }

    func testSnippetCollapsesWhitespaceAndTruncates() {
        let long = String(repeating: "word ", count: 100)
        let snippet = citation(locator: .pdfPage(index: 0, charRange: nil), text: "  a\n\n  b  ").snippet
        XCTAssertEqual(snippet, "a b")
        XCTAssertTrue(citation(locator: .pdfPage(index: 0, charRange: nil), text: long).snippet.hasSuffix("…"))
    }
}
