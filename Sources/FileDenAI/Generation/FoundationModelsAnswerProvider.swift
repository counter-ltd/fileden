import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A grounded, cited answer synthesized by the on-device LLM.
public struct SynthesizedAnswer: Sendable {
    public let text: String
    /// Ids of the citations the model actually used (subset of those it was given).
    public let citedIDs: [Int64]
}

/// Streaming events while the model writes an answer.
public enum AnswerStreamEvent: Sendable {
    case partialText(String)             // cumulative answer text so far
    case completed(SynthesizedAnswer)    // final text + resolved citations
}

/// Synthesizes answers with Apple's on-device Foundation Models LLM. This is the
/// **only** file that imports FoundationModels; everything is gated behind
/// `@available(macOS 26, *)` and a runtime availability check, and the framework
/// is weak-linked, so the app still runs where the model isn't present.
///
/// Answers are strictly grounded in the retrieved passages, and the model returns
/// the block numbers it used so citations are precise (not hallucinated): the LLM
/// only ever sees opaque block numbers, never file paths or offsets.
@available(macOS 26, *)
public enum FoundationModelsAnswerProvider {
    /// True only when the system model is ready (device eligible, Apple
    /// Intelligence on, model downloaded).
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// Reason the model can't be used, for surfacing in the UI. Nil when available.
    public static var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to get written answers."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "The on-device model is unavailable."
        }
        #else
        return "Built without FoundationModels."
        #endif
    }

    /// Stream an answer for `question` grounded in `citations`, emitting the
    /// answer text as it's written and a final event with resolved citations.
    /// Retries with fewer context blocks if the prompt overflows the window.
    public static func streamAnswer(question: String, citations: [Citation]) -> AsyncThrowingStream<AnswerStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                let pool = Array(citations.prefix(6))
                guard !pool.isEmpty else {
                    continuation.yield(.completed(SynthesizedAnswer(
                        text: "I couldn't find anything about that in these documents.", citedIDs: [])))
                    continuation.finish()
                    return
                }
                var blockCount = pool.count
                while true {
                    do {
                        let answer = try await runStream(question: question, blocks: Array(pool.prefix(blockCount))) {
                            continuation.yield(.partialText($0))
                        }
                        continuation.yield(.completed(answer))
                        continuation.finish()
                        return
                    } catch let error as LanguageModelSession.GenerationError {
                        if case .exceededContextWindowSize = error, blockCount > 1 {
                            blockCount = max(1, blockCount / 2)
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                #else
                continuation.finish(throwing: AskError.embeddingsUnavailable)
                #endif
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Non-streaming convenience (used in tests).
    public static func answer(question: String, citations: [Citation]) async throws -> SynthesizedAnswer {
        #if canImport(FoundationModels)
        let pool = Array(citations.prefix(6))
        guard !pool.isEmpty else {
            return SynthesizedAnswer(text: "I couldn't find anything about that in these documents.", citedIDs: [])
        }
        var blockCount = pool.count
        while true {
            do {
                return try await runStream(question: question, blocks: Array(pool.prefix(blockCount)), onText: { _ in })
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, blockCount > 1 {
                    blockCount = max(1, blockCount / 2)
                    continue
                }
                throw error
            }
        }
        #else
        throw AskError.embeddingsUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    @Generable
    struct CitedAnswer {
        @Guide(description: "A concise answer grounded only in the provided context blocks. If the context does not contain the answer, say you couldn't find it in these documents.")
        var answer: String
        @Guide(description: "The numbers of the context blocks that support the answer, for example [1, 3].")
        var citedBlocks: [Int]
    }

    private static let instructions = """
    You answer questions about the user's documents using ONLY the numbered context blocks provided. \
    Ground every statement in that context and do not use outside knowledge. \
    If the context does not contain the answer, say you couldn't find it in these documents. \
    For ANY arithmetic — totals, sums, differences, products, percentages, or counts — you MUST call \
    the `calculate` tool and report its exact result; never do the math yourself. \
    Be concise, and cite the numbers of the blocks you used.
    """

    /// Lets the model compute exact arithmetic instead of guessing it. Small
    /// on-device models read numbers fine but are unreliable at adding them, so
    /// math is delegated to this tool.
    struct CalculatorTool: Tool {
        let name = "calculate"
        let description = "Evaluate an arithmetic expression and return the exact result. Use for any totals, sums, differences, products, percentages, or counts over numbers found in the documents."

        @Generable
        struct Arguments {
            @Guide(description: "An arithmetic expression using digits and + - * / ( ) only, e.g. '42000 + 68000 + 97000 + 124000'.")
            var expression: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let value = ArithmeticEvaluator.evaluate(arguments.expression) else {
                return "Could not evaluate \"\(arguments.expression)\"."
            }
            let result = value == value.rounded()
                ? String(Int(value))
                : String(format: "%.4f", value)
            return "\(arguments.expression) = \(result)"
        }
    }

    private static func prompt(question: String, blocks: [Citation]) -> String {
        let context = blocks.enumerated().map { index, citation in
            "[\(index + 1)] (\(citation.sourceURL.lastPathComponent), \(citation.locationLabel))\n\(citation.chunk.text)"
        }.joined(separator: "\n\n")
        return "Context:\n\(context)\n\nQuestion: \(question)"
    }

    /// Run one streamed generation, forwarding cumulative text via `onText` and
    /// returning the final answer with resolved citation ids.
    private static func runStream(question: String, blocks: [Citation],
                                  onText: @escaping (String) -> Void) async throws -> SynthesizedAnswer {
        let session = LanguageModelSession(tools: [CalculatorTool()], instructions: instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 600)
        let stream = session.streamResponse(
            to: prompt(question: question, blocks: blocks),
            generating: CitedAnswer.self,
            options: options)

        var lastText = ""
        var lastBlocks: [Int] = []
        for try await partial in stream {
            if let text = partial.content.answer {
                lastText = text
                onText(text)
            }
            if let cited = partial.content.citedBlocks {
                lastBlocks = cited
            }
        }
        let citedIDs = lastBlocks.compactMap { number -> Int64? in
            let index = number - 1
            return blocks.indices.contains(index) ? blocks[index].id : nil
        }
        return SynthesizedAnswer(text: lastText, citedIDs: citedIDs)
    }
    #endif
}
