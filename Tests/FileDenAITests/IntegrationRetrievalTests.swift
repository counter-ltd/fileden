import XCTest
@testable import FileDenAI

/// End-to-end check with REAL on-device embeddings (the local sentence model, so
/// no network): chunk → embed → store → hybrid retrieve. Proves the pipeline
/// actually returns the on-topic passage — the thing competitors get wrong.
/// Skips if the embedding model isn't available on the host.
final class IntegrationRetrievalTests: XCTestCase {
    func testHybridRetrievalSurfacesOnTopicPassage() throws {
        guard let provider = SentenceEmbeddingProvider(language: .english) else {
            throw XCTSkip("Sentence embedding model unavailable on this host")
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileDenAI-int-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SQLiteIndexStore(url: dir.appendingPathComponent("index.sqlite"))

        let url = URL(fileURLWithPath: "/tmp/mixed.txt")
        let text = """
        Photosynthesis is the process by which green plants convert sunlight, water, and carbon dioxide into glucose and oxygen, storing the energy of light in chemical bonds.
        The French Revolution began in 1789 and led to the end of the monarchy and the rise of radical political factions across France.
        A binary search algorithm repeatedly halves a sorted array, achieving logarithmic time complexity when looking up an element.
        """
        // Small chunks so each sentence is its own retrievable unit.
        let chunks = Chunker.chunk(
            [ExtractedSegment(text: text, origin: .wholeText)],
            sourceURL: url,
            config: Chunker.Config(targetChars: 120, maxChars: 220, overlapChars: 0))
        XCTAssertGreaterThanOrEqual(chunks.count, 3, "each sentence should be a chunk")

        let vectors = provider.embed(chunks.map(\.text))
        try store.replaceFile(path: url.path, mtime: 1, size: 1,
                              provider: provider.identifier, dim: provider.dimension,
                              chunks: chunks, vectors: vectors)
        let corpus = store.loadCorpus(urls: [url], dim: provider.dimension)
        XCTAssertEqual(corpus.chunks.count, chunks.count)

        let question = "how do plants turn sunlight into energy?"
        let queryVector = provider.embed([question]).first ?? []
        let results = HybridRetriever.retrieve(
            query: question, queryVector: queryVector,
            corpus: corpus, store: store, k: 3)

        XCTAssertFalse(results.isEmpty, "retrieval should return passages")
        XCTAssertTrue(results.first!.chunk.text.lowercased().contains("photosynthesis"),
                      "the on-topic passage should rank first, got: \(results.first!.chunk.text)")
    }
}
