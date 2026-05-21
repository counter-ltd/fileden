import Foundation
import AppKit
import FileDenAI

/// Drives the Ask UI as a multi-turn chat over a den's documents: indexes them in
/// the background, then runs each turn through ``DocumentChat`` (retrieve →
/// synthesize, with a passages fallback that never dead-ends). Mirrors the app's
/// off-main work pattern and publishes the transcript to ``QAView``.
@MainActor
final class QASession: ObservableObject {
    enum Phase: Equatable {
        case indexing
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase = .indexing
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy = false           // a turn is in flight

    let fileCount: Int
    private let urls: [URL]
    private var engine: AskEngine?
    private var chat: DocumentChat?
    private var turnTask: Task<Void, Never>?
    private let work = DispatchQueue(label: "ltd.anti.FileDen.ask", qos: .userInitiated)

    init(urls: [URL]) {
        self.urls = urls
        self.fileCount = urls.filter { TextExtractor.canExtract($0) }.count
        startIndexing()
    }

    var hasMessages: Bool { !messages.isEmpty }
    var llmAvailable: Bool { Intelligence.isAvailable }
    var llmUnavailableNote: String? { Intelligence.unavailabilityReason }

    // MARK: - Indexing

    private func startIndexing() {
        guard fileCount > 0 else { phase = .empty; return }
        phase = .indexing
        let hud = ProgressHUD(label: "Indexing documents")
        let urls = self.urls
        work.async { [weak self] in
            do {
                let engine = try AskEngine()
                try engine.prepare(urls: urls) { fraction in
                    Task { @MainActor in hud.update(fraction) }
                }
                Task { @MainActor in
                    hud.finish()
                    guard let self else { return }
                    self.engine = engine
                    let supported = urls.filter { TextExtractor.canExtract($0) }
                    self.chat = DocumentChat(documentURLs: supported,
                                             retrieve: { query, k in engine.retrieve(query, topK: k) })
                    self.phase = engine.isReady ? .ready : .empty
                }
            } catch {
                let message = Self.message(for: error)
                Task { @MainActor in
                    hud.finish()
                    self?.phase = .failed(message)
                }
            }
        }
    }

    // MARK: - Chatting

    func send(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy, phase == .ready, let chat else { return }

        let history = messages
        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, isStreaming: true)
        messages.append(assistant)
        let assistantID = assistant.id
        isBusy = true

        let synthesize = FileDenSettings.shared.aiSynthesisEnabled
        turnTask = Task { [weak self] in
            for await event in chat.send(question: trimmed, history: history, synthesize: synthesize) {
                if Task.isCancelled { return }
                switch event {
                case .citations(let citations):
                    self?.update(assistantID) { $0.citations = citations }
                case .partialText(let text):
                    self?.update(assistantID) { $0.text = text }
                case .completed(let text, _):
                    self?.update(assistantID) { $0.text = text; $0.isStreaming = false }
                }
            }
            self?.update(assistantID) { $0.isStreaming = false }
            self?.isBusy = false
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private nonisolated static func message(for error: Error) -> String {
        switch error {
        case AskError.noSupportedFiles:
            return "No PDF, text, Markdown, or HTML files to search."
        case AskError.embeddingsUnavailable:
            return "On-device text embeddings aren't available on this Mac."
        default:
            return "Couldn't index these documents."
        }
    }
}
