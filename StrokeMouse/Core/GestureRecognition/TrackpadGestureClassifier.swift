import CoreGraphics
import Foundation

struct TrackpadGestureClassifier {
    private static let geometryTolerance: CGFloat = 1e-6
    private static let timeTolerance: TimeInterval = 1e-9

    private struct Session {
        let startedAt: TimeInterval
        var stableSince: TimeInterval
        var ids: Set<Int>
        var baseline: [Int: CGPoint]
        var travelOrigins: [Int: CGPoint]
        var latest: [Int: CGPoint]
        var maximumTravel: [Int: CGFloat]
        var isLocked = false
    }

    private struct Ending {
        let session: Session
        let firstLiftAt: TimeInterval
    }

    private let policy: TrackpadRecognitionPolicy
    private var session: Session?
    private var ending: Ending?
    private var isDraining = false
    private var lastTimestamp: TimeInterval?
    private(set) var lastMetrics: TrackpadGestureMetrics?

    init(policy: TrackpadRecognitionPolicy = .init()) {
        self.policy = policy
    }

    mutating func process(_ frame: TrackpadTouchFrame) -> TrackpadClassifierEvent? {
        guard isValid(frame) else {
            session = nil
            ending = nil
            isDraining = !frame.contacts.isEmpty
            return .rejected(.invalidFrame)
        }
        lastTimestamp = frame.timestamp
        if frame.contacts.contains(where: { $0.phase == .cancelled }) {
            session = nil
            ending = nil
            isDraining = frame.contacts.contains(where: \.phase.isActive)
            return .rejected(.interrupted)
        }

        let active = Dictionary(
            uniqueKeysWithValues: frame.contacts
                .filter(\.phase.isActive)
                .map { ($0.id, $0.position) }
        )
        let reported = Dictionary(
            uniqueKeysWithValues: frame.contacts.map {
                ($0.id, $0.position)
            }
        )
        if isDraining {
            if active.isEmpty { isDraining = false }
            return nil
        }
        let activeStartedAt = ending?.session.startedAt
            ?? session?.startedAt
        if let activeStartedAt,
           frame.timestamp - activeStartedAt
               > policy.maximumGestureDuration + Self.timeTolerance
        {
            session = nil
            ending = nil
            isDraining = !active.isEmpty
            return .rejected(.durationExceeded)
        }
        if let ending {
            return processEnding(ending, frame: frame, active: active)
        }

        guard var current = session else {
            guard !active.isEmpty else { return nil }
            session = Session(
                startedAt: frame.timestamp,
                stableSince: frame.timestamp,
                ids: Set(active.keys),
                baseline: active,
                travelOrigins: active,
                latest: active,
                maximumTravel: Dictionary(
                    uniqueKeysWithValues: active.keys.map { ($0, 0) }
                )
            )
            return nil
        }

        if current.isLocked,
           !Set(reported.keys).isSubset(of: current.ids)
        {
            session = nil
            isDraining = !active.isEmpty
            return .rejected(.contactSetChanged)
        }
        updateKnownPositions(reported, in: &current)

        if active.isEmpty {
            session = nil
            isDraining = false
            guard current.isLocked else {
                return .rejected(.unsupported)
            }
            return classify(current, endedAt: frame.timestamp)
        }

        if !current.isLocked,
           frame.timestamp - current.startedAt
               > policy.formingTimeout + Self.timeTolerance
        {
            session = nil
            isDraining = true
            return .rejected(.formingTimedOut)
        }

        let ids = Set(active.keys)
        if current.isLocked {
            if ids.isStrictSubset(of: current.ids) {
                session = nil
                ending = Ending(session: current, firstLiftAt: frame.timestamp)
                return nil
            }
            guard ids == current.ids else {
                session = nil
                isDraining = true
                return .rejected(.contactSetChanged)
            }
        } else if ids != current.ids {
            guard frame.timestamp - current.startedAt
                <= policy.maximumLandingSpread + Self.timeTolerance
            else {
                session = nil
                isDraining = true
                return .rejected(.landingSpreadExceeded)
            }
            guard ids.isSuperset(of: current.ids) else {
                session = nil
                isDraining = true
                return .rejected(.contactSetChanged)
            }
            for (id, point) in active where current.travelOrigins[id] == nil {
                current.travelOrigins[id] = point
                current.maximumTravel[id] = 0
            }
            current.ids = ids
            current.baseline = active
            current.stableSince = frame.timestamp
        }

        updateKnownPositions(active, in: &current)
        if !current.isLocked,
           (2...5).contains(current.ids.count),
           frame.timestamp - current.stableSince + Self.timeTolerance
               >= policy.stableContactDuration
        {
            current.isLocked = true
        }
        session = current
        return nil
    }

