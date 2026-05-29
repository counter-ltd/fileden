import CoreGraphics
import Foundation

/// Detects a left-right "shake" from a stream of horizontal drag deltas.
///
/// Feed it each drag event's `deltaX` via ``feed(dx:now:)``; it returns `true`
/// the moment a shake completes (enough direction reversals inside the time
/// window, respecting a cooldown). Shared by ``ShakeDetector`` (shake
/// activation) and ``FileDragDetector`` (shake-for-a-new-instance), so the
/// gesture feels identical wherever it's used.
struct ShakeRecognizer {
    // Rolling window of (deltaX, timestamp) samples — only meaningful during a drag.
    private var samples: [(dx: CGFloat, t: TimeInterval)] = []
    private var lastTrigger: TimeInterval = 0

    static let windowDuration: TimeInterval = 0.45
    static let minReversals = 4        // 4 sign-changes ≈ 3 full shakes
    static let minSegmentDelta: CGFloat = 8
    static let cooldown: TimeInterval = 1.0

    /// Feed one drag event. Returns `true` exactly once per completed shake.
    mutating func feed(dx: CGFloat, now: TimeInterval) -> Bool {
        guard abs(dx) >= 1 else { return false }

        samples.append((dx: dx, t: now))
        // Prune outside the window.
        samples = samples.filter { now - $0.t < Self.windowDuration }
        guard samples.count >= 3 else { return false }

        // Count direction reversals above the per-segment movement threshold.
        var reversals = 0
        var accumulated: CGFloat = 0
        var lastSign: CGFloat = samples[0].dx.sign

        for s in samples.dropFirst() {
            let sign = s.dx.sign
            if sign == lastSign {
                accumulated += abs(s.dx)
            } else {
                if accumulated >= Self.minSegmentDelta { reversals += 1 }
                accumulated = abs(s.dx)
                lastSign = sign
            }
        }

        guard reversals >= Self.minReversals else { return false }
        guard now - lastTrigger >= Self.cooldown else { return false }

        lastTrigger = now
        samples.removeAll()
        return true
    }

    /// Drop accumulated samples — call when the gesture ends (mouse-up).
    mutating func reset() { samples.removeAll() }
}

private extension CGFloat {
    var sign: CGFloat { self >= 0 ? 1 : -1 }
}
