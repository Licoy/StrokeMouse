import CoreGraphics
import Foundation

enum TrackpadTouchPhase: Sendable {
    case began
    case moved
    case resting
    case ended
    case cancelled

    var isActive: Bool {
        switch self {
        case .began, .moved, .resting:
            return true
        case .ended, .cancelled:
            return false
        }
    }
}

struct TrackpadTouchContact: Equatable, Sendable {
    let id: Int
    let phase: TrackpadTouchPhase
    let position: CGPoint
}

struct TrackpadTouchFrame: Equatable, Sendable {
    let timestamp: TimeInterval
    let contacts: [TrackpadTouchContact]
}

enum TrackpadSwipeDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

enum TrackpadPinchDirection: Equatable, Sendable {
    case inward
    case outward
}

enum TrackpadRotationDirection: Equatable, Sendable {
    case clockwise
    case counterclockwise
}

enum TrackpadGestureClassification: Equatable, Sendable {
    case tap(fingers: Int)
    case swipe(fingers: Int, direction: TrackpadSwipeDirection)
    case pinch(fingers: Int, direction: TrackpadPinchDirection)
    case rotate(fingers: Int, direction: TrackpadRotationDirection)
}

enum TrackpadGestureRejection: Equatable, Sendable {
    case invalidFrame
    case interrupted
    case contactSetChanged
    case landingSpreadExceeded
    case formingTimedOut
    case releaseTimedOut
    case durationExceeded
    case unsupported
    case ambiguous
}

enum TrackpadClassifierEvent: Equatable, Sendable {
    case recognized(TrackpadGestureClassification)
    case rejected(TrackpadGestureRejection)
}

struct TrackpadGestureMetrics: Equatable, Sendable {
    let fingerCount: Int
    let duration: TimeInterval
    let translationX: CGFloat
    let translationY: CGFloat
    let scale: CGFloat
    let rotationRadians: CGFloat
    let strongestToSecondRatio: CGFloat?
}

struct TrackpadRecognitionPolicy: Equatable, Sendable {
    var stableContactDuration: TimeInterval = 0.060
    var formingTimeout: TimeInterval = 0.180
    var maximumLandingSpread: TimeInterval = 0.100
    var groupedReleaseDuration: TimeInterval = 0.120
    var maximumGestureDuration: TimeInterval = 2.0
    var maximumTapDuration: TimeInterval = 0.250
    var maximumTapTravel: CGFloat = 0.025
    var minimumSwipeDistance: CGFloat = 0.12
    var swipeAxisRatio: CGFloat = 1.5
    var minimumBaselineRadius: CGFloat = 0.03
    var minimumScaleChange: CGFloat = 0.18
    var minimumRotationRadians: CGFloat = .pi / 12
    var dominanceRatio: CGFloat = 1.30
    var maximumTranslationResidual: CGFloat = 0.45
    var maximumSimilarityResidual: CGFloat = 0.30
}