    private func updateKnownPositions(
        _ positions: [Int: CGPoint],
        in session: inout Session
    ) {
        for (id, point) in positions {
            guard session.ids.contains(id),
                  let origin = session.travelOrigins[id]
            else {
                continue
            }
            session.latest[id] = point
            session.maximumTravel[id] = max(
                session.maximumTravel[id] ?? 0,
                hypot(point.x - origin.x, point.y - origin.y)
            )
        }
    }

    private mutating func processEnding(
        _ ending: Ending,
        frame: TrackpadTouchFrame,
        active: [Int: CGPoint]
    ) -> TrackpadClassifierEvent? {
        var updatedSession = ending.session
        let reported = Dictionary(
            uniqueKeysWithValues: frame.contacts.map {
                ($0.id, $0.position)
            }
        )
        let elapsed = frame.timestamp - ending.firstLiftAt
        guard elapsed
            <= policy.groupedReleaseDuration + Self.timeTolerance
        else {
            self.ending = nil
            isDraining = !active.isEmpty
            return .rejected(.releaseTimedOut)
        }
        guard Set(reported.keys).isSubset(of: updatedSession.ids) else {
            self.ending = nil
            isDraining = !active.isEmpty
            return .rejected(.contactSetChanged)
        }
        updateKnownPositions(reported, in: &updatedSession)
        guard active.isEmpty else {
            self.ending = Ending(
                session: updatedSession,
                firstLiftAt: ending.firstLiftAt
            )
            return nil
        }

        self.ending = nil
        return classify(updatedSession, endedAt: frame.timestamp)
    }

    private mutating func classify(
        _ session: Session,
        endedAt: TimeInterval
    ) -> TrackpadClassifierEvent {
        let fingers = session.ids.count
        guard (2...5).contains(fingers) else {
            return .rejected(.unsupported)
        }
        let start = centroid(session.baseline.values)
        let end = centroid(session.latest.values)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let primary = max(abs(dx), abs(dy))
        let secondary = min(abs(dx), abs(dy))
        let translationStrength = primary / policy.minimumSwipeDistance
        let startRadius = radius(points: session.baseline.values, centroid: start)
        let endRadius = radius(points: session.latest.values, centroid: end)
        let scale = startRadius > 0 ? endRadius / startRadius : 1
        let scaleStrength: CGFloat
        if startRadius >= policy.minimumBaselineRadius, scale > 0 {
            scaleStrength = abs(scale - 1) / policy.minimumScaleChange
        } else {
            scaleStrength = 0
        }
        let rotation = rotationAngle(
            baseline: session.baseline,
            latest: session.latest,
            startCentroid: start,
            endCentroid: end
        )
        let rotationStrength = abs(rotation) / policy.minimumRotationRadians
        let translationResidual = translationResidual(
            baseline: session.baseline,
            latest: session.latest,
            translation: CGPoint(x: dx, y: dy),
            magnitude: primary
        )
        let similarityResidual = similarityResidual(
            baseline: session.baseline,
            latest: session.latest,
            startCentroid: start,
            endCentroid: end,
            scale: scale,
            rotation: rotation,
            baselineRadius: startRadius
        )
        let strengths = [
            (kind: TransformKind.translation, value: translationStrength),
            (kind: TransformKind.scale, value: scaleStrength),
            (kind: TransformKind.rotation, value: rotationStrength),
        ].sorted { $0.value > $1.value }
        let ratio = strengths[1].value > 0
            ? strengths[0].value / strengths[1].value
            : nil
        lastMetrics = TrackpadGestureMetrics(
            fingerCount: fingers,
            duration: endedAt - session.startedAt,
            translationX: dx,
            translationY: dy,
            scale: scale,
            rotationRadians: rotation,
            strongestToSecondRatio: ratio
        )

        guard let strongest = strengths.first else {
            return .rejected(.unsupported)
        }
        if strongest.value < 1 - Self.geometryTolerance {
            if (3...5).contains(fingers),
               endedAt - session.startedAt
                   <= policy.maximumTapDuration + Self.timeTolerance,
               session.maximumTravel.values.allSatisfy({
                   $0 <= policy.maximumTapTravel + Self.geometryTolerance
               })
            {
                return .recognized(.tap(fingers: fingers))
            }
            return .rejected(.unsupported)
        }
        if strengths[1].value > 0,
           strongest.value + Self.geometryTolerance
               < strengths[1].value * policy.dominanceRatio
        {
            return .rejected(.ambiguous)
        }

        switch strongest.kind {
        case .scale:
            guard similarityResidual <= policy.maximumSimilarityResidual else {
                return .rejected(.unsupported)
            }
            let direction: TrackpadPinchDirection = scale > 1 ? .outward : .inward
            return .recognized(.pinch(fingers: fingers, direction: direction))
        case .rotation:
            guard similarityResidual <= policy.maximumSimilarityResidual else {
                return .rejected(.unsupported)
            }
            let direction: TrackpadRotationDirection =
                rotation < 0 ? .clockwise : .counterclockwise
            return .recognized(.rotate(fingers: fingers, direction: direction))
        case .translation:
            guard (3...5).contains(fingers),
                  secondary == 0
                    || primary / secondary + Self.geometryTolerance
                        >= policy.swipeAxisRatio,
                  translationResidual <= policy.maximumTranslationResidual
            else {
                return .rejected(.unsupported)
            }
        }

        let direction: TrackpadSwipeDirection
        if abs(dx) >= abs(dy) {
            direction = dx >= 0 ? .right : .left
        } else {
            direction = dy >= 0 ? .up : .down
        }
        return .recognized(.swipe(fingers: fingers, direction: direction))
    }

