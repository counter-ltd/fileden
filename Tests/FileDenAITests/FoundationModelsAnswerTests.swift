import XCTest
@testable import FileDenAI

/// Exercises the real on-device LLM (Apple Foundation Models). Skips unless the
/// host is macOS 26+ with Apple Intelligence available. Verifies the synthesized
/// answer is grounded in the supplied passages.
final class FoundationModelsAnswerTests: XCTestCase {
    func testSynthesizesGroundedCitedAnswer() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires macOS 26+") }
        guard FoundationModelsAnswerProvider.isAvailable else {
            throw XCTSkip("On-device model unavailable: \(FoundationModelsAnswerProvider.unavailabilityReason ?? "unknown")")
        }

        let url = URL(fileURLWithPath: "/tmp/policy.txt")
        func cite(_ id: Int64, _ text: String, page: Int) -> Citation {
            Citation(id: id,
                     chunk: StoredChunk(id: id, chunk: Chunk(
                        sourceURL: url, ordinal: Int(id), text: text,
                        locator: .pdfPage(index: page, charRange: nil))),
                     score: 1)
        }
        let citations = [
            cite(1, "The return policy allows refunds within 30 days of purchase with a valid receipt.", page: 0),
            cite(2, "Shipping is free for orders over fifty dollars.", page: 1),
        ]

        let answer = try await FoundationModelsAnswerProvider.answer(
            question: "How long do I have to return an item?", citations: citations)

        XCTAssertFalse(answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "the model should produce an answer")
        let lower = answer.text.lowercased()
        XCTAssertTrue(lower.contains("30") || lower.contains("thirty"),
                      "answer should be grounded in the 30-day passage, got: \(answer.text)")
    }

    /// Regression for the wrong-total bug: the model must compute exact arithmetic
    /// via the calculator tool (42k+68k+97k+124k = 331k, not 400k).
    func testTotalUsesExactArithmetic() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires macOS 26+") }
        guard FoundationModelsAnswerProvider.isAvailable else {
            throw XCTSkip("On-device model unavailable")
        }
        let url = URL(fileURLWithPath: "/tmp/finance.pdf")
        let table = """
        Quarterly results:
        Q1 revenue $42,000
        Q2 revenue $68,000
        Q3 revenue $97,000
        Q4 revenue $124,000
        """
        let citation = Citation(
            id: 1,
            chunk: StoredChunk(id: 1, chunk: Chunk(
                sourceURL: url, ordinal: 0, text: table,
                locator: .pdfPage(index: 0, charRange: nil))),
            score: 1)

        let answer = try await FoundationModelsAnswerProvider.answer(
            question: "What is the total revenue across all four quarters?", citations: [citation])

        XCTAssertTrue(answer.text.contains("331"),
                      "total should be 331,000 (computed via the tool), got: \(answer.text)")
    }
}
