#if APPSTAGE
import AppKit
import SwiftUI
import FileDenCore
import FileDenAI

// Dev tool: render one UI state on-screen for appstage to screenshot, then keep
// running so the window can be captured. Activated by `--appstage <state>`.
//
// Everything is synthetic: the den holds throwaway placeholder files created in
// an isolated temp dir (Paths is forced there in APPSTAGE builds), and the Ask
// transcript is a pre-built conversation — the indexer and LLM never run. Real
// files, dens, indices and notebooks are never touched. Prints one line:
//
//   @@APPSTAGE_READY@@ {"window":<cgWindowID>,"w":W,"h":H,"slug":"<state>"}
//
// This whole file is compiled out of normal/release builds.
@MainActor
enum AppStageCapture {
    static let state: String? = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--appstage"), i + 1 < args.count {
            return args[i + 1]
        }
        return nil
    }()

    static func run(state: String) {
        NSApp.setActivationPolicy(.accessory)

        let cornerRadius: CGFloat
        let inner: AnyView
        switch state {
        case "ask":
            let session = QASession(demoMessages: demoMessages(), fileCount: 3)
            inner = AnyView(QAView(session: session).frame(width: 440, height: 430))
            cornerRadius = 16
        case "compact":
            inner = AnyView(ShelfView(initialURLs: demoFiles(), initiallyExpanded: false))
            cornerRadius = 24
        case "drop":
            inner = AnyView(ShelfView(initialURLs: demoFiles(), initiallyExpanded: true,
                                      initiallyTargeted: true))
            cornerRadius = 24
        case "list":
            inner = AnyView(ShelfView(initialURLs: demoFiles(), initiallyExpanded: true,
                                      initialViewMode: .list))
            cornerRadius = 24
        case "pdf":
            inner = AnyView(ShelfView(initialURLs: pdfFiles(), initiallyExpanded: true))
            cornerRadius = 24
        case "convert":
            inner = AnyView(ShelfView(initialURLs: mediaFiles(), initiallyExpanded: true))
            cornerRadius = 24
        default: // "shelf"
            inner = AnyView(ShelfView(initialURLs: demoFiles(), initiallyExpanded: true))
            cornerRadius = 24
        }

        // Opaque backing so the den/chat material doesn't sample the desktop;
        // clipped to a rounded card; the window itself is transparent and sized
        // tight, so the capture is just the app's UI with transparent surround.
        let root = inner
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .dark)

        let host = NSHostingController(rootView: root)
        let window = CaptureWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // ShelfView expands in onAppear, so re-measure and size the window to the
        // settled content before reporting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            host.view.layoutSubtreeIfNeeded()
            let fit = host.view.fittingSize
            if fit.width > 80 && fit.height > 80 {
                window.setContentSize(fit)
                window.center()
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let f = window.frame
                print(
                    "@@APPSTAGE_READY@@ {\"window\":\(window.windowNumber),"
                    + "\"w\":\(Int(f.width)),\"h\":\(Int(f.height)),\"slug\":\"\(state)\"}"
                )
                fflush(stdout)
            }
        }
    }

    // Throwaway placeholder files (real, empty) so the den shows proper type
    // icons via NSWorkspace without referencing any of the user's files.
    private static func demoFiles() -> [URL] {
        placeholders(["Q3 Report.pdf", "Brand Moodboard.png", "Contract.docx",
                       "Release Notes.md", "assets.zip"])
    }

    // A spread of PDF documents — triggers PDF Tools in the actions menu.
    private static func pdfFiles() -> [URL] {
        placeholders(["Annual Report.pdf", "Brand Guide.pdf",
                       "Press Kit.pdf", "Product Spec.pdf"])
    }

    // A spread of image + video files — triggers Convert Image / Convert Video.
    private static func mediaFiles() -> [URL] {
        placeholders(["hero.png", "product-shot.jpg", "walkthrough.mov",
                       "banner.webp", "thumbnail.heic"])
    }

    private static func placeholders(_ names: [String]) -> [URL] {
        let dir = Paths.appSupport.appendingPathComponent("DemoFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return names.map { name in
            let url = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            return url
        }
    }

    // A pre-built, grounded answer with a citation — no indexer, no LLM.
    private static func demoMessages() -> [ChatMessage] {
        let docURL = Paths.appSupport
            .appendingPathComponent("DemoFiles/Q3 Report.pdf")
        let chunk = Chunk(
            sourceURL: docURL,
            ordinal: 2,
            text: "Revenue grew 24% quarter-over-quarter, driven mainly by enterprise renewals and the launch of the EU region.",
            locator: .pdfPage(index: 2, charRange: nil)
        )
        let citation = Citation(id: 1, chunk: StoredChunk(id: 1, chunk: chunk), score: 0.95)
        return [
            ChatMessage(role: .user, text: "What drove the revenue increase this quarter?"),
            ChatMessage(
                role: .assistant,
                text: "Revenue grew 24% quarter-over-quarter, driven mainly by enterprise renewals and the new EU region launch.",
                citations: [citation],
                isStreaming: false
            ),
        ]
    }
}

private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
