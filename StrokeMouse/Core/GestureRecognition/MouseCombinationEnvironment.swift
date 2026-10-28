import CoreGraphics
import Foundation

final class MouseCombinationEnvironment: @unchecked Sendable {
    private let lock = NSLock()
    private var displayBounds: [CGRect] = []
    private var heldCandidates: [TargetedGesture] = []
    private var dragActive = false
    var dragOwnsMovement: Bool {
        get { lock.withLock { dragActive } }
        set { lock.withLock { dragActive = newValue } }
    }

    var displays: [CGRect] {
        get { lock.withLock { displayBounds } }
        set { lock.withLock { displayBounds = newValue } }
    }
    var held: [TargetedGesture] {
        get { lock.withLock { heldCandidates } }
        set { lock.withLock { heldCandidates = newValue } }
    }
    func reset() {
        lock.withLock { heldCandidates = []; dragActive = false }
    }
}

/// Both scroll taps consult the same owner before scroll enhancement, regardless
/// of their installation order. An accepted event is consumed exactly once.
final class MouseCombinationScrollBridge: @unchecked Sendable {
    static let shared = MouseCombinationScrollBridge()
    private let lock = NSLock()
    private weak var owner: MouseEventTap?
    func install(_ tap: MouseEventTap) { lock.withLock { owner = tap } }
    func remove(_ tap: MouseEventTap) {
        lock.withLock { if owner === tap { owner = nil } }
    }
    func markInspectedBeforeReversing(_ event: CGEvent) {
        let tap = lock.withLock { owner }
        guard tap?.interceptsScroll == true,
              event.getIntegerValueField(.eventSourceUserData) == 0 else { return }
        event.setIntegerValueField(.eventSourceUserData, value: MouseEventTap.combinationInspectedMarker)
    }
    func consume(_ event: CGEvent) -> Bool {
        let tap = lock.withLock { owner }
        return tap.map { $0.handle(type: .scrollWheel, event: event) == nil } ?? false
    }
}