    private enum TransformKind {
        case translation
        case scale
        case rotation
    }

    private func centroid<S: Sequence>(_ points: S) -> CGPoint where S.Element == CGPoint {
        var total = CGPoint.zero
        var count: CGFloat = 0
        for point in points {
            total.x += point.x
            total.y += point.y
            count += 1
        }
        return CGPoint(x: total.x / count, y: total.y / count)
    }

    private func radius<S: Sequence>(
        points: S,
        centroid: CGPoint
    ) -> CGFloat where S.Element == CGPoint {
        var squaredDistance: CGFloat = 0
        var count: CGFloat = 0
        for point in points {
            let dx = point.x - centroid.x
            let dy = point.y - centroid.y
            squaredDistance += dx * dx + dy * dy
            count += 1
        }
        return sqrt(squaredDistance / count)
    }

    private func rotationAngle(
        baseline: [Int: CGPoint],
        latest: [Int: CGPoint],
        startCentroid: CGPoint,
        endCentroid: CGPoint
    ) -> CGFloat {
        var dot: CGFloat = 0
        var cross: CGFloat = 0
        for (id, start) in baseline {
            guard let end = latest[id] else { continue }
            let ax = start.x - startCentroid.x
            let ay = start.y - startCentroid.y
            let bx = end.x - endCentroid.x
            let by = end.y - endCentroid.y
            dot += ax * bx + ay * by
            cross += ax * by - ay * bx
        }
        return atan2(cross, dot)
    }

    private func translationResidual(
        baseline: [Int: CGPoint],
        latest: [Int: CGPoint],
        translation: CGPoint,
        magnitude: CGFloat
    ) -> CGFloat {
        guard magnitude > 0 else { return .infinity }
        var squaredError: CGFloat = 0
        var count: CGFloat = 0
        for (id, start) in baseline {
            guard let end = latest[id] else { continue }
            let errorX = (end.x - start.x) - translation.x
            let errorY = (end.y - start.y) - translation.y
            squaredError += errorX * errorX + errorY * errorY
            count += 1
        }
        guard count > 0 else { return .infinity }
        return sqrt(squaredError / count) / magnitude
    }

    private func similarityResidual(
        baseline: [Int: CGPoint],
        latest: [Int: CGPoint],
        startCentroid: CGPoint,
        endCentroid: CGPoint,
        scale: CGFloat,
        rotation: CGFloat,
        baselineRadius: CGFloat
    ) -> CGFloat {
        guard baselineRadius > 0 else { return .infinity }
        let cosine = cos(rotation)
        let sine = sin(rotation)
        var squaredError: CGFloat = 0
        var count: CGFloat = 0
        for (id, start) in baseline {
            guard let end = latest[id] else { continue }
            let x = start.x - startCentroid.x
            let y = start.y - startCentroid.y
            let predicted = CGPoint(
                x: endCentroid.x + scale * (x * cosine - y * sine),
                y: endCentroid.y + scale * (x * sine + y * cosine)
            )
            let errorX = end.x - predicted.x
            let errorY = end.y - predicted.y
            squaredError += errorX * errorX + errorY * errorY
            count += 1
        }
        guard count > 0 else { return .infinity }
        return sqrt(squaredError / count) / baselineRadius
    }

    private func isValid(_ frame: TrackpadTouchFrame) -> Bool {
        guard frame.timestamp.isFinite,
              lastTimestamp.map({ frame.timestamp >= $0 }) ?? true
        else {
            return false
        }
        var ids = Set<Int>()
        for contact in frame.contacts {
            guard contact.position.x.isFinite,
                  contact.position.y.isFinite,
                  ids.insert(contact.id).inserted
            else {
                return false
            }
        }
        return true
    }
}
