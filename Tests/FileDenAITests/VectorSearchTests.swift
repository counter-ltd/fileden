import XCTest
@testable import FileDenAI

final class VectorSearchTests: XCTestCase {
    func testTopKMatchesCosineOrder() {
        let dim = 2
        // Rows: e0=[1,0], e1=[0,1], e2≈[0.707,0.707]
        let matrix: [Float] = [1, 0, 0, 1, 0.7071068, 0.7071068]
        let query: [Float] = [1, 0]
        let top = VectorSearch.topK(query: query, matrix: matrix, count: 3, dim: dim, k: 2)
        XCTAssertEqual(top.map(\.index), [0, 2])
        XCTAssertEqual(top[0].score, 1.0, accuracy: 1e-5)
        XCTAssertEqual(top[1].score, 0.7071068, accuracy: 1e-4)
    }

    func testSelectTopKDescendingAndBounded() {
        let scores: [Float] = [0.1, 0.9, 0.5, 0.95, 0.2]
        let top = VectorSearch.selectTopK(scores: scores, k: 3)
        XCTAssertEqual(top.map(\.index), [3, 1, 2])
        XCTAssertEqual(top.count, 3)
    }

    func testKLargerThanCountAndEmpty() {
        XCTAssertEqual(VectorSearch.topK(query: [1, 0], matrix: [1, 0], count: 1, dim: 2, k: 5).count, 1)
        XCTAssertTrue(VectorSearch.topK(query: [], matrix: [], count: 0, dim: 2, k: 3).isEmpty)
    }

    func testSGEMVMatchesNaiveReference() {
        let dim = 8
        let count = 50
        var rng = SystemRandomNumberGenerator()
        var matrix = [Float](); matrix.reserveCapacity(count * dim)
        for _ in 0..<(count * dim) { matrix.append(Float.random(in: -1...1, using: &rng)) }
        let query = (0..<dim).map { _ in Float.random(in: -1...1, using: &rng) }

        let top = VectorSearch.topK(query: query, matrix: matrix, count: count, dim: dim, k: count)
        // Reference dot products.
        var reference = [(Int, Float)]()
        for i in 0..<count {
            var s: Float = 0
            for d in 0..<dim { s += matrix[i * dim + d] * query[d] }
            reference.append((i, s))
        }
        reference.sort { $0.1 > $1.1 }
        XCTAssertEqual(top.map(\.index), reference.map(\.0))
        for (a, b) in zip(top, reference) { XCTAssertEqual(a.score, b.1, accuracy: 1e-3) }
    }

    func testNormalizationUnitLength() {
        let v = VectorMath.normalized([3, 4])   // length 5 → [0.6, 0.8]
        XCTAssertEqual(v[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(v[1], 0.8, accuracy: 1e-6)
        XCTAssertEqual(VectorMath.normalized([0, 0]), [0, 0])   // zero stays zero
    }
}
