import AppKit
import Combine

/// Opens a Den near the cursor the moment the user starts dragging a file
/// anywhere on screen, giving them somewhere to drop it. The Den is closed
/// again on mouse-up if nothing was dropped into it.
///
/// Like `ShakeDetector`, this reacts to a left-mouse drag, so the two are
/// mutually exclusive (enforced in `FileMasterSettings`). It only fires when
/// the drag pasteboard actually carries file URLs.
///
/// Two optional behaviours, both off the activation path itself:
/// - `fileDragNewDenWhenOpen` — when off, don't open a den if one's already up.
/// - `fileDragShakeForNewInstance` — shaking mid-drag forces a fresh den even
///   when one's already open, via the shared `ShakeRecognizer`.
@MainActor
final class FileDragDetector {
    static let shared = FileDragDetector()

    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var releaseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Dens opened during the current gesture — any that don't receive a drop are
    // closed on mouseUp. A gesture can open more than one when shake-for-a-new-
    // instance fires repeatedly.
    private var gestureDens: [ShelfWindowController] = []
    private var didOpen = false
    private var shake = ShakeRecognizer()
    // Drag-pasteboard changeCount captured at mouse-down. The pasteboard keeps
    // its contents between drag sessions, so a stale fileURL would otherwise
    // make every plain mouse-drag look like a file drag. We only treat the
    // gesture as a file drag once the pasteboard is *rewritten* (changeCount
    // moves past this baseline) during the current down→up sequence.
    private var baselineChangeCount = 0

    private init() {}

    func start() {
        FileMasterSettings.shared.$fileDragActivationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMonitor() }
            .store(in: &cancellables)
        updateMonitor()
    }

    private func updateMonitor() {
        if let m = downMonitor    { NSEvent.removeMonitor(m); downMonitor    = nil }
        if let m = dragMonitor    { NSEvent.removeMonitor(m); dragMonitor    = nil }
        if let m = releaseMonitor { NSEvent.removeMonitor(m); releaseMonitor = nil }
        guard FileMasterSettings.shared.fileDragActivationEnabled else { return }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.beginGesture() }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            let dx = event.deltaX
            Task { @MainActor in self?.handleDrag(dx: dx) }
        }
        releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.endDrag() }
        }
    }

    private func beginGesture() {
        baselineChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func handleDrag(dx: CGFloat) {
        let pb = NSPasteboard(name: .drag)
        // Only act on a genuine file drag this gesture. A real file drag rewrites
        // the drag pasteboard, bumping its changeCount past the mouse-down
        // baseline; without this guard a leftover fileURL from an earlier drag
        // fires on any plain mouse-drag.
        guard pb.changeCount != baselineChangeCount else { return }
        guard pb.types?.contains(.fileURL) == true else { return }

        let settings = FileMasterSettings.shared

        // Shake mid-drag → force a brand-new instance, even when one's already
        // open. The escape hatch that pairs with "New Den each drag" being off.
        if settings.fileDragShakeForNewInstance,
           shake.feed(dx: dx, now: ProcessInfo.processInfo.systemUptime) {
            openDen()
            return
        }

        // First file-drag movement opens a den — unless the user opted out while
        // one's already up, in which case they drop into the open one.
        guard !didOpen else { return }
        didOpen = true
        if !settings.fileDragNewDenWhenOpen, DenManager.shared.hasVisibleDen { return }
        openDen()
    }

    private func openDen() {
        gestureDens.append(DenManager.shared.newDen(placement: .nearCursor))
    }

    private func endDrag() {
        didOpen = false
        shake.reset()
        let dens = gestureDens
        gestureDens.removeAll()
        guard !dens.isEmpty else { return }
        // Small delay lets the drop handler fire before we decide to close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for den in dens where !den.receivedDrop { den.close() }
        }
    }
}
