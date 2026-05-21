import Foundation

/// Combines semantic (vector) and lexical (FTS5/BM25) retrieval over a corpus and
/// fuses them with RRF. This hybrid is the accuracy lever: embeddings catch
/// paraphrase and meaning, BM25 catches exact names / identifiers / rare terms
/// that vectors smear over.
public enum HybridRetriever {
    public static func retrieve(query: String,
                                queryVector: [Float],
                                corpus: Corpus,
                                store: SQLiteIndexStore,
                                k: Int = 8,
                                candidatePool: Int = 40) -> [Citation] {
        guard !corpus.isEmpty else { return [] }
        let byID = Dictionary(corpus.chunks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Semantic candidates.
        let semantic = VectorSearch.topK(
            query: queryVector, matrix: corpus.matrix,
            count: corpus.chunks.count, dim: corpus.dim, k: candidatePool)
        let semanticIDs = semantic.map { corpus.chunks[$0.index].id }
        let semanticScore = Dictionary(
            semantic.map { (corpus.chunks[$0.index].id, $0.score) }, uniquingKeysWith: { a, _ in a })

        // Lexical candidates, restricted to this corpus's chunks.
        let lexicalIDs = store.ftsSearch(query, limit: candidatePool * 2)
            .filter { corpus.validIDs.contains($0) }
            .prefix(candidatePool)

        let lists = lexicalIDs.isEmpty ? [semanticIDs] : [semanticIDs, Array(lexicalIDs)]
        let fused = RankFusion.rrf(lists, limit: k)

        return fused.compactMap { entry in
            guard let chunk = byID[entry.id] else { return nil }
            // Prefer the cosine score for display when we have it.
            let score = semanticScore[entry.id] ?? Float(entry.score)
            return Citation(id: entry.id, chunk: chunk, score: score)
        }
    }
}
