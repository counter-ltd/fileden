import SwiftUI
import AppKit
import FileDenAI

/// The Ask UI: a multi-turn chat over the den's documents. User turns appear as
/// accent bubbles; assistant turns stream in on material cards with the sources
/// they used. Clicking a source opens it in the viewer pane.
struct QAView: View {
    @ObservedObject var session: QASession
    @ObservedObject private var settings = FileDenSettings.shared
    @State private var question = ""
    @FocusState private var inputFocused: Bool
    /// Called when a source is clicked, so the host can show it in a pane.
    var onOpenCitation: ((Citation) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            banner
            Divider().opacity(0.4)
            transcript
            Divider().opacity(0.4)
            inputBar
        }
        .frame(minWidth: 360, minHeight: 420)
        .onAppear { if session.phase == .ready { inputFocused = true } }
        .onChange(of: session.phase) { _, phase in
            if phase == .ready { inputFocused = true }
        }
    }

    // MARK: - Banner

    @ViewBuilder private var banner: some View {
        HStack(spacing: 8) {
            switch session.phase {
            case .indexing:
                ProgressView().controlSize(.small)
                Text("Indexing \(session.fileCount) \(plural(session.fileCount))…")
            case .ready:
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("\(session.fileCount) \(plural(session.fileCount)) · offline")
                Spacer()
                aiToggle
            case .empty:
                Image(systemName: "doc.questionmark").foregroundStyle(.secondary)
                Text("Nothing to search — add PDF, text, Markdown, or HTML files.")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message)
            }
            if case .ready = session.phase {} else { Spacer() }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(2)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var aiToggle: some View {
        if session.llmAvailable {
            Toggle(isOn: $settings.aiSynthesisEnabled) {
                Text("AI answer").font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        } else if let note = session.llmUnavailableNote {
            Text("Passages only")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .help(note)
        }
    }

    // MARK: - Transcript

    @ViewBuilder private var transcript: some View {
        if !session.hasMessages {
            centered {
                VStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Chat with your documents.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Grounded answers cite the exact passage — click to jump there.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(session.messages) { message in
                            messageView(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: session.messages.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: session.messages.last?.text) { _, _ in scrollToEnd(proxy) }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = session.messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
        case .assistant:
            assistantBubble(message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func assistantBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !message.citations.isEmpty {
                HStack {
                    Spacer()
                    SourcesButton(citations: message.citations,
                                  onOpen: { onOpenCitation?($0) })
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a question…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .onSubmit(submit)
                .disabled(session.phase != .ready)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
        }
        .padding(12)
    }

    private var canSend: Bool {
        session.phase == .ready && !session.isBusy &&
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        session.send(question)
        question = ""
    }

    private func plural(_ n: Int) -> String { n == 1 ? "document" : "documents" }
}

/// A small chip on an assistant bubble showing the source count; tap for a
/// popover listing the sources, each clickable to open in the viewer pane.
private struct SourcesButton: View {
    let citations: [Citation]
    let onOpen: (Citation) -> Void
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening").font(.system(size: 10, weight: .semibold))
                Text("\(citations.count) \(citations.count == 1 ? "source" : "sources")")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show sources")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            SourcesPopover(citations: citations, onOpen: { citation in
                showing = false
                onOpen(citation)
            })
        }
    }
}

/// Brief rundown of an answer's sources, shown in a popover.
private struct SourcesPopover: View {
    let citations: [Citation]
    let onOpen: (Citation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(citations) { citation in
                Button { onOpen(citation) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: icon(citation)).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(citation.sourceURL.lastPathComponent)
                                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(citation.locationLabel)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Text(citation.snippet)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(citation.sourceURL.lastPathComponent) at \(citation.locationLabel)")
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func icon(_ citation: Citation) -> String {
        citation.sourceURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text"
    }
}
