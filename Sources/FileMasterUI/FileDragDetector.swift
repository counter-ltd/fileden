import AppKit
import Combine

/// Opens a Den near the cursor the moment the user starts dragging a file
/// anywhere on screen, giving them somewhere to drop it. The Den is closed
/// again on mouse-up if nothing was dropped into it.
///
/// Like `ShakeDetector`, this reacts to a left-mouse drag, so the two are
/// mutually exclusive (enforced in `FileMasterSettings`). It only fires when
/// the drag pasteboard actually carries file URLs.
@MainActor
final class FileDragDetector {
    static let shared = FileDragDetector()

    private var dragMonitor: Any?
    private var releaseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Den opened by the current drag — closed on mouseUp if nothing landed in it.
    private weak var dragDen: ShelfWindowController?
    private var didOpen = false

    private init() {}

    func start() {
        FileMasterSettings.shared.$fileDragActivationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMonitor() }
            .store(in: &cancellables)
        updateMonitor()
    }

    private func updateMonitor() {
        if let m = dragMonitor    { NSEvent.removeMonitor(m); dragMonitor    = nil }
        if let m = releaseMonitor { NSEvent.removeMonitor(m); releaseMonitor = nil }
        guard FileMasterSettings.shared.fileDragActivationEnabled else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in self?.checkForFileDrag() }
        }
        releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.endDrag() }
        }
    }

    private func checkForFileDrag() {
        guard !didOpen else { return }
        let pb = NSPasteboard(name: .drag)
        guard pb.types?.contains(.fileURL) == true else { return }
        didOpen = true
        dragDen = DenManager.shared.newDen(placement: .nearCursor)
    }

    private func endDrag() {
        didOpen = false
        guard let den = dragDen else { return }
        dragDen = nil
        // Small delay lets the drop handler fire before we decide to close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !den.receivedDrop { den.close() }
        }
    }
}
