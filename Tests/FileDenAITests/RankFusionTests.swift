import XCTest
@testable import FileDenAI

final class RankFusionTests: XCTestCase {
    func testRRFFusesAndOrdersDeterministically() {
        let semantic: [Int64] = [10, 20, 30]
        let lexical: [Int64] = [20, 40, 50]
        let fused = RankFusion.rrf([semantic, lexical], k: 60, limit: 5)

        // 20 appears high in both → clear winner. Ties (30, 50 each appear once
        // at rank 3) break by smaller id first.
        XCTAssertEqual(fused.map(\.id), [20, 10, 40, 30, 50])
        XCTAssertEqual(fused.first?.id, 20)
        XCTAssertGreaterThan(fused[0].score, fused[1].score)
    }

    func testSingleListPassesThrough() {
        let fused = RankFusion.rrf([[7, 8, 9]], limit: 2)
        XCTAssertEqual(fused.map(\.id), [7, 8])
    }

    func testLimitRespected() {
        let fused = RankFusion.rrf([[1, 2, 3, 4, 5]], limit: 3)
        XCTAssertEqual(fused.count, 3)
    }
}
