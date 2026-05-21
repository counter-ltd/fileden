import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Thin wrapper over one streamed, plain-text generation from the on-device model
/// with tools attached. Plain text (not guided `@Generable`) is deliberate: it
/// avoids the `decodingFailure` that makes structured generation flaky, which is
/// the bulletproofing win. The caller owns prompt construction and retry policy.
enum LLMResponder {
    private static let core = """
    You are a helpful assistant answering questions about the user's own documents in a conversation. \
    Answer the user's latest message directly, using the provided excerpts as your primary source and \
    staying grounded in them; you may use the conversation so far for context. If the excerpts don't \
    contain the answer, say so plainly rather than inventing facts.
    """

    /// Calculator guidance, added only when the turn actually calls for arithmetic.
    /// Kept out of plain turns so a small model doesn't fixate on figures in a
    /// number-heavy document and refuse factual questions ("who's the landlord?")
    /// in arithmetic terms.
    private static let arithmeticGuidance = """
    Only when the user explicitly asks you to compute something over numbers in the documents — a \
    total, sum, difference, product, or percentage — call the `calculate` tool and report its result. \
    When the numbers live in a table with several columns, take the values from the exact column the \
    user named (e.g. revenue, not users), passing them as written (keep the currency symbols).
    """

    private static let graphGuidance = """
    When the user asks for a chart, graph, plot, or data visualization, extract the relevant \
    labels and numeric values from the document excerpts and output a graph specification using \
    EXACTLY this format — the raw XML tag with JSON inside, no markdown code fences, no extra \
    formatting: <graph>{"type":"TYPE","title":"TITLE","labels":["Label1","Label2"],"values":[1.0,2.0]}</graph> \
    Supported types: "bar" for comparing categories, "pie" for proportions, "line" for trends. \
    IMPORTANT: Do NOT wrap it in ```json or any code block. Write the <graph> tag directly in \
    your response. You may add one sentence of context before or after. Output at most one graph tag.
    """

    private static let closing = "Be concise and conversational."

    /// Instructions tuned to the turn: calculator and/or graph guidance is included only
    /// when the question actually calls for it, preventing small models from fixating on
    /// numbers or graph syntax in unrelated answers.
    static func instructions(arithmetic: Bool, graph: Bool = false) -> String {
        var parts = [core]
        if arithmetic { parts.append(arithmeticGuidance) }
        if graph      { parts.append(graphGuidance) }
        parts.append(closing)
        return parts.joined(separator: " ")
    }

    #if canImport(FoundationModels)
    /// Stream a response for `prompt`, forwarding cumulative text via `onText`,
    /// returning the final text. Throws `GenerationError` (caller handles overflow).
    /// Pass the same `instructions` whose calculator guidance matches whether
    /// `tools` includes the calculator.
    @available(macOS 26, *)
    static func stream(prompt: String,
                       tools: [any Tool],
                       instructions: String,
                       onText: @escaping (String) -> Void) async throws -> String {
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        let options = GenerationOptions(temperature: 0.4, maximumResponseTokens: 800)
        var last = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            last = snapshot.content
            onText(last)
        }
        return last
    }

    /// True if `error` is a context-window overflow (caller should retry smaller).
    @available(macOS 26, *)
    static func isContextOverflow(_ error: Error) -> Bool {
        if let generationError = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }
    #endif
}
