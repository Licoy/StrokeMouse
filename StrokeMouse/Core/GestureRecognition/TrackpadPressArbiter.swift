import CoreGraphics
import Foundation

/// A physical press made while a grouped set of fingers rested on the trackpad.
struct TrackpadPress: Equatable, Sendable {
    let sequenceID: UInt64
    let fingers: Int
    let centroid: CGPoint
}

enum TrackpadPressResolution: Equatable, Sendable {
    /// No finger is on the trackpad: an ordinary pointer click.
    case unrelated
    /// The sequence was pressed, but the press is not an armed click gesture.
    case observed
    case click(TrackpadPress)
}

/// Correlates left-button edges with the current contact sequence.
///
/// Frames are recorded on the runtime input queue; `press` runs on the click
/// tap thread, so every entry point only takes this lock.
final class TrackpadPressArbiter: @unchecked Sendable {
    private struct Sequence {
        let id: UInt64
        let landedAt: TimeInterval
        var lastLandingAt: TimeInterval
        var active: [Int: CGPoint]
        var origins: [Int: CGPoint]
        var maximumTravel: CGFloat = 0
        var hasLifted = false
        var armedFingerCounts: Set<Int> = []
        var wasPressed = false
    }

    private static let timeTolerance: TimeInterval = 1e-9

    private let policy: TrackpadRecognitionPolicy
    private let lock = NSLock()
    private var sequence: Sequence?

    init(policy: TrackpadRecognitionPolicy = .init()) {
        self.policy = policy
    }

    /// Returns whether the frame's sequence has been physically pressed. The
    /// release frame still reports it so the lift can reject a tap.
    func record(_ frame: TrackpadTouchFrame, sequenceID: UInt64) -> Bool {
        let active = Dictionary(
            frame.contacts.filter(\.phase.isActive).map {
                ($0.id, $0.position)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        return lock.withLock {
            guard !active.isEmpty else {
                let wasPressed = sequence?.id == sequenceID
                    && sequence?.wasPressed == true
                sequence = nil
                return wasPressed
            }
            guard var current = sequence, current.id == sequenceID else {
                sequence = Sequence(
                    id: sequenceID,
                    landedAt: frame.timestamp,
                    lastLandingAt: frame.timestamp,
                    active: active,
                    origins: active
                )
                return false
            }
            if current.active.keys.contains(where: { active[$0] == nil }) {
                current.hasLifted = true
            }
            for (id, point) in active {
                if let origin = current.origins[id] {
                    current.maximumTravel = max(
                        current.maximumTravel,
                        hypot(point.x - origin.x, point.y - origin.y)
                    )
                } else {
                    current.origins[id] = point
                    current.lastLandingAt = frame.timestamp
                }
            }
            current.active = active
            sequence = current
            return current.wasPressed
        }
    }

    /// Finger counts whose press the target application turns into a click
    /// gesture. Set once the sequence's target is known.
    func arm(sequenceID: UInt64, fingerCounts: Set<Int>) {
        lock.withLock {
            guard sequence?.id == sequenceID else { return }
            sequence?.armedFingerCounts = fingerCounts
        }
    }

    /// Classifies a left-button down. Every press marks its sequence so the
    /// lift never also yields a tap; only a grouped, resting, armed contact
    /// set may become a click, and only when the tap can swallow the edge.
    func press(canSwallow: Bool) -> TrackpadPressResolution {
        lock.withLock {
            guard var current = sequence else { return .unrelated }
            current.wasPressed = true
            sequence = current
            let fingers = current.active.count
            guard canSwallow,
                  current.armedFingerCounts.contains(fingers),
                  !current.hasLifted,
                  current.lastLandingAt - current.landedAt
                      <= policy.maximumLandingSpread + Self.timeTolerance,
                  current.maximumTravel <= policy.maximumPressTravel
            else {
                return .observed
            }
            let sum = current.active.values.reduce(CGPoint.zero) {
                CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
            }
            return .click(TrackpadPress(
                sequenceID: current.id,
                fingers: fingers,
                centroid: CGPoint(
                    x: sum.x / CGFloat(fingers),
                    y: sum.y / CGFloat(fingers)
                )
            ))
        }
    }

    func reset() {
        lock.withLock { sequence = nil }
    }
}
