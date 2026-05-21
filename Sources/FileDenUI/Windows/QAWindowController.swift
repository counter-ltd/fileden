import AppKit
import SwiftUI
import FileDenAI

/// Hosts a single Ask window. Unlike den panels (borderless, non-activating),
/// this is a titled floating panel that can become key — the user types into it.
/// Owns one ``QASession`` for the documents it was opened with.
public final class QAWindowController: NSWindowController, NSWindowDelegate {
    public convenience init(urls: [URL]) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "Ask"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 360, height: 420)

        self.init(window: panel)
        panel.delegate = self

        let session = QASession(urls: urls)
        panel.contentView = NSHostingView(rootView: QAView(session: session))
        panel.center()
    }

    override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// Bring the window forward and focus it so the user can type immediately.
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .qaClosed, object: ObjectIdentifier(self))
    }
}
