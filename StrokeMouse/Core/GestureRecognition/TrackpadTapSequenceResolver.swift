import CoreGraphics
import Foundation

struct TrackpadTap: Equatable, Sendable {
    let deviceID: UInt64
    let fingers: Int
    let centroid: CGPoint
    let beganAt: TimeInterval
    let timestamp: TimeInterval

    init(
        deviceID: UInt64,
        fingers: Int,
        centroid: CGPoint,
        beganAt: TimeInterval? = nil,
        timestamp: TimeInterval
    ) {
        self.deviceID = deviceID
        self.fingers = fingers
        self.centroid = centroid
        self.beganAt = beganAt ?? timestamp
        self.timestamp = timestamp
    }
}

struct TrackpadTapAvailability: Equatable, Sendable {
    let hasSingle: Bool
    let hasDouble: Bool

    static let singleOnly = Self(hasSingle: true, hasDouble: false)
    static let doubleOnly = Self(hasSingle: false, hasDouble: true)
    static let singleAndDouble = Self(hasSingle: true, hasDouble: true)
}

enum TrackpadTapResolution: Equatable, Sendable {
    case single(TrackpadTap)
    case double(first: TrackpadTap, second: TrackpadTap)
    case invalidTimestamp
}

struct TrackpadTapSequenceResolver {
    private struct Pending {
        let tap: TrackpadTap
        let availability: TrackpadTapAvailability
    }

    private let doubleClickInterval: TimeInterval
    private let maximumCentroidDistance: CGFloat
    private var pending: Pending?
    private var lastTimestamp: TimeInterval?

    init(
        doubleClickInterval: TimeInterval,
        maximumCentroidDistance: CGFloat = 0.10
    ) {
        self.doubleClickInterval = max(0, doubleClickInterval)
        self.maximumCentroidDistance = maximumCentroidDistance
    }

    mutating func register(
        _ tap: TrackpadTap,
        availability: TrackpadTapAvailability
    ) -> [TrackpadTapResolution] {
        guard isValid(timestamp: tap.timestamp),
              tap.beganAt.isFinite,
              tap.beganAt <= tap.timestamp,
              tap.centroid.x.isFinite,
              tap.centroid.y.isFinite,
              (3...5).contains(tap.fingers)
        else {
            return [.invalidTimestamp]
        }

        if let pending, formsDouble(first: pending.tap, second: tap),
           pending.availability.hasDouble,
           availability.hasDouble
        {
            self.pending = nil
            lastTimestamp = tap.timestamp
            return [.double(first: pending.tap, second: tap)]
        }

        var resolutions = expirePending(at: tap.timestamp)
        if pending != nil {
            resolutions.append(contentsOf: flushPending())
        }
        resolutions.append(contentsOf: startSequence(tap, availability: availability))
        lastTimestamp = tap.timestamp
        return resolutions
    }

    mutating func advance(to timestamp: TimeInterval) -> [TrackpadTapResolution] {
        guard isValid(timestamp: timestamp) else {
            return [.invalidTimestamp]
        }
        lastTimestamp = timestamp
        return expirePending(at: timestamp)
    }

    mutating func interrupt() -> [TrackpadTapResolution] {
        flushPending()
    }

    private mutating func startSequence(
        _ tap: TrackpadTap,
        availability: TrackpadTapAvailability
    ) -> [TrackpadTapResolution] {
        if availability.hasDouble {
            pending = Pending(tap: tap, availability: availability)
            return []
        }
        return availability.hasSingle ? [.single(tap)] : []
    }

    private mutating func expirePending(
        at timestamp: TimeInterval
    ) -> [TrackpadTapResolution] {
        guard let pending,
              timestamp - pending.tap.timestamp > doubleClickInterval
        else {
            return []
        }
        return flushPending()
    }

    private mutating func flushPending() -> [TrackpadTapResolution] {
        guard let pending else { return [] }
        self.pending = nil
        return pending.availability.hasSingle
            ? [.single(pending.tap)]
            : []
    }

    private func formsDouble(
        first: TrackpadTap,
        second: TrackpadTap
    ) -> Bool {
        guard first.deviceID == second.deviceID,
              first.fingers == second.fingers,
              second.beganAt >= first.timestamp,
              second.beganAt - first.timestamp <= doubleClickInterval
        else {
            return false
        }
        return hypot(
            second.centroid.x - first.centroid.x,
            second.centroid.y - first.centroid.y
        ) <= maximumCentroidDistance
    }

    private func isValid(timestamp: TimeInterval) -> Bool {
        timestamp.isFinite
            && (lastTimestamp.map { timestamp >= $0 } ?? true)
    }
}
