import CoreGraphics
import Foundation

struct GestureMatchResult: Sendable {
    let profile: GestureProfile
    let score: Double
}

@MainActor
protocol GesturePermissionProviding: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func refresh()
}

extension PermissionManager: GesturePermissionProviding {}

protocol MouseGestureEventSource: AnyObject {
    var watchedButtons: Set<MouseTriggerButton> { get set }
    var onEvent: ((MouseEventTap.EventKind, UInt64) -> Void)? { get set }
    var shouldCapture: ((MouseTriggerButton) -> Bool)? { get set }
    var isActive: Bool { get }

    func start() -> Bool
    func stop()
    func isCurrentEventGeneration(_ generation: UInt64) -> Bool
    func replayClick(
        button: MouseTriggerButton,
        location: CGPoint
    ) -> Bool
}

extension MouseEventTap: MouseGestureEventSource {}

protocol ModifierGestureEventSource: AnyObject {
    var watchedKeys: Set<GestureModifierKey> { get set }
    var onEvent:
        (@Sendable (
            ModifierFlagsStateMachine.Event,
            CGPoint,
            UInt64
        ) -> Void)? {
            get set
        }
    var isActive: Bool { get }

    func start() -> Result<Void, ModifierEventTapError>
    func stop()
    func isCurrentEventGeneration(_ generation: UInt64) -> Bool
}

extension ModifierEventTap: ModifierGestureEventSource {}

struct GestureRuntimeConfiguration: Equatable, Sendable {
    var revision: UInt64
    var isEnabled: Bool
    var profiles: [GestureProfile]
    var minimumStrokeDistance: CGFloat
    var pathMatchThreshold: Double
    var showsHUD: Bool
    var directTrackpadEnabled: Bool
}

enum GestureRuntimeConfigurationError: Error, Equatable, Sendable {
    case duplicateProfileID(UUID)
    case invalidDrawnPath(UUID)
}

enum GestureRuntimeLifecycle: Equatable, Sendable {
    case stopped
    case awaitingAccessibility
    case listening
    case suppressed
    case degraded
}

enum GestureInputFailure: Equatable, Sendable {
    case accessibilityRequired
    case mouseEventTapCreationFailed
    case modifierEventTapCreationFailed
    case multitouchFrameworkUnavailable
    case multitouchSymbolMissing(String)
    case multitouchDeviceUnavailable
    case multitouchInvalidDimensions
    case multitouchInvalidFrame
    case multitouchStartFailed(String)
}

enum GestureInputChannelStatus: Equatable, Sendable {
    case notRequested
    case stopped
    case listening
    case failed(GestureInputFailure)
}

struct GestureRuntimeInputStatuses: Equatable, Sendable {
    var mouse: GestureInputChannelStatus = .notRequested
    var modifier: GestureInputChannelStatus = .notRequested
    var multitouch: GestureInputChannelStatus = .notRequested
}

struct GestureActiveSessionSummary: Equatable, Sendable {
    let source: GestureInputSource
    let configurationRevision: UInt64
    let candidateCount: Int
}

enum GestureRuntimeOutcome: Equatable, Sendable {
    case matched(profileID: UUID, score: Double?)
    case noMatch
    case conflict([UUID])
    case rejected(TrackpadGestureRejection)
    case cancelled
    case actionFailed(String)
}

struct GestureRuntimeState: Equatable, Sendable {
    var lifecycle: GestureRuntimeLifecycle = .stopped
    var inputs = GestureRuntimeInputStatuses()
    var activeSession: GestureActiveSessionSummary?
    var lastOutcome: GestureRuntimeOutcome?
    var configurationRevision: UInt64 = 0
}

enum GestureSuppressionReason: String, Hashable, Sendable {
    case gestureEditor
    case settings
    case userRequested
}

@MainActor
final class GestureCaptureSuppression {
    private var releaseHandler: (() -> Void)?

    init(release: @escaping () -> Void) {
        releaseHandler = release
    }

    func release() {
        let handler = releaseHandler
        releaseHandler = nil
        handler?()
    }

    deinit {
        MainActor.assumeIsolated {
            release()
        }
    }
}

@MainActor
final class GestureDiagnosticSession {
    private var releaseHandler: (() -> Void)?

    init(release: @escaping () -> Void) {
        releaseHandler = release
    }

    func end() {
        let handler = releaseHandler
        releaseHandler = nil
        handler?()
    }

    deinit {
        MainActor.assumeIsolated {
            end()
        }
    }
}

protocol MultitouchFrameSource: AnyObject {
    var isRunning: Bool { get }

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (
            MultitouchSupportAdapterError
        ) -> Void
    ) throws

    func stop()
    func clearFailure()
}

extension MultitouchFrameSource {
    func clearFailure() {}
}

extension MultitouchSupportAdapter: MultitouchFrameSource {}
