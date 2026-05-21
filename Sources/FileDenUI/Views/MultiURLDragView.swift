import SwiftUI
import AppKit

/// Transparent overlay that captures a click-or-drag gesture.
/// - On drag past a small threshold, starts a multi-file drag session.
/// - On release without dragging, fires `onTap(modifiers)`.
struct MultiURLDragView: NSViewRepresentable {
    let urls: () -> [URL]
    var onTap: (NSEvent.ModifierFlags) -> Void = { _ in }
    /// Right-click / control-click contextual menu provider. Receives the overlay
    /// view so the menu can use it as a host (e.g. positioning a share picker).
    /// Nil means no contextual menu.
    var menu: ((NSView) -> NSMenu?)? = nil

    func makeNSView(context: Context) -> DragCaptureView {
        let v = DragCaptureView()
        v.urls = urls
        v.onTap = onTap
        v.menuProvider = menu
        return v
    }

    func updateNSView(_ nsView: DragCaptureView, context: Context) {
        nsView.urls = urls
        nsView.onTap = onTap
        nsView.menuProvider = menu
    }
}

final class DragCaptureView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onTap: (NSEvent.ModifierFlags) -> Void = { _ in }
    var menuProvider: ((NSView) -> NSMenu?)? = nil

    private var downPointInWindow: NSPoint?
    private var downEvent: NSEvent?
    private var didStartDrag = false
    private var downModifiers: NSEvent.ModifierFlags = []

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always answer for mouse — but let scroll/keyboard pass.
        return self
    }

    // Right-click / control-click: AppKit's default rightMouseDown pops up
    // whatever this returns, positioned at the event.
    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(self)
    }

    override func mouseDown(with event: NSEvent) {
        downPointInWindow = event.locationInWindow
        downEvent = event
        downModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag,
              let down = downPointInWindow,
              let downEvent
        else { return }
        let dx = event.locationInWindow.x - down.x
        let dy = event.locationInWindow.y - down.y
        guard hypot(dx, dy) > 4 else { return }

        let list = urls()
        guard !list.isEmpty else { return }

        didStartDrag = true
        let items = list.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 48, height: 48)
            let frame = NSRect(origin: NSPoint(x: down.x - size.width / 2,
                                               y: down.y - size.height / 2),
                               size: size)
            item.draggingFrame = self.convert(frame, from: nil)
            item.imageComponentsProvider = {
                let comp = NSDraggingImageComponent(key: .icon)
                icon.size = size
                comp.contents = icon
                comp.frame = NSRect(origin: .zero, size: size)
                return [comp]
            }
            return item
        }
        beginDraggingSession(with: items, event: downEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag {
            onTap(downModifiers)
        }
        downPointInWindow = nil
        downEvent = nil
        didStartDrag = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }
}

/// Overlay that drags the host window via `performDrag`.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragCaptureView { WindowDragCaptureView() }
    func updateNSView(_ nsView: WindowDragCaptureView, context: Context) {}
}

final class WindowDragCaptureView: NSView {
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

