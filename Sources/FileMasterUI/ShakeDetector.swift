import AppKit
import Combine

final class ShakeDetector {
    static let shared = ShakeDetector()

    private var dragMonitor: Any?
    private var releaseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var shake = ShakeRecognizer()
    // Den opened by the current shake gesture — closed on mouseUp if nothing was dropped in
    private weak var shakeDen: ShelfWindowController?

    private init() {}

    func start() {
        FileMasterSettings.shared.$shakeActivationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMonitor() }
            .store(in: &cancellables)
        updateMonitor()
    }

    func updateMonitor() {
        if let m = dragMonitor    { NSEvent.removeMonitor(m); dragMonitor    = nil }
        if let m = releaseMonitor { NSEvent.removeMonitor(m); releaseMonitor = nil }
        guard FileMasterSettings.shared.shakeActivationEnabled else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handle(event)
        }
        releaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.shake.reset()
            guard let self, let den = self.shakeDen else { return }
            self.shakeDen = nil
            // Small delay lets the drop handler fire before we decide to close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !den.receivedDrop { den.close() }
            }
        }
    }

    private func handle(_ event: NSEvent) {
        guard shake.feed(dx: event.deltaX, now: ProcessInfo.processInfo.systemUptime) else { return }
        DispatchQueue.main.async { @MainActor [weak self] in
            let den = DenManager.shared.newDen(placement: .nearCursor)
            self?.shakeDen = den
        }
    }
}
