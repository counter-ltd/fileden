import AppKit
import PDFKit
import FileDenAI

/// Opens a citation at its exact source location, in-app, with the cited passage
/// highlighted (the "clickable to jump there" requirement). PDFs open in a
/// `PDFView` scrolled to the page; text/Markdown/HTML/RTF/DOCX/code open in a
/// text viewer scrolled to the highlighted span.
@MainActor
enum CitationOpener {
    static func open(_ citation: Citation) {
        switch citation.chunk.locator {
        case .pdfPage(let index, let charRange):
            PDFCitationWindow.show(url: citation.sourceURL, page: index, charRange: charRange)
        case .textRange(let charRange, _):
            TextCitationWindow.show(url: citation.sourceURL, charRange: charRange)
        }
    }
}

/// A lightweight PDF viewer window that jumps to a page and highlights a passage.
@MainActor
final class PDFCitationWindow: NSWindowController, NSWindowDelegate {
    private static var open: [PDFCitationWindow] = []
    private let pdfView = PDFView()

    static func show(url: URL, page: Int, charRange: Range<Int>?) {
        let controller = PDFCitationWindow(url: url, page: page, charRange: charRange)
        open.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(url: URL, page: Int, charRange: Range<Int>?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 840),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        super.init(window: window)
        window.delegate = self
        window.center()

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        window.contentView = pdfView

        guard let document = PDFDocument(url: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        pdfView.document = document
        guard page >= 0, page < document.pageCount, let pdfPage = document.page(at: page) else { return }
        pdfView.go(to: pdfPage)

        if let range = charRange, range.lowerBound >= 0,
           let selection = pdfPage.selection(for: NSRange(location: range.lowerBound, length: range.count)) {
            selection.color = .systemYellow
            pdfView.highlightedSelections = [selection]
            pdfView.setCurrentSelection(selection, animate: true)
            // Scroll once layout has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.pdfView.go(to: selection)
                self?.pdfView.scrollSelectionToVisible(nil)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        PDFCitationWindow.open.removeAll { $0 === self }
    }
}

/// A text viewer that shows a non-PDF source and highlights the cited span. It
/// displays exactly the text the indexer chunked (e.g. HTML stripped to plain
/// text, RTF/DOCX decoded) so the stored character offsets line up.
@MainActor
final class TextCitationWindow: NSWindowController, NSWindowDelegate {
    private static var open: [TextCitationWindow] = []
    private let textView = NSTextView()

    static func show(url: URL, charRange: Range<Int>?) {
        let controller = TextCitationWindow(url: url, charRange: charRange)
        open.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(url: URL, charRange: Range<Int>?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        super.init(window: window)
        window.delegate = self
        window.center()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        scroll.documentView = textView
        window.contentView = scroll

        let text = Self.displayText(for: url)
        textView.string = text

        guard let range = charRange else { return }
        let ns = text as NSString
        let location = max(0, min(range.lowerBound, ns.length))
        let length = max(0, min(range.count, ns.length - location))
        let nsRange = NSRange(location: location, length: length)
        textView.textStorage?.addAttribute(.backgroundColor,
                                           value: NSColor.systemYellow.withAlphaComponent(0.4),
                                           range: nsRange)
        textView.setSelectedRange(nsRange)
        // Scroll once layout has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.textView.scrollRangeToVisible(nsRange)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        TextCitationWindow.open.removeAll { $0 === self }
    }

    /// The same text the chunker saw, so offsets align.
    private static func displayText(for url: URL) -> String {
        let segments = TextExtractor.extract(url)
        for segment in segments {
            if case .wholeText = segment.origin { return segment.text }
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
