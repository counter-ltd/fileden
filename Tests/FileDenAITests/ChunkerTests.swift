import XCTest
@testable import FileDenAI

final class ChunkerTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/sample.txt")

    func testSentenceSizedChunksCoverSourceInOrder() {
        let text = "Alpha beta gamma. Delta epsilon zeta. Eta theta iota. Kappa lambda mu."
        let segments = [ExtractedSegment(text: text, origin: .wholeText)]
        let config = Chunker.Config(targetChars: 20, maxChars: 30, overlapChars: 8)
        let chunks = Chunker.chunk(segments, sourceURL: url, config: config)

        XCTAssertEqual(chunks.count, 4, "Each ~18-char sentence should be its own chunk")
        XCTAssertEqual(chunks.map(\.ordinal), [0, 1, 2, 3])

        let ns = text as NSString
        for chunk in chunks {
            guard case let .textRange(range, lines) = chunk.locator else {
                return XCTFail("whole-text chunks must carry a textRange locator")
            }
            XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
            XCTAssertLessThanOrEqual(range.upperBound, ns.length)
            XCTAssertEqual(chunk.text, ns.substring(with: NSRange(location: range.lowerBound, length: range.count)))
            XCTAssertNotNil(lines)
        }
        // First chunk starts at the top; chunks advance through the document.
        if case let .textRange(first, _) = chunks.first!.locator {
            XCTAssertEqual(first.lowerBound, 0)
        }
        XCTAssertTrue(chunks.contains { $0.text.contains("Kappa") })
    }

    func testOverlapIsProducedForDenseText() {
        // Short sentences with a small target but generous overlap → consecutive
        // chunks should share trailing context.
        let text = (1...12).map { "S\($0) word here." }.joined(separator: " ")
        let config = Chunker.Config(targetChars: 40, maxChars: 60, overlapChars: 20)
        let chunks = Chunker.chunk([ExtractedSegment(text: text, origin: .wholeText)],
                                   sourceURL: url, config: config)
        XCTAssertGreaterThan(chunks.count, 1)

        func bounds(_ c: Chunk) -> Range<Int> {
            if case let .textRange(r, _) = c.locator { return r }
            return 0..<0
        }
        // At least one adjacent pair overlaps (next starts before previous ends).
        let overlapping = zip(chunks, chunks.dropFirst()).contains { a, b in
            bounds(b).lowerBound < bounds(a).upperBound
        }
        XCTAssertTrue(overlapping, "expected sliding-window overlap between chunks")
    }

    func testLongUnbrokenTextIsHardSplitWithinMax() {
        let text = String(repeating: "x", count: 100)   // no sentence breaks
        let config = Chunker.Config(targetChars: 25, maxChars: 30, overlapChars: 5)
        let chunks = Chunker.chunk([ExtractedSegment(text: text, origin: .wholeText)],
                                   sourceURL: url, config: config)
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            XCTAssertLessThanOrEqual((chunk.text as NSString).length, config.maxChars)
        }
        // The whole document is represented.
        XCTAssertTrue(chunks.contains { !$0.text.isEmpty })
    }

    func testPDFOriginYieldsPageLocator() {
        let chunks = Chunker.chunk([ExtractedSegment(text: "Hello world. Goodbye.", origin: .pdfPage(index: 4))],
                                   sourceURL: url)
        XCTAssertFalse(chunks.isEmpty)
        for chunk in chunks {
            guard case let .pdfPage(index, range) = chunk.locator else {
                return XCTFail("pdf chunks must carry a pdfPage locator")
            }
            XCTAssertEqual(index, 4)
            XCTAssertNotNil(range)
        }
    }
}
