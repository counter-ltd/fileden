import SwiftUI
import AppKit
import FileDenAI

/// The Ask window: a status banner, the answer area (a written answer when the
/// on-device LLM is available, plus the source passages it drew from), and a
/// question input. Clicking a source jumps to it in the document.
struct QAView: View {
    @ObservedObject var session: QASession
    @ObservedObject private var settings = FileDenSettings.shared
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            banner
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            inputBar
        }
        .frame(minWidth: 360, minHeight: 420)
        .background(.background)
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

    /// Inline, configurable answer mode. Disabled (with a reason) when the
    /// on-device model isn't available — then Ask shows passages only.
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

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if session.isSearching {
            centered { ProgressView("Searching…").controlSize(.small) }
        } else if !session.hasAsked {
            centered {
                VStack(spacing: 6) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Ask a question about your documents.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Answers cite the exact passage — click to jump there.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .multilineTextAlignment(.center)
            }
        } else if session.citations.isEmpty {
            centered {
                Text("No relevant passages found for “\(session.lastQuestion)”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if session.isAnswering || session.answerText != nil {
                        answerSection
                    }
                    sourcesSection
                }
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder private var answerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Answer")
            if let text = session.answerText {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Writing answer…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(session.answerText != nil ? "Sources" : "Top passages")
            ForEach(orderedCitations) { citation in
                CitationRow(citation: citation, isCited: session.answerCitedIDs.contains(citation.id))
                    .padding(.horizontal, 10)
            }
        }
    }

    /// Cited sources first when we have an answer; otherwise retrieval order.
    private var orderedCitations: [Citation] {
        guard !session.answerCitedIDs.isEmpty else { return session.citations }
        let cited = session.citations.filter { session.answerCitedIDs.contains($0.id) }
        let rest = session.citations.filter { !session.answerCitedIDs.contains($0.id) }
        return cited + rest
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
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
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit(submit)
                .disabled(session.phase != .ready)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canAsk ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canAsk)
        }
        .padding(12)
    }

    private var canAsk: Bool {
        session.phase == .ready && !session.isSearching && !session.isAnswering &&
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canAsk else { return }
        session.ask(question)
    }

    private func plural(_ n: Int) -> String { n == 1 ? "document" : "documents" }
}

/// One source passage: file, location, excerpt. Clicking jumps to the source.
private struct CitationRow: View {
    let citation: Citation
    var isCited: Bool = false

    var body: some View {
        Button(action: { CitationOpener.open(citation) }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(citation.sourceURL.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if isCited {
                        Text("cited")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 6)
                    Text(citation.locationLabel)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text(citation.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isCited ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(citation.sourceURL.lastPathComponent) at \(citation.locationLabel)")
    }

    private var icon: String {
        citation.sourceURL.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc.text"
    }
}
