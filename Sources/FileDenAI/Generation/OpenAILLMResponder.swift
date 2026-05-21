import Foundation

/// Streams a chat completion from any OpenAI-compatible endpoint.
/// Works unmodified for OpenAI (api.openai.com/v1), Ollama (/v1), and llama.cpp (/v1).
enum OpenAILLMResponder {

    /// Stream a response using SSE, calling `onText` with the cumulative text on each chunk.
    /// Returns the final accumulated text. Throws on network or HTTP error.
    static func stream(
        prompt: String,
        systemPrompt: String,
        config: LLMConfiguration,
        onText: @escaping (String) -> Void
    ) async throws -> String {
        let base = config.baseURL.hasSuffix("/")
            ? String(config.baseURL.dropLast())
            : config.baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model":       config.model,
            "messages":    [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "stream":      true,
            "temperature": 0.4,
            "max_tokens":  800
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]" else { break }
            guard
                let data  = payload.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data),
                let delta = chunk.choices.first?.delta.content
            else { continue }
            accumulated += delta
            onText(accumulated)
        }
        return accumulated
    }
}

// MARK: - SSE response shape

private struct SSEChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        struct Delta: Decodable {
            let content: String?
        }
    }
}
