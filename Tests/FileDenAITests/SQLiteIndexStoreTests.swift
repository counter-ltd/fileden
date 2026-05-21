import XCTest
@testable import FileDenAI

final class SQLiteIndexStoreTests: XCTestCase {
    private func makeStore() throws -> (SQLiteIndexStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileDenAITests-\(UUID().uuidString)", isDirectory: true)
        let dbURL = dir.appendingPathComponent("index.sqlite")
        return (try SQLiteIndexStore(url: dbURL), dir)
    }

    func testRoundTripChunksVectorsAndFingerprint() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = URL(fileURLWithPath: "/tmp/contract.txt")
        let chunks = [
            Chunk(sourceURL: fileURL, ordinal: 0,
                  text: "The termination clause requires thirty days notice.",
                  locator: .textRange(charRange: 0..<51, lineRange: 1...1)),
            Chunk(sourceURL: fileURL, ordinal: 1,
                  text: "Payment is due within fourteen days of invoice.",
                  locator: .textRange(charRange: 52..<99, lineRange: 2...2)),
        ]
        let vectors: [[Float]] = [[1, 0, 0, 0], [0, 1, 0, 0]]

        try store.replaceFile(path: fileURL.path, mtime: 123.0, size: 999,
                              provider: "test.d4", dim: 4, chunks: chunks, vectors: vectors)

        // Fingerprint persisted.
        XCTAssertEqual(store.fingerprint(path: fileURL.path),
                       SQLiteIndexStore.Fingerprint(mtime: 123.0, size: 999, provider: "test.d4"))

        // Corpus loads chunks + a packed matrix.
        let corpus = store.loadCorpus(urls: [fileURL], dim: 4)
        XCTAssertEqual(corpus.chunks.count, 2)
        XCTAssertEqual(corpus.matrix.count, 8)
        XCTAssertEqual(corpus.dim, 4)
        XCTAssertEqual(corpus.chunks[0].text, "The termination clause requires thirty days notice.")
        XCTAssertEqual(Array(corpus.matrix.prefix(4)), [1, 0, 0, 0])

        // Locators survive the round trip.
        if case let .textRange(range, lines) = corpus.chunks[1].locator {
            XCTAssertEqual(range, 52..<99)
            XCTAssertEqual(lines, 2...2)
        } else {
            XCTFail("expected a textRange locator")
        }
    }

    func testFTS5LexicalSearchFindsExactTerm() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = URL(fileURLWithPath: "/tmp/spec.txt")
        let chunks = [
            Chunk(sourceURL: fileURL, ordinal: 0, text: "The widget uses protocol XYZ-9000 for handshakes.",
                  locator: .textRange(charRange: 0..<10, lineRange: 1...1)),
            Chunk(sourceURL: fileURL, ordinal: 1, text: "Unrelated paragraph about lunch options.",
                  locator: .textRange(charRange: 11..<20, lineRange: 2...2)),
        ]
        try store.replaceFile(path: fileURL.path, mtime: 1, size: 1,
                              provider: "test.d2", dim: 2,
                              chunks: chunks, vectors: [[1, 0], [0, 1]])

        let corpus = store.loadCorpus(urls: [fileURL], dim: 2)
        // The exact identifier "XYZ-9000" tokenizes to "xyz" + "9000" — the kind
        // of rare term semantic vectors smear over but lexical search nails.
        let hits = store.ftsSearch("protocol XYZ 9000", limit: 10).filter { corpus.validIDs.contains($0) }
        XCTAssertEqual(hits.first, corpus.chunks[0].id, "lexical search should surface the exact-term chunk first")
    }

    func testReindexReplacesOldRows() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = URL(fileURLWithPath: "/tmp/changing.txt")

        try store.replaceFile(path: fileURL.path, mtime: 1, size: 1, provider: "p.d2", dim: 2,
                              chunks: [Chunk(sourceURL: fileURL, ordinal: 0, text: "old text here",
                                             locator: .textRange(charRange: 0..<5, lineRange: 1...1))],
                              vectors: [[1, 0]])
        try store.replaceFile(path: fileURL.path, mtime: 2, size: 2, provider: "p.d2", dim: 2,
                              chunks: [Chunk(sourceURL: fileURL, ordinal: 0, text: "brand new text",
                                             locator: .textRange(charRange: 0..<5, lineRange: 1...1))],
                              vectors: [[0, 1]])

        let corpus = store.loadCorpus(urls: [fileURL], dim: 2)
        XCTAssertEqual(corpus.chunks.count, 1)
        XCTAssertEqual(corpus.chunks[0].text, "brand new text")
        XCTAssertTrue(store.ftsSearch("old", limit: 10).isEmpty, "stale FTS rows must be cleared on reindex")
    }
}
