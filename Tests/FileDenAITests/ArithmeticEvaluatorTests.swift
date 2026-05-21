import XCTest
@testable import FileDenAI

final class ArithmeticEvaluatorTests: XCTestCase {
    func testSumOfQuarterlyRevenue() {
        // The exact case the LLM got wrong (it said 400,000).
        XCTAssertEqual(ArithmeticEvaluator.evaluate("42000 + 68000 + 97000 + 124000"), 331000)
    }

    func testTolereatesThousandsSeparators() {
        XCTAssertEqual(ArithmeticEvaluator.evaluate("42,000 + 68,000 + 97,000 + 124,000"), 331000)
    }

    func testPrecedenceAndParentheses() {
        XCTAssertEqual(ArithmeticEvaluator.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(ArithmeticEvaluator.evaluate("(2 + 3) * 4"), 20)
    }

    func testDivisionDecimalsAndUnary() {
        XCTAssertEqual(ArithmeticEvaluator.evaluate("10 / 4"), 2.5)
        XCTAssertEqual(ArithmeticEvaluator.evaluate("-5 + 3"), -2)
        XCTAssertEqual(ArithmeticEvaluator.evaluate("3 * (4 - 6)"), -6)
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(ArithmeticEvaluator.evaluate("2 +"))
        XCTAssertNil(ArithmeticEvaluator.evaluate("abc"))
        XCTAssertNil(ArithmeticEvaluator.evaluate("5 / 0"))
        XCTAssertNil(ArithmeticEvaluator.evaluate(""))
        XCTAssertNil(ArithmeticEvaluator.evaluate("1 2 3"))
    }
}
