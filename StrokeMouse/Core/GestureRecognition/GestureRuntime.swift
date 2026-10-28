import AppKit
import CoreGraphics
import Foundation
import Observation

private final class MultitouchCallbackGeneration: @unchecked Sendable {
    enum StartDecision {
        case accepted(UInt64)
        case failed(GestureInputFailure)
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var failure: GestureInputFailure?

    func begin() -> StartDecision {
        lock.withLock {
            if let failure {
                return .failed(failure)
            }
            generation &+= 1
            return .accepted(generation)
        }
    }

    func invalidate() {
        lock.withLock {
            generation &+= 1
        }
    }

    func fail(
        _ expected: UInt64,
        with newFailure: GestureInputFailure
    ) -> UInt64? {
        lock.withLock {
            guard generation == expected else { return nil }
            failure = newFailure
            generation &+= 1
            return generation
        }
    }

    func isCurrent(_ expected: UInt64) -> Bool {
        lock.withLock { generation == expected }
    }

    var latchedFailure: GestureInputFailure? {
        lock.withLock { failure }
    }

    func clearFailure() {
        lock.withLock {
            failure = nil
        }
    }
}

private final class DrawCallbackGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var isEnabled = false

    func rotate(enabled: Bool) {
        lock.withLock {
            generation &+= 1
            isEnabled = enabled
        }
    }

    var token: UInt64? {
        lock.withLock { isEnabled ? generation : nil }
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.withLock { isEnabled && generation == token }
    }
}

/// Hands the target captured while deciding whether to swallow a mouse down
/// to the down edge that follows on the same tap thread, so AX runs once.
private final class PendingMouseCapture: @unchecked Sendable {
    struct Capture {
        let snapshot: GestureTargetSnapshot
        let heldModifiers: Set<GestureModifierKey>
    }

    private let lock = NSLock()
    private var admissionID: UInt64?
    private var capture: Capture?

    func store(_ capture: Capture, for admissionID: UInt64) {
        lock.withLock {
            self.admissionID = admissionID
            self.capture = capture
        }
    }

    func take(for admissionID: UInt64) -> Capture? {
        lock.withLock {
            defer {
                self.admissionID = nil
                capture = nil
            }
            return self.admissionID == admissionID ? capture : nil
        }
    }
}

@MainActor
@Observable
final class GestureRuntime {
    private enum SessionMode {
        case normal
        case diagnostic

        var executesActions: Bool { self == .normal }
        var showsToast: Bool { self == .normal }
    }

    private struct DrawSession {
        let source: GestureInputSource
        let revision: UInt64
        let targeted: [TargetedGesture]
        let preparedTemplates: [TemplateMatcher.PreparedPath]
        let clickQuartzLocation: CGPoint?
        let origin: CGPoint
        let recognitionPolicy: GestureRecognitionPolicy
        let showsHUD: Bool
        let showsLiveMismatchFeedback: Bool
        /// False when only button mappings can answer this press: the click
        /// runs the mapping however far the pointer moved.
        let tracksPath: Bool
        var mode: SessionMode
        var path: [CGPoint]
        var isDrawing: Bool
        var liveHysteresis: LiveGestureViability.Hysteresis
        var samplesSinceLiveEval: Int
        /// Sticky: one left click selects the secondary action at release.
        var chordClicked = false
        var combinationTriggered = false
        var combinationLeftClicked = false
        var wheelRepeatGate = MouseCombinationWheelRepeatGate()
        var dragScroll: MouseDragScrollSession?
        var dragScrollProfileID: UUID?
        var dragScrollClaimed = false
        var movementConflict = false
        var pendingMovementConflict: [UUID]?
        var dragScrollFailed = false
        var dragScrollHasPostedBegin = false
    }

    private struct DirectSession {
        let sequenceID: UInt64
        let revision: UInt64
        let profiles: [GestureProfile]
        let rules: GestureAppRules
        let snapshot: GestureTargetSnapshot
        let beganAt: TimeInterval
        var mode: SessionMode
        var classifier = TrackpadGestureClassifier()
        var centroid = CGPoint.zero
        var terminalEventReceived = false
        /// Sticky once the trackpad is pressed during this contact sequence.
        var physicallyPressed = false
    }

    private struct PendingTapContext {
        let profiles: [GestureProfile]
        let rules: GestureAppRules
        let snapshot: GestureTargetSnapshot
        let tap: TrackpadTap
        let mode: SessionMode
    }

    private(set) var state = GestureRuntimeState()
    private(set) var currentPath: [CGPoint] = []
    private(set) var currentTouches: [TrackpadTouchContact] = []
    private(set) var lastDrawDiagnostic: GestureDrawDiagnostic?
    private(set) var lastTrackpadMetrics: TrackpadGestureMetrics?
    private(set) var lastTrackpadOutcome: GestureRuntimeOutcome?
    private(set) var lastMatch: GestureMatchResult?
    private(set) var lastError: String?
    private(set) var isDrawing = false

    private let mouseEventTap: any MouseGestureEventSource
    private let modifierEventTap: any ModifierGestureEventSource
    private let trackpadClickEventTap: any TrackpadClickEventSource
    private let permissionManager: any GesturePermissionProviding
    private let actionExecutor: ActionExecutor
    private let targetCapturer: any GestureTargetCapturing
    private let pointerLocation: () -> CGPoint
    private let dragScrollPoster: ScrollEventPosting
    private let dragScrollEventFactory: (MouseDragScrollSession.Frame) -> CGEvent?
    private let wheelActionTime: () -> TimeInterval
    private let multitouchSourceFactory: () -> any MultitouchFrameSource
    private let inputCoreQueue: DispatchQueue
    private let sessionGate = GestureSessionGate()
    private let combinationEnvironment = MouseCombinationEnvironment()
    private let drawCallbackGeneration = DrawCallbackGeneration()
    private let multitouchAdmission = MultitouchSessionAdmission()
    private let pressArbiter = TrackpadPressArbiter()
    private let multitouchCallbackGeneration =
        MultitouchCallbackGeneration()
    private var multitouchSource: (any MultitouchFrameSource)?
    private var configuration = GestureRuntimeConfiguration(
        revision: 0,
        isEnabled: false,
        profiles: [],
        minimumStrokeDistance: Constants.defaultMinStrokeDistance,
        pathMatchThreshold: Constants.freePathMatchThreshold,
        showsHUD: true,
        showsLiveMismatchFeedback: false,
        directTrackpadEnabled: true
    )
    private var drawSession: DrawSession?
    private var edgeWheelRepeatGate = MouseCombinationWheelRepeatGate(interval: 0.1)
    private var edgeWheelRepeatProfiles: [UUID] = []
    private var directSession: DirectSession?
    private var ignoresDirectTouchesUntilEmpty = false
    private var sampleTimer: Timer?
    private var pendingTapTimer: Timer?
    private let tapDoubleClickInterval: TimeInterval
    private var tapResolver: TrackpadTapSequenceResolver
    private var pendingTapContext: PendingTapContext?
    private var pendingClickTimer: Timer?
    private var clickResolver: TrackpadTapSequenceResolver
    private var pendingClickContext: PendingTapContext?
    private var suppressionTokens = Set<UUID>()
    private var diagnosticTokens = Set<UUID>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var isSystemSleeping = false

    var onMatch: ((GestureMatchResult) -> Void)?

    init(
        permissionManager: any GesturePermissionProviding,
        actionExecutor: ActionExecutor,
        targetCapturer: (any GestureTargetCapturing)? = nil,
        mouseEventTap: any MouseGestureEventSource = MouseEventTap(),
        modifierEventTap: any ModifierGestureEventSource = ModifierEventTap(),
        trackpadClickEventTap: any TrackpadClickEventSource =
            TrackpadClickEventTap(),
        doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval,
        pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        wheelActionTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        dragScrollPoster: ScrollEventPosting = CGScrollEventPoster(),
        dragScrollEventFactory: @escaping (MouseDragScrollSession.Frame) -> CGEvent? = {
            CGScrollEventPoster.makeEvent(deltaY: $0.y, deltaX: $0.x, flags: [], phase: $0.phase)
        },
        multitouchSourceFactory: @escaping () -> any MultitouchFrameSource
    ) {
        let resolvedTargetCapturer =
            targetCapturer ?? MacGestureTargetCapturer()
        let inputCoreQueue = DispatchQueue(
            label: "com.strokemouse.app.gesture-runtime.input-core"
        )
        self.permissionManager = permissionManager
        self.actionExecutor = actionExecutor
        self.targetCapturer = resolvedTargetCapturer
        self.dragScrollPoster = dragScrollPoster
        self.dragScrollEventFactory = dragScrollEventFactory
        self.pointerLocation = pointerLocation
        self.wheelActionTime = wheelActionTime
        self.mouseEventTap = mouseEventTap
        self.modifierEventTap = modifierEventTap
        self.trackpadClickEventTap = trackpadClickEventTap
        self.multitouchSourceFactory = multitouchSourceFactory
        self.inputCoreQueue = inputCoreQueue
        let doubleClickInterval = max(0, doubleClickInterval)
        tapDoubleClickInterval = doubleClickInterval
        tapResolver = TrackpadTapSequenceResolver(
            doubleClickInterval: doubleClickInterval
        )
        clickResolver = TrackpadTapSequenceResolver(
            doubleClickInterval: doubleClickInterval
        )
        let drawCallbacks = drawCallbackGeneration
        let pendingMouseCapture = PendingMouseCapture()
        let combinationEnvironment = self.combinationEnvironment
        let wheelCaptureQueue = DispatchQueue(label: "com.strokemouse.app.gesture-runtime.wheel-target")
        // The target is resolved before the down edge is swallowed: when the
        // target application has no candidate for this button, the physical
        // down/up pair reaches it untouched (native drag / hold semantics).
        mouseEventTap.shouldCapture = {
            [weak sessionGate] button, location, flags in
            guard let callbackToken = drawCallbacks.token else {
                return .passThrough
            }
            return inputCoreQueue.sync {
                guard drawCallbacks.isCurrent(callbackToken),
                      let sessionGate,
                      let admission = sessionGate.claim(.mouse(button))
                else {
                    return .passThrough
                }
                let displays = combinationEnvironment.displays
                // Location is pure: a press that only edge combinations elsewhere
                // could use passes through before any Accessibility lookup.
                guard admission.context.isDiagnostic
                    || admission.context.configuration.profiles.contains(where: {
                        $0.isEnabled
                            && GestureInputMatcher.matches(source: .mouse(button), input: $0.input)
                            && Self.reachesPress($0.input, at: location, displays: displays)
                    })
                else {
                    sessionGate.release(admission)
                    return .passThrough
                }
                let heldModifiers = ModifierEventTap.supportedKeys(in: flags)
                let snapshot = Self.captureTargetSnapshot(
                    for: admission,
                    at: location,
                    heldModifiers: heldModifiers,
                    using: resolvedTargetCapturer
                )
                let targeted = Self.targetedCandidates(
                    for: admission,
                    snapshot: snapshot,
                    heldModifiers: heldModifiers
                ).filter { Self.reachesPress($0.profile.input, at: location, displays: displays) }
                guard admission.context.isDiagnostic || !targeted.isEmpty else {
                    sessionGate.release(admission)
                    return .passThrough
                }
                combinationEnvironment.held = button == .right ? targeted : []
                pendingMouseCapture.store(
                    .init(snapshot: snapshot, heldModifiers: heldModifiers),
                    for: admission.id
                )
                // Left clicks stay with the app unless a reachable gesture
                // can turn them into its secondary action.
                let allowsDrawSecondary: Bool
                if case .drawn = MouseDragScrollSelection.select(targeted) { allowsDrawSecondary = true }
                else { allowsDrawSecondary = false }
                return .capture(
                    acceptsChordClick: targeted.contains { item in
                        if allowsDrawSecondary && item.profile.acceptsChordClick { return true }
                        if case .mouseCombination(let combo) = item.profile.input {
                            return combo.needsHeldRight && combo.action == .leftClick
                        }
                        return false
                    }
                )
            }
        }
        mouseEventTap.shouldCaptureScroll = { [weak sessionGate] direction, location in
            guard let callbackToken = drawCallbacks.token,
                  drawCallbacks.isCurrent(callbackToken), let sessionGate else { return false }
            // Only locked value-state here; target capture runs on a separate queue.
            if sessionGate.activeSource == .mouse(.right) {
                guard !combinationEnvironment.dragOwnsMovement else { return false }
                return combinationEnvironment.held.contains { item in
                    guard case .mouseCombination(let combo) = item.profile.input else { return false }
                    return combo.needsHeldRight && combo.action.wheelDirection == direction
                }
            }
            // An edge tick is instantaneous: it never holds the session gate.
            // App scope is unknown until the target resolves, so any enabled
            // edge wheel here reserves the tick and an unmatched one is replayed.
            guard let admission = sessionGate.transientAdmission(.mouse(.right)) else { return false }
            return admission.context.configuration.profiles.contains { profile in
                guard profile.isEnabled, case .mouseCombination(let combo) = profile.input else { return false }
                return !combo.needsHeldRight && combo.action.wheelDirection == direction
                    && combo.accepts(location: location, displays: combinationEnvironment.displays)
            }
        }
        mouseEventTap.onEvent = {
            [weak self, weak sessionGate, weak mouseEventTap]
            event, sourceGeneration in
            guard let mouseEventTap else { return }
            if case .scroll(let direction, let location, let original) = event {
                // The tap already swallowed this tick. Every path below runs a
                // combination or replays the tick, so wheel input is never lost.
                guard mouseEventTap.isCurrentEventGeneration(sourceGeneration),
                      drawCallbacks.token != nil
                else {
                    // Post off the tap thread, in order with the other replays on main.
                    DispatchQueue.main.async { mouseEventTap.replayScroll(original) }
                    return
                }
                guard let wheelAdmission = sessionGate?.transientAdmission(.mouse(.right)) else {
                    // A held right button owns the session; its candidates are matched on main.
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.handleMouseEvent(event, admission: nil, snapshot: nil, heldModifiers: [])
                        }
                    }
                    return
                }
                wheelCaptureQueue.async { [weak self] in
                    let snapshot = Self.captureTargetSnapshot(
                        for: wheelAdmission, at: location, using: resolvedTargetCapturer
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.handleStandaloneWheel(
                            direction, location: location, original: original,
                            admission: wheelAdmission, snapshot: snapshot
                        )
                    }
                }
                return
            }
            guard mouseEventTap.isCurrentEventGeneration(sourceGeneration)
            else {
                return
            }
            guard let callbackToken = drawCallbacks.token else { return }
            inputCoreQueue.sync {
                guard drawCallbacks.isCurrent(callbackToken),
                      mouseEventTap.isCurrentEventGeneration(sourceGeneration)
                else {
                    return
                }
                let admission: GestureInputAdmission?
                let capture: PendingMouseCapture.Capture?
                switch event {
                case .buttonDown(let button, let location):
                    admission = sessionGate?.admission(
                        for: .mouse(button)
                    )
                    capture = admission.map {
                        pendingMouseCapture.take(for: $0.id)
                            ?? .init(
                                snapshot: Self.captureTargetSnapshot(
                                    for: $0,
                                    at: location,
                                    using: resolvedTargetCapturer
                                ),
                                heldModifiers: []
                            )
                    }
                case .buttonUp(let button, _):
                    combinationEnvironment.held = []
                    if let completed = sessionGate?.admission(
                        for: .mouse(button)
                    ) {
                        sessionGate?.release(completed)
                    }
                    admission = nil
                    capture = nil
                case .scroll, .chordClick:
                    admission = nil
                    capture = nil
                case .interrupted(let button, _):
                    combinationEnvironment.held = []
                    _ = sessionGate?.interrupt(.mouse(button))
                    admission = nil
                    capture = nil
                case .drained(let button):
                    _ = sessionGate?.completeDrain(.mouse(button))
                    admission = nil
                    capture = nil
                }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.handleMouseEvent(
                            event,
                            admission: admission,
                            snapshot: capture?.snapshot,
                            heldModifiers: capture?.heldModifiers ?? []
                        )
                    }
                }
            }
        }
        modifierEventTap.onEvent = {
            [weak self, weak sessionGate, weak modifierEventTap]
            event, quartzLocation, sourceGeneration in
            guard let modifierEventTap else { return }
            guard modifierEventTap.isCurrentEventGeneration(sourceGeneration)
            else {
                return
            }
            guard let callbackToken = drawCallbacks.token else { return }
            inputCoreQueue.sync {
                guard drawCallbacks.isCurrent(callbackToken),
                      modifierEventTap.isCurrentEventGeneration(
                          sourceGeneration
                      )
                else {
                    return
                }
                let admission: GestureInputAdmission?
                let snapshot: GestureTargetSnapshot?
                switch event {
                case .began(let key):
                    let claimed = sessionGate?.claim(.modifier(key))
                    let captured = claimed.map {
                        Self.captureTargetSnapshot(
                            for: $0,
                            at: quartzLocation,
                            using: resolvedTargetCapturer
                        )
                    }
                    if let claimed, let captured,
                       !Self.hasCandidates(claimed, snapshot: captured)
                    {
                        // Listen-only: nothing to release to the app, just
                        // skip the session (no HUD) and free the gate.
                        sessionGate?.release(claimed)
                        admission = nil
                        snapshot = nil
                    } else {
                        admission = claimed
                        snapshot = captured
                    }
                case .ended(let key):
                    if let completed = sessionGate?.admission(
                        for: .modifier(key)
                    ) {
                        sessionGate?.release(completed)
                    }
                    admission = nil
                    snapshot = nil
                case .drained(let key):
                    if let completed = sessionGate?.admission(
                        for: .modifier(key)
                    ) {
                        sessionGate?.release(completed)
                    } else {
                        _ = sessionGate?.completeDrain(.modifier(key))
                    }
                    admission = nil
                    snapshot = nil
                case .cancelled:
                    admission = nil
                    snapshot = nil
                case .interrupted(let key):
                    _ = sessionGate?.interrupt(.modifier(key))
                    admission = nil
                    snapshot = nil
                }
                if case .began = event, admission == nil { return }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.handleModifierEvent(
                            event,
                            quartzLocation: quartzLocation,
                            admission: admission,
                            snapshot: snapshot
                        )
                    }
                }
            }
        }
        let pressArbiter = pressArbiter
        trackpadClickEventTap.onPress = { [weak self] canSwallow in
            switch pressArbiter.press(canSwallow: canSwallow) {
            case .unrelated, .observed:
                return .passThrough
            case .click(let press):
                // Through the input queue, so the press reaches the main actor
                // after the frame that armed its sequence.
                inputCoreQueue.async {
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.handleTrackpadPress(press)
                        }
                    }
                }
                return .swallow
            }
        }
        publishAdmissionContext()
        installWorkspaceObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            finishDragScroll(cancelled: true)
            sampleTimer?.invalidate()
            pendingTapTimer?.invalidate()
            pendingClickTimer?.invalidate()
            mouseEventTap.onEvent = nil
            mouseEventTap.shouldCapture = nil
            mouseEventTap.shouldCaptureScroll = nil
            modifierEventTap.onEvent = nil
            trackpadClickEventTap.onPress = nil
            mouseEventTap.stop()
            modifierEventTap.stop()
            trackpadClickEventTap.stop()
            multitouchCallbackGeneration.invalidate()
            multitouchSource?.stop()
            if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
            let center = NSWorkspace.shared.notificationCenter
            for observer in workspaceObservers {
                center.removeObserver(observer)
            }
        }
    }

    var isEnabled: Bool { configuration.isEnabled }

    var isListening: Bool {
        state.inputs.mouse == .listening
            || state.inputs.modifier == .listening
            || state.inputs.multitouch == .listening
    }

    var matchThreshold: Double { configuration.pathMatchThreshold }

    var statusMessageKey: String {
        switch state.lifecycle {
        case .stopped: return configuration.isEnabled ? "engine.idle" : "engine.paused"
        case .awaitingAccessibility: return "engine.needPermission"
        case .listening: return "engine.listening"
        case .suppressed: return "engine.suppressed"
        case .degraded: return "engine.degraded"
        }
    }

    @discardableResult
    func apply(
        _ newConfiguration: GestureRuntimeConfiguration
    ) throws -> GestureRuntimeState {
        try Self.validate(newConfiguration)
        let candidate = normalized(newConfiguration)
        if configuration.isEnabled, !candidate.isEnabled {
            cancelDragScrollUntilRelease()
        }
        sessionGate.updateContext(admissionContext(for: candidate))
        configuration = candidate
        state.configurationRevision = configuration.revision
        // Do not write DrawingStyle.showHUD from configuration: apply() is also
        // used by tests / temporary runtime configs with showsHUD: false, and
        // the setter persists to UserDefaults — that would silently turn off the
        // user's "Show Gesture Trail" preference.
        reconcileChannels()
        return state
    }

    func suppress(
        reason: GestureSuppressionReason
    ) -> GestureCaptureSuppression {
        _ = reason
        let token = UUID()
        if suppressionTokens.isEmpty {
            resetPendingTapSequence()
            resetPendingClickSequence()
            downgradeActiveSessionToDiagnostics()
        }
        sessionGate.updateContext(admissionContext(
            for: configuration,
            isSuppressed: true
        ))
        suppressionTokens.insert(token)
        reconcileChannels()
        return GestureCaptureSuppression { [weak self] in
            self?.suppressionTokens.remove(token)
            self?.publishAdmissionContext()
            self?.reconcileChannels()
        }
    }

    func beginDiagnostics() -> GestureDiagnosticSession {
        let token = UUID()
        if diagnosticTokens.isEmpty {
            resetPendingTapSequence()
            resetPendingClickSequence()
            downgradeActiveSessionToDiagnostics()
        }
        sessionGate.updateContext(admissionContext(
            for: configuration,
            isDiagnostic: true
        ))
        diagnosticTokens.insert(token)
        currentTouches = []
        lastDrawDiagnostic = nil
        lastTrackpadMetrics = nil
        lastTrackpadOutcome = nil
        state.lastOutcome = nil
        reconcileChannels()
        return GestureDiagnosticSession { [weak self] in
            self?.diagnosticTokens.remove(token)
            self?.publishAdmissionContext()
            self?.reconcileChannels()
        }
    }

    func retryFailedInputs() {
        multitouchSource?.clearFailure()
        multitouchCallbackGeneration.clearFailure()
        if sessionGate.activeSource == nil {
            stopChannels()
        }
        reconcileChannels()
    }

    func accessibilityTrustDidChange(_ isTrusted: Bool) {
        guard !isTrusted else {
            sessionGate.enableDrawInputs()
            reconcileChannels()
            return
        }
        // Close admission before stopping either tap. Their threads can still
        // have an edge in flight while stop waits for the run loop to drain.
        drawCallbackGeneration.rotate(enabled: false)
        sessionGate.disableAndInvalidateDrawInputs()
        finishDragScroll(cancelled: true)
        combinationEnvironment.reset()
        stopSampling()
        drawSession = nil
        currentPath = []
        isDrawing = false
        if let source = state.activeSession?.source,
           source != .multitouch
        {
            state.activeSession = nil
        }
        GestureHUDController.shared.hide()
        mouseEventTap.stop()
        modifierEventTap.stop()
        trackpadClickEventTap.stop()
        let demand = inputDemand
        let shouldRequest = (configuration.isEnabled
            || !diagnosticTokens.isEmpty)
            && suppressionTokens.isEmpty
        state.inputs.mouse = demand.mouseButtons.isEmpty
            ? .notRequested
            : shouldRequest
                ? .failed(.accessibilityRequired)
                : .stopped
        state.inputs.modifier = demand.modifierKeys.isEmpty
            ? .notRequested
            : shouldRequest
                ? .failed(.accessibilityRequired)
                : .stopped
        state.inputs.trackpadClick = !demand.needsTrackpadClicks
            ? .notRequested
            : shouldRequest
                ? .failed(.accessibilityRequired)
                : .stopped
        updateLifecycle()
    }

    func evaluateForTesting(
        path: [CGPoint],
        button: MouseTriggerButton
    ) -> GestureRecognitionEvaluation {
        GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: configuration.profiles,
            button: button,
            policy: recognitionPolicy
        )
    }

    nonisolated static func shouldAcceptMatch(
        bestScore: Double,
        secondBestScore: Double?
    ) -> Bool {
        GestureRecognitionEvaluator.shouldAccept(
            bestScore: bestScore,
            secondBestScore: secondBestScore
        )
    }

    // MARK: - Configuration and lifecycle

    private static func validate(
        _ configuration: GestureRuntimeConfiguration
    ) throws {
        var ids = Set<UUID>()
        for profile in configuration.profiles {
            guard ids.insert(profile.id).inserted else {
                throw GestureRuntimeConfigurationError.duplicateProfileID(profile.id)
            }
            guard case .drawn(let drawn) = profile.input else { continue }
            guard drawn.allPaths.count <= DrawnGesture.maximumSampleCount,
                  drawn.allPaths.allSatisfy({ path in
                      path.count >= 2
                          && path.allSatisfy { $0.x.isFinite && $0.y.isFinite }
                          && zip(path, path.dropFirst()).contains { lhs, rhs in
                              lhs.x != rhs.x || lhs.y != rhs.y
                          }
                  })
            else {
                throw GestureRuntimeConfigurationError.invalidDrawnPath(profile.id)
            }
        }
    }

    private func normalized(
        _ configuration: GestureRuntimeConfiguration
    ) -> GestureRuntimeConfiguration {
        var result = configuration
        result.minimumStrokeDistance = max(0, configuration.minimumStrokeDistance)
        result.pathMatchThreshold =
            GestureRecognitionPolicy.normalizedMatchThreshold(
                configuration.pathMatchThreshold
            )
        return result
    }

    private func admissionContext(
        for configuration: GestureRuntimeConfiguration,
        isDiagnostic: Bool? = nil,
        isSuppressed: Bool? = nil
    ) -> GestureInputAdmissionContext {
        GestureInputAdmissionContext(
            configuration: configuration,
            isDiagnostic: isDiagnostic ?? !diagnosticTokens.isEmpty,
            isSuppressed: isSuppressed ?? !suppressionTokens.isEmpty
        )
    }

    private func publishAdmissionContext() {
        sessionGate.updateContext(admissionContext(for: configuration))
    }

    private func reconcileChannels() {
        let demand = inputDemand
        // An accepted physical sequence owns its adapter until every input is
        // released. Configuration changes are applied after that boundary.
        guard sessionGate.activeSource == nil else { return }

        mouseEventTap.watchedButtons = demand.mouseButtons
        mouseEventTap.interceptsChordClicks = demand.needsChordClicks
        refreshCombinationDisplays()
        mouseEventTap.interceptsScroll = configuration.profiles.contains {
            guard $0.isEnabled, case .mouseCombination(let combo) = $0.input else { return false }
            return combo.isValid && combo.action.wheelDirection != nil
        }
        modifierEventTap.watchedKeys = demand.modifierKeys
        trackpadClickEventTap.interceptsPresses =
            demand.interceptsTrackpadClicks

        guard configuration.isEnabled || !diagnosticTokens.isEmpty else {
            stopChannels()
            state.inputs = GestureRuntimeInputStatuses(
                mouse: demand.mouseButtons.isEmpty ? .notRequested : .stopped,
                modifier: demand.modifierKeys.isEmpty ? .notRequested : .stopped,
                multitouch: demand.needsMultitouch ? .stopped : .notRequested,
                trackpadClick: demand.needsTrackpadClicks
                    ? .stopped
                    : .notRequested
            )
            state.lifecycle = .stopped
            return
        }
        guard suppressionTokens.isEmpty else {
            stopChannels()
            state.inputs = GestureRuntimeInputStatuses(
                mouse: demand.mouseButtons.isEmpty ? .notRequested : .stopped,
                modifier: demand.modifierKeys.isEmpty ? .notRequested : .stopped,
                multitouch: demand.needsMultitouch ? .stopped : .notRequested,
                trackpadClick: demand.needsTrackpadClicks
                    ? .stopped
                    : .notRequested
            )
            state.lifecycle = .suppressed
            return
        }

        permissionManager.refresh()
        drawCallbackGeneration.rotate(
            enabled: permissionManager.isAccessibilityTrusted
                && (!demand.mouseButtons.isEmpty
                    || !demand.modifierKeys.isEmpty)
        )
        if permissionManager.isAccessibilityTrusted {
            sessionGate.enableDrawInputs()
        } else {
            sessionGate.disableAndInvalidateDrawInputs()
        }
        state.inputs.mouse = startMouseIfNeeded(demand.mouseButtons)
        state.inputs.modifier = startModifierIfNeeded(demand.modifierKeys)
        state.inputs.multitouch = isSystemSleeping
            ? (demand.needsMultitouch ? .stopped : .notRequested)
            : startMultitouchIfNeeded(demand.needsMultitouch)
        state.inputs.trackpadClick = startTrackpadClickIfNeeded(
            demand.needsTrackpadClicks
        )
        updateLifecycle()
    }

    private var inputDemand: (
        mouseButtons: Set<MouseTriggerButton>,
        needsChordClicks: Bool,
        modifierKeys: Set<GestureModifierKey>,
        needsMultitouch: Bool,
        needsTrackpadClicks: Bool,
        interceptsTrackpadClicks: Bool
    ) {
        var buttons = Set<MouseTriggerButton>()
        var chordClicks = false
        var modifiers = Set<GestureModifierKey>()
        var direct = false
        var directTaps = false
        var directClicks = false
        for profile in configuration.profiles where profile.isEnabled {
            chordClicks = chordClicks || profile.acceptsChordClick
            switch profile.input {
            case .drawn(let drawn):
                switch drawn.activation {
                case .mouse(let trigger):
                    buttons.insert(trigger.button)
                    if let key = drawn.trackpadModifierKey {
                        modifiers.insert(key)
                    }
                case .modifier(let key): modifiers.insert(key)
                }
            case .trackpad(let gesture):
                direct = true
                switch gesture {
                case .tap: directTaps = true
                case .click: directClicks = true
                case .swipe, .pinch, .rotate: break
                }
            case .mouseCombination(let combo):
                if combo.isValid {
                    buttons.insert(.right)
                    chordClicks = chordClicks || (combo.needsHeldRight && combo.action == .leftClick)
                }
            case .mouseButton(let gesture):
                if MouseButtonGesture.supportedButtons.contains(gesture.button) {
                    buttons.insert(gesture.button)
                }
            }
        }
        let isDiagnosing = !diagnosticTokens.isEmpty
        if isDiagnosing {
            modifiers.formUnion(GestureModifierKey.allCases)
        }
        let needsMultitouch = (direct || isDiagnosing)
            && configuration.directTrackpadEnabled
        // Taps alone only need presses observed, so a pressed sequence is not
        // mistaken for a tap; swallowing requires a reachable click gesture.
        return (
            buttons,
            chordClicks,
            modifiers,
            needsMultitouch,
            needsMultitouch && (directTaps || directClicks || isDiagnosing),
            directClicks || isDiagnosing
        )
    }

    private func startMouseIfNeeded(
        _ buttons: Set<MouseTriggerButton>
    ) -> GestureInputChannelStatus {
        guard !buttons.isEmpty else {
            mouseEventTap.stop()
            return .notRequested
        }
        guard permissionManager.isAccessibilityTrusted else {
            mouseEventTap.stop()
            return .failed(.accessibilityRequired)
        }
        return mouseEventTap.start()
            ? .listening
            : .failed(.mouseEventTapCreationFailed)
    }

    private func startModifierIfNeeded(
        _ keys: Set<GestureModifierKey>
    ) -> GestureInputChannelStatus {
        guard !keys.isEmpty else {
            modifierEventTap.stop()
            return .notRequested
        }
        guard permissionManager.isAccessibilityTrusted else {
            modifierEventTap.stop()
            return .failed(.accessibilityRequired)
        }
        switch modifierEventTap.start() {
        case .success:
            return .listening
        case .failure(.accessibilityPermissionRequired):
            return .failed(.accessibilityRequired)
        case .failure(.creationFailed):
            return .failed(.modifierEventTapCreationFailed)
        }
    }

    /// Presses only mean something while touch frames are flowing.
    private func startTrackpadClickIfNeeded(
        _ isNeeded: Bool
    ) -> GestureInputChannelStatus {
        guard isNeeded else {
            trackpadClickEventTap.stop()
            return .notRequested
        }
        guard state.inputs.multitouch == .listening else {
            trackpadClickEventTap.stop()
            return .stopped
        }
        guard permissionManager.isAccessibilityTrusted else {
            trackpadClickEventTap.stop()
            return .failed(.accessibilityRequired)
        }
        return trackpadClickEventTap.start()
            ? .listening
            : .failed(.trackpadClickTapCreationFailed)
    }

    private func startMultitouchIfNeeded(
        _ isNeeded: Bool
    ) -> GestureInputChannelStatus {
        guard isNeeded else {
            stopMultitouchInput()
            return .notRequested
        }
        if let failure = multitouchCallbackGeneration.latchedFailure {
            return .failed(failure)
        }
        let source = multitouchSource ?? multitouchSourceFactory()
        multitouchSource = source
        if source.isRunning {
            return .listening
        }
        let admissionController = multitouchAdmission
        let pressArbiter = pressArbiter
        let arbitrationGate = sessionGate
        let inputCoreQueue = inputCoreQueue
        let targetCapturer = targetCapturer
        let callbackGeneration = multitouchCallbackGeneration
        let callbackToken: UInt64
        switch callbackGeneration.begin() {
        case .accepted(let token):
            callbackToken = token
        case .failed(let failure):
            return .failed(failure)
        }
        do {
            try source.start(
                onFrame: { [weak self] frame in
                    guard callbackGeneration.isCurrent(callbackToken) else {
                        return
                    }
                    inputCoreQueue.sync {
                        guard callbackGeneration.isCurrent(callbackToken) else {
                            return
                        }
                        let admission = admissionController.process(
                            frame,
                            gate: arbitrationGate
                        )
                        // Before the target capture below, so a press during
                        // a slow capture still marks this sequence.
                        let pressed = pressArbiter.record(
                            frame,
                            sequenceID: admission.sequenceID
                        )
                        let pointerLocation =
                            CGEvent(source: nil)?.location ?? .zero
                        let snapshot =
                            admission.isBeginning
                            ? admission.admission.map {
                                Self.captureTargetSnapshot(
                                    for: $0,
                                    at: pointerLocation,
                                    using: targetCapturer
                                )
                            }
                            : nil
                        if let inputAdmission = admission.admission,
                           let snapshot
                        {
                            pressArbiter.arm(
                                sequenceID: admission.sequenceID,
                                fingerCounts: Self.clickFingerCounts(
                                    for: inputAdmission,
                                    snapshot: snapshot
                                )
                            )
                        }
                        DispatchQueue.main.async { [weak self] in
                            MainActor.assumeIsolated {
                                guard callbackGeneration.isCurrent(
                                    callbackToken
                                ) else {
                                    return
                                }
                                self?.handleTouchFrame(
                                    frame,
                                    admission: admission,
                                    targetSnapshot: snapshot,
                                    pressed: pressed
                                )
                            }
                        }
                    }
                },
                onFailure: { [weak self] error in
                    inputCoreQueue.sync {
                        let mappedFailure = Self.mapMultitouchError(error)
                        guard let failureGeneration =
                            callbackGeneration.fail(
                                callbackToken,
                                with: mappedFailure
                            )
                        else {
                            return
                        }
                        arbitrationGate.forceRelease(.multitouch)
                        admissionController.reset()
                        pressArbiter.reset()
                        DispatchQueue.main.async { [weak self] in
                            MainActor.assumeIsolated {
                                guard callbackGeneration.isCurrent(
                                    failureGeneration
                                ) else {
                                    return
                                }
                                self?.handleMultitouchFailure(error)
                            }
                        }
                    }
                }
            )
            return .listening
        } catch {
            let failure = Self.mapMultitouchError(error)
            _ = callbackGeneration.fail(callbackToken, with: failure)
            return .failed(failure)
        }
    }

    nonisolated private static func mapMultitouchError(
        _ error: Error
    ) -> GestureInputFailure {
        guard let error = error as? MultitouchSupportAdapterError else {
            return .multitouchStartFailed(String(describing: error))
        }
        switch error {
        case .frameworkUnavailable:
            return .multitouchFrameworkUnavailable
        case .missingSymbol(let symbol):
            return .multitouchSymbolMissing(symbol)
        case .deviceUnavailable:
            return .multitouchDeviceUnavailable
        case .invalidDimensions:
            return .multitouchInvalidDimensions
        case .invalidFrame:
            return .multitouchInvalidFrame
        case .startFailed, .resourceUnavailable:
            return .multitouchStartFailed(error.description)
        }
    }

    private func handleMultitouchFailure(
        _ error: MultitouchSupportAdapterError
    ) {
        stopMultitouchInput()
        let failure = Self.mapMultitouchError(error)
        state.inputs.multitouch = .failed(failure)
        directSession = nil
        ignoresDirectTouchesUntilEmpty = false
        currentTouches = []
        resetPendingTapSequence()
        resetPendingClickSequence()
        if state.activeSession?.source == .multitouch {
            state.activeSession = nil
        }
        reconcileChannels()
    }

    private func stopMultitouchInput() {
        multitouchCallbackGeneration.invalidate()
        multitouchSource?.stop()
        let arbitrationGate = sessionGate
        let admissionController = multitouchAdmission
        let pressArbiter = pressArbiter
        inputCoreQueue.async { [weak self] in
            let releasedOwner = arbitrationGate.forceRelease(.multitouch)
            let resetSequence = admissionController.reset()
            pressArbiter.reset()
            guard releasedOwner || resetSequence else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.reconcileChannels()
                }
            }
        }
    }

    private func updateLifecycle() {
        let channels = [
            state.inputs.mouse,
            state.inputs.modifier,
            state.inputs.multitouch,
            state.inputs.trackpadClick,
        ]
        let failures = channels.compactMap { channel -> GestureInputFailure? in
            guard case .failed(let failure) = channel else { return nil }
            return failure
        }
        if failures.isEmpty {
            state.lifecycle = channels.contains(.listening) ? .listening : .stopped
        } else if !channels.contains(.listening),
                  failures.allSatisfy({ $0 == .accessibilityRequired })
        {
            state.lifecycle = .awaitingAccessibility
        } else {
            state.lifecycle = .degraded
        }
    }

    private func stopChannels() {
        drawCallbackGeneration.rotate(enabled: false)
        mouseEventTap.stop()
        modifierEventTap.stop()
        trackpadClickEventTap.stop()
        stopMultitouchInput()
        cancelActiveSessions()
    }

    private func cancelActiveSessions() {
        edgeWheelRepeatGate = MouseCombinationWheelRepeatGate(interval: 0.1)
        edgeWheelRepeatProfiles = []
        finishDragScroll(cancelled: true)
        combinationEnvironment.reset()
        stopSampling()
        drawSession = nil
        directSession = nil
        ignoresDirectTouchesUntilEmpty = false
        currentPath = []
        currentTouches = []
        isDrawing = false
        state.activeSession = nil
        sessionGate.reset()
        GestureHUDController.shared.hide()
    }

    // MARK: - Drawn gestures

    private func handleMouseEvent(
        _ event: MouseEventTap.EventKind,
        admission: GestureInputAdmission?,
        snapshot: GestureTargetSnapshot?,
        heldModifiers: Set<GestureModifierKey>
    ) {
        switch event {
        case .buttonDown(let button, let quartzLocation):
            guard let admission else { return }
            beginDraw(
                source: .mouse(button),
                quartzLocation: quartzLocation,
                clickQuartzLocation: quartzLocation,
                admission: admission,
                snapshot: snapshot,
                heldModifiers: heldModifiers
            )
        case .buttonUp(let button, let quartzLocation):
            finishDraw(
                source: .mouse(button),
                quartzLocation: quartzLocation,
                wasCancelled: false
            )
        case .chordClick(let button):
            if button == .right, triggerHeldCombination(action: .leftClick) { return }
            registerChordClick(source: .mouse(button))
        case .scroll(let direction, _, let event):
            let preciseTimestamp: TimeInterval? = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
                ? (event.timestamp == 0 ? ProcessInfo.processInfo.systemUptime : Double(event.timestamp) / 1_000_000_000)
                : nil
            // The hold may have ended before this tick reached main: scroll natively.
            if !triggerHeldCombination(action: direction == .up ? .wheelUp : .wheelDown,
                                       preciseTimestamp: preciseTimestamp) {
                mouseEventTap.replayScroll(event)
            }
        case .interrupted(let button, let quartzLocation):
            finishDraw(
                source: .mouse(button),
                quartzLocation: quartzLocation,
                wasCancelled: true
            )
        case .drained:
            reconcileChannels()
        }
    }

    private func handleModifierEvent(
        _ event: ModifierFlagsStateMachine.Event,
        quartzLocation: CGPoint,
        admission: GestureInputAdmission?,
        snapshot: GestureTargetSnapshot?
    ) {
        switch event {
        case .began(let key):
            guard let admission else { return }
            beginDraw(
                source: .modifier(key),
                quartzLocation: quartzLocation,
                clickQuartzLocation: nil,
                admission: admission,
                snapshot: snapshot,
                heldModifiers: []
            )
        case .ended(let key):
            finishDraw(
                source: .modifier(key),
                quartzLocation: quartzLocation,
                wasCancelled: false
            )
        case .cancelled(let key):
            finishDraw(
                source: .modifier(key),
                quartzLocation: quartzLocation,
                wasCancelled: true
            )
        case .drained(let key):
            _ = key
            reconcileChannels()
        case .interrupted(let key):
            finishDraw(
                source: .modifier(key),
                quartzLocation: quartzLocation,
                wasCancelled: true
            )
        }
    }

    private func beginDraw(
        source: GestureInputSource,
        quartzLocation: CGPoint,
        clickQuartzLocation: CGPoint?,
        admission: GestureInputAdmission,
        snapshot: GestureTargetSnapshot?,
        heldModifiers: Set<GestureModifierKey>
    ) {
        guard admission.source == source,
              sessionGate.isValid(admission),
              drawSession == nil,
              let snapshot
        else {
            return
        }
        let frozenConfiguration = admission.context.configuration
        let targeted = Self.targetedCandidates(
            for: admission,
            snapshot: snapshot,
            heldModifiers: heldModifiers
        ).filter {
            Self.reachesPress(
                $0.profile.input,
                at: quartzLocation,
                displays: combinationEnvironment.displays
            )
        }
        let point = Self.appKitLocation(fromQuartz: quartzLocation)
        let mode: SessionMode = admission.context.isDiagnostic
            || !diagnosticTokens.isEmpty
            || !suppressionTokens.isEmpty
            ? .diagnostic
            : .normal
        if mode == .diagnostic {
            lastDrawDiagnostic = nil
        }
        let tracksPath = mode == .diagnostic || targeted.contains {
            if case .drawn = $0.profile.input { return true }
            return false
        }
        let preparedTemplates = targeted.flatMap { item -> [TemplateMatcher.PreparedPath] in
            guard case .drawn(let drawn) = item.profile.input else { return [] }
            let paths = drawn.allPaths.map { $0.map(\.cgPoint) }
            guard paths.allSatisfy({ $0.count >= 2 }) else { return [] }
            return GestureTemplateCache.shared.preparedPaths(
                id: item.profile.id,
                paths: paths
            )
        }
        drawSession = DrawSession(
            source: source,
            revision: frozenConfiguration.revision,
            targeted: targeted,
            preparedTemplates: preparedTemplates,
            clickQuartzLocation: clickQuartzLocation,
            origin: point,
            recognitionPolicy: recognitionPolicy(
                for: frozenConfiguration
            ),
            showsHUD: frozenConfiguration.showsHUD && mode == .normal,
            showsLiveMismatchFeedback: frozenConfiguration.showsLiveMismatchFeedback
                && frozenConfiguration.showsHUD
                && mode == .normal,
            tracksPath: tracksPath,
            mode: mode,
            path: [point],
            isDrawing: false,
            liveHysteresis: LiveGestureViability.Hysteresis(),
            samplesSinceLiveEval: 0
        )
        if source == .mouse(.right) {
            switch MouseDragScrollSelection.select(targeted) {
            case .drawn: break
            case .drag(let selected):
                if case .mouseCombination(let combo) = selected.profile.input {
                    drawSession?.dragScroll = MouseDragScrollSession(origin: point,
                        configuration: combo.resolvedDragScrollConfiguration)
                    drawSession?.dragScrollProfileID = selected.profile.id
                }
            case .conflict(let ids):
                drawSession?.pendingMovementConflict = ids
            }
        }
        currentPath = drawSession?.dragScroll == nil ? [point] : []
        state.activeSession = GestureActiveSessionSummary(
            source: source,
            configurationRevision: frozenConfiguration.revision,
            candidateCount: targeted.count
        )
        if tracksPath || drawSession?.dragScroll != nil || drawSession?.pendingMovementConflict != nil {
            startSampling()
        }
    }

    private func appendDrawSample(_ point: CGPoint) {
        guard var session = drawSession else { return }
        guard !session.movementConflict, !session.dragScrollFailed else { return }
        if let ids = session.pendingMovementConflict {
            guard !session.combinationTriggered,
                  hypot(point.x - session.origin.x, point.y - session.origin.y) >= MouseDragScrollSession.deadzone
            else { return }
            session.movementConflict = true
            session.combinationTriggered = true
            session.path = []
            drawSession = session
            currentPath = []
            stopSampling()
            recordOutcome(.conflict(ids), source: session.source)
            if session.mode.showsToast { GestureToastController.shared.showMovementConflict() }
            return
        }
        if var drag = session.dragScroll {
            guard !session.combinationTriggered || drag.isActive else { return }
            let frame = drag.sample(point)
            session.dragScroll = drag
            if drag.isActive {
                session.dragScrollClaimed = true
                session.combinationTriggered = true
                session.path = []
                combinationEnvironment.dragOwnsMovement = true
            }
            drawSession = session
            currentPath = []
            if let frame {
                if frame.phase == 1, let profileID = session.dragScrollProfileID,
                   let profile = session.targeted.first(where: { $0.profile.id == profileID })?.profile {
                    lastError = nil
                    let result = GestureMatchResult(profile: profile, score: 1, usesSecondaryAction: false)
                    lastMatch = result
                    recordOutcome(.matched(profileID: profileID, score: nil), source: session.source)
                    onMatch?(result)
                }
                postDragScroll(frame, mode: session.mode, source: session.source)
            }
            return
        }
        if let last = session.path.last,
           hypot(point.x - last.x, point.y - last.y) < 1.5
        {
            return
        }
        session.path.append(point)
        if hypot(point.x - session.origin.x, point.y - session.origin.y)
            >= session.recognitionPolicy.minimumPathLength
        {
            session.isDrawing = true
        }
        if session.showsLiveMismatchFeedback, session.isDrawing {
            session.samplesSinceLiveEval += 1
            let n = max(1, Constants.liveViabilityEvalEveryNSamples)
            if session.samplesSinceLiveEval == 1
                || session.samplesSinceLiveEval % n == 0
            {
                let observed = LiveGestureViability.evaluate(
                    path: session.path,
                    preparedTemplates: session.preparedTemplates,
                    minimumPathLength: session.recognitionPolicy.minimumPathLength,
                    matchThreshold: session.recognitionPolicy.matchThreshold
                )
                session.liveHysteresis = LiveGestureViability.applyHysteresis(
                    current: session.liveHysteresis,
                    observed: observed
                )
            }
        }
        drawSession = session
        currentPath = session.path
        isDrawing = session.isDrawing
        showDrawHUD(session)
    }

    private func showDrawHUD(_ session: DrawSession) {
        guard session.showsHUD,
              session.mode == .normal,
              session.path.count >= 2
        else {
            return
        }
        let showsMismatch = session.showsLiveMismatchFeedback
            && session.isDrawing
            && session.liveHysteresis.state == .unlikely
        GestureHUDController.shared.showPath(
            session.path,
            lineColorOverride: showsMismatch
                ? DrawingStyle.mismatchLineNSColor
                : nil,
            badge: session.chordClicked
                ? L10n.string("hud.secondaryActionBadge")
                : nil
        )
    }

    private func registerChordClick(source: GestureInputSource) {
        guard var session = drawSession,
              session.source == source,
              !session.chordClicked,
              !session.dragScrollClaimed, !session.dragScrollFailed,
              !session.movementConflict
        else {
            return
        }
        session.chordClicked = true
        drawSession = session
        showDrawHUD(session)
    }

    private func finishDraw(
        source: GestureInputSource,
        quartzLocation: CGPoint,
        wasCancelled: Bool
    ) {
        guard let session = drawSession, session.source == source else {
            reconcileChannels()
            return
        }
        if !wasCancelled,
           (session.tracksPath || session.dragScroll != nil || session.pendingMovementConflict != nil),
           !session.combinationTriggered || session.dragScroll?.isActive == true {
            appendDrawSample(Self.appKitLocation(fromQuartz: quartzLocation))
        }
        finishDragScroll(cancelled: wasCancelled)
        let finished = drawSession ?? session
        combinationEnvironment.dragOwnsMovement = false
        stopSampling()
        drawSession = nil
        currentPath = []
        isDrawing = false
        state.activeSession = nil
        GestureHUDController.shared.hide()

        defer { reconcileChannels() }
        guard !wasCancelled else {
            let outcome: GestureRuntimeOutcome = .cancelled
            state.lastOutcome = outcome
            publishDrawDiagnostic(
                session: finished,
                evaluation: nil,
                outcome: outcome
            )
            return
        }
        if finished.combinationTriggered {
            return
        }
        if !finished.isDrawing, performCombination(
            finished.targeted.filter {
                if case .mouseCombination(let combo) = $0.profile.input {
                    return !combo.needsHeldRight && combo.action == .rightClick
                        && combo.accepts(location: quartzLocation, displays: combinationEnvironment.displays)
                }
                return false
            }, mode: finished.mode, source: source
        ) { return }
        if finished.isDrawing || finished.mode == .diagnostic {
            recognizeDrawn(finished)
        } else if finished.chordClicked {
            // A chord is deliberate gesture input: replaying the trigger
            // click would open a context menu the user never asked for.
            state.lastOutcome = .cancelled
        } else if performButtonMapping(for: finished) {
            // The click became the mapped action instead of a native click.
        } else if case .mouse(let button) = source,
                  let clickLocation = finished.clickQuartzLocation,
                  !mouseEventTap.replayClick(
                    button: button,
                    location: clickLocation
                  )
        {
            lastError = "Failed to replay mouse click"
            state.lastOutcome = .actionFailed(lastError ?? "")
        }
    }

    private func postDragScroll(_ frame: MouseDragScrollSession.Frame,
                                mode: SessionMode, source: GestureInputSource) {
        guard mode.executesActions else { return }
        guard let event = dragScrollEventFactory(frame) else {
            let message = L10n.string("dragScroll.eventCreationFailed")
            lastError = message
            recordOutcome(.actionFailed(message), source: source)
            GestureToastController.shared.showActionError(message)
            // Stop sampling immediately; the release still owns the swallowed right press.
            stopSampling()
            drawSession?.dragScrollFailed = true
            if frame.phase == 2 {
                finishDragScroll(cancelled: true)
            } else if frame.phase == 1 {
                _ = drawSession?.dragScroll?.finish(cancelled: true)
            }
            return
        }
        dragScrollPoster.post(event)
        if frame.phase == 1 { drawSession?.dragScrollHasPostedBegin = true }
    }

    /// Pausing terminates continuous input immediately while retaining the
    /// swallowed physical press and its paired up until the adapter drains it.
    private func cancelDragScrollUntilRelease() {
        guard let session = drawSession,
              session.dragScroll != nil || session.pendingMovementConflict != nil else { return }
        finishDragScroll(cancelled: true)
        drawSession?.dragScrollClaimed = true
        drawSession?.combinationTriggered = true
        combinationEnvironment.dragOwnsMovement = true
        stopSampling()
        currentPath = []
        GestureHUDController.shared.hide()
        if drawSession?.dragScrollFailed != true {
            recordOutcome(.cancelled, source: session.source)
        }
    }

    private func finishDragScroll(cancelled: Bool) {
        guard var session = drawSession, var drag = session.dragScroll else { return }
        let frame = drag.finish(cancelled: cancelled)
        session.dragScroll = drag
        drawSession = session
        if let frame, session.dragScrollHasPostedBegin {
            postDragScroll(frame, mode: session.mode, source: session.source)
        }
    }

    /// Left clicks fire once per right-button hold; wheel ticks may repeat.
    private func triggerHeldCombination(action: MouseCombinationAction, preciseTimestamp: TimeInterval? = nil) -> Bool {
        guard var session = drawSession, session.source == .mouse(.right),
              !session.dragScrollClaimed, !session.dragScrollFailed, !session.movementConflict else { return false }
        let candidates = session.targeted.filter {
            guard case .mouseCombination(let combo) = $0.profile.input else { return false }
            return combo.needsHeldRight && combo.action == action
        }
        guard !candidates.isEmpty else { return false }
        if action == .leftClick, session.combinationLeftClicked { return true }
        if action == .leftClick { session.combinationLeftClicked = true }
        if !session.wheelRepeatGate.shouldExecute(action: action, preciseTimestamp: preciseTimestamp) {
            drawSession = session
            return true
        }
        session.combinationTriggered = true
        drawSession = session
        stopSampling()
        currentPath = []
        isDrawing = false
        GestureHUDController.shared.hide()
        return performCombination(candidates, mode: session.mode, source: session.source)
    }

    private func handleStandaloneWheel(
        _ direction: MouseWheelDirection, location: CGPoint, original: CGEvent,
        admission: GestureInputAdmission, snapshot: GestureTargetSnapshot
    ) {
        let candidates = Self.targetedCandidates(for: admission, snapshot: snapshot).filter {
            guard case .mouseCombination(let combo) = $0.profile.input else { return false }
            return !combo.needsHeldRight && combo.action.wheelDirection == direction
                && combo.accepts(location: location, displays: combinationEnvironment.displays)
        }
        guard sessionGate.isValid(admission), suppressionTokens.isEmpty, !candidates.isEmpty else {
            // No mapping in this app: replay the tick's deltas. The distinct
            // marker skips combination routing but still permits scroll enhancement.
            mouseEventTap.replayScroll(original)
            return
        }
        let profileIDs = candidates.map(\.profile.id)
        if profileIDs != edgeWheelRepeatProfiles {
            edgeWheelRepeatProfiles = profileIDs
            edgeWheelRepeatGate = MouseCombinationWheelRepeatGate(interval: 0.1)
        }
        // Use processing time rather than replayed event timestamps: a queue of
        // delayed frames must never turn into a sudden burst of media actions.
        guard edgeWheelRepeatGate.shouldExecute(
            action: direction == .up ? .wheelUp : .wheelDown,
            preciseTimestamp: wheelActionTime()
        ) else { return }
        _ = performCombination(candidates, mode: admission.context.isDiagnostic ? .diagnostic : .normal,
                               source: .mouse(.right))
    }

    @discardableResult
    private func performCombination(
        _ candidates: [TargetedGesture], mode: SessionMode, source: GestureInputSource
    ) -> Bool {
        guard let tier = candidates.map({ GestureScopeTier($0.profile.scope) }).min() else { return false }
        let preferred = candidates.filter { GestureScopeTier($0.profile.scope) == tier }
        if preferred.count == 1 {
            perform(preferred[0], action: preferred[0].profile.action, announcesMatch: false,
                    score: nil, mode: mode, source: source)
        } else {
            recordOutcome(.conflict(preferred.map(\.profile.id)), source: source)
            if mode.showsToast { GestureToastController.shared.showCombinationConflict() }
        }
        return true
    }

    /// Runs the button mapping for a press that never became a stroke. Only
    /// the most specific scope tier competes; several mappings there are a
    /// conflict and run nothing. Returns false when no mapping applies.
    private func performButtonMapping(for session: DrawSession) -> Bool {
        let mappings = Self.preferredButtonMappings(session.targeted)
        switch mappings.count {
        case 0:
            return false
        case 1:
            perform(
                mappings[0],
                action: mappings[0].profile.action,
                announcesMatch: false,
                score: nil,
                mode: session.mode,
                source: session.source
            )
        default:
            recordOutcome(
                .conflict(mappings.map(\.profile.id)),
                source: session.source
            )
            if session.mode.showsToast {
                GestureToastController.shared.showButtonMappingConflict()
            }
        }
        return true
    }

    nonisolated private static func preferredButtonMappings(
        _ targeted: [TargetedGesture]
    ) -> [TargetedGesture] {
        let mappings = targeted.filter {
            if case .mouseButton = $0.profile.input { return true }
            return false
        }
        let preferredTier = mappings.map {
            GestureScopeTier($0.profile.scope)
        }.min()
        return mappings.filter {
            GestureScopeTier($0.profile.scope) == preferredTier
        }
    }

    private func recognizeDrawn(_ session: DrawSession) {
        let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: session.path,
            profiles: session.targeted.map(\.profile),
            policy: session.recognitionPolicy
        )
        guard let accepted = evaluation.acceptedCandidate,
              let selected = session.targeted.first(where: {
                  $0.profile.id == accepted.profile.id
              })
        else {
            let outcome: GestureRuntimeOutcome = .noMatch
            state.lastOutcome = outcome
            publishDrawDiagnostic(
                session: session,
                evaluation: evaluation,
                outcome: outcome
            )
            if session.mode.showsToast {
                if evaluation.decision == .tooShort {
                    GestureToastController.shared.showTooShort()
                } else {
                    GestureToastController.shared.showNoMatch()
                }
            }
            return
        }
        // Every candidate competes in both cases so a path always resolves
        // to the same gesture; the chord only chooses which action runs.
        let action: GestureAction
        if session.chordClicked {
            guard let secondaryAction = selected.profile.secondaryAction else {
                let outcome: GestureRuntimeOutcome =
                    .secondaryActionUnavailable(profileID: selected.profile.id)
                state.lastOutcome = outcome
                publishDrawDiagnostic(
                    session: session,
                    evaluation: evaluation,
                    outcome: outcome
                )
                if session.mode.showsToast {
                    GestureToastController.shared.showSecondaryActionMissing(
                        name: selected.profile.name
                    )
                }
                return
            }
            action = secondaryAction
        } else {
            action = selected.profile.action
        }
        perform(
            selected,
            action: action,
            usesSecondaryAction: session.chordClicked,
            score: accepted.score,
            mode: session.mode,
            source: session.source
        )
        publishDrawDiagnostic(
            session: session,
            evaluation: evaluation,
            outcome: .matched(
                profileID: selected.profile.id,
                score: accepted.score
            )
        )
    }

    private func publishDrawDiagnostic(
        session: DrawSession,
        evaluation: GestureRecognitionEvaluation?,
        outcome: GestureRuntimeOutcome
    ) {
        guard session.mode == .diagnostic else { return }
        lastDrawDiagnostic = GestureDrawDiagnostic(
            source: session.source,
            path: session.path,
            evaluation: evaluation,
            outcome: outcome,
            configurationRevision: session.revision,
            chordClicked: session.chordClicked
        )
    }

    /// Whether a mouse press at this location can reach the input. Only
    /// combinations depend on location; every other input keeps its source match.
    nonisolated private static func reachesPress(
        _ input: GestureInput,
        at quartzLocation: CGPoint,
        displays: [CGRect]
    ) -> Bool {
        guard case .mouseCombination(let combo) = input else { return true }
        return combo.acceptsRightPress(at: quartzLocation, displays: displays)
    }

    /// Candidates for the admission's source after app scope, app groups and
    /// per-application global suppression are applied to the frozen target.
    /// `heldModifiers` are the modifiers down with a mouse press; only button
    /// mappings consult them.
    nonisolated private static func targetedCandidates(
        for admission: GestureInputAdmission,
        snapshot: GestureTargetSnapshot,
        heldModifiers: Set<GestureModifierKey> = []
    ) -> [TargetedGesture] {
        let configuration = admission.context.configuration
        let profiles = configuration.profiles.filter { profile in
            guard profile.isEnabled,
                  GestureInputMatcher.matches(
                      source: admission.source,
                      input: profile.input
                  )
            else {
                return false
            }
            guard case .mouseButton(let gesture) = profile.input else {
                return true
            }
            return gesture.accepts(heldModifiers: heldModifiers)
        }
        return GestureCandidateSelector.prepare(
            profiles: profiles,
            snapshot: snapshot,
            inputKind: admission.source.inputKind,
            rules: configuration.appRules
        )
    }

    /// Diagnostics always record; otherwise a session only starts when the
    /// target application can match at least one gesture.
    nonisolated private static func hasCandidates(
        _ admission: GestureInputAdmission,
        snapshot: GestureTargetSnapshot,
        heldModifiers: Set<GestureModifierKey> = []
    ) -> Bool {
        admission.context.isDiagnostic
            || !targetedCandidates(
                for: admission,
                snapshot: snapshot,
                heldModifiers: heldModifiers
            ).isEmpty
    }

    /// Finger counts whose press this target turns into a click gesture.
    /// Diagnostics arm every count so an unconfigured press still reports.
    nonisolated private static func clickFingerCounts(
        for admission: GestureInputAdmission,
        snapshot: GestureTargetSnapshot
    ) -> Set<Int> {
        guard !admission.context.isDiagnostic else {
            return Set(StandardFingerCount.allCases.map(\.rawValue))
        }
        return Set(
            targetedCandidates(for: admission, snapshot: snapshot)
                .compactMap { targeted in
                    guard case .trackpad(.click(let fingers, _)) =
                        targeted.profile.input
                    else {
                        return nil
                    }
                    return fingers.rawValue
                }
        )
    }

    nonisolated private static func captureTargetSnapshot(
        for admission: GestureInputAdmission,
        at quartzLocation: CGPoint,
        heldModifiers: Set<GestureModifierKey> = [],
        using capturer: any GestureTargetCapturing
    ) -> GestureTargetSnapshot {
        let profiles = admission.context.configuration.profiles.filter {
            profile in
            guard profile.isEnabled else { return false }
            return GestureInputMatcher.matches(
                source: admission.source,
                input: profile.input
            )
        }
        let policies = Set(profiles.map(\.targetPolicy))
        if let identifying = capturer as? any GestureTargetIdentifying {
            let identity = identifying.captureIdentity(
                policies: policies,
                at: quartzLocation
            )
            // No candidate: keep the physical event, and do not copy an AX window.
            guard Self.hasCandidates(
                admission,
                snapshot: identity,
                heldModifiers: heldModifiers
            ) else {
                return identity
            }
        }
        return capturer.capture(policies: policies, at: quartzLocation)
    }

    private func startSampling() {
        stopSampling()
        let timer = Timer(timeInterval: 1 / 120, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.appendDrawSample(self.pointerLocation())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    // MARK: - Direct trackpad gestures

    private func handleTouchFrame(
        _ frame: TrackpadTouchFrame,
        admission: MultitouchAdmission,
        targetSnapshot: GestureTargetSnapshot?,
        pressed: Bool
    ) {
        currentTouches = frame.contacts
        let activeContacts = frame.contacts.filter(\.phase.isActive)
        if ignoresDirectTouchesUntilEmpty {
            if activeContacts.isEmpty {
                ignoresDirectTouchesUntilEmpty = false
                completeMultitouchSequence(admission)
            }
            return
        }
        if directSession == nil {
            guard !activeContacts.isEmpty else { return }
            guard let inputAdmission = admission.admission else {
                ignoresDirectTouchesUntilEmpty = true
                return
            }
            beginDirectSession(
                frame: frame,
                sequenceID: admission.sequenceID,
                contacts: activeContacts,
                admission: inputAdmission,
                snapshot: targetSnapshot
            )
        }
        guard var session = directSession else { return }
        if pressed {
            session.physicallyPressed = true
        }
        if !activeContacts.isEmpty {
            session.centroid = Self.centroid(activeContacts.map(\.position))
        }
        let event = session.classifier.process(frame)
        if let metrics = session.classifier.lastMetrics {
            lastTrackpadMetrics = metrics
        }
        if let event, !session.terminalEventReceived {
            session.terminalEventReceived = true
            switch event {
            case .recognized where session.physicallyPressed:
                // A pressed sequence is a click or an app drag, never a
                // touch gesture.
                interruptPendingTapSequence()
                recordOutcome(
                    .rejected(.physicallyPressed),
                    source: .multitouch
                )
            case .recognized(let classification):
                interruptPendingClickSequence()
                if !classification.isTap {
                    interruptPendingTapSequence()
                }
                handleDirectRecognition(
                    classification,
                    session: session,
                    timestamp: frame.timestamp
                )
            case .rejected(let reason):
                interruptPendingTapSequence()
                recordOutcome(.rejected(reason), source: .multitouch)
            }
        }
        directSession = session

        if activeContacts.isEmpty {
            if !session.terminalEventReceived,
               pendingTapContext != nil,
               pendingTapTimer == nil
            {
                interruptPendingTapSequence()
            }
            directSession = nil
            currentTouches = []
            state.activeSession = nil
            completeMultitouchSequence(admission)
        }
    }

    private func completeMultitouchSequence(
        _ admission: MultitouchAdmission
    ) {
        guard admission.isAccepted else {
            reconcileChannels()
            return
        }
        reconcileChannels()
    }

    private func beginDirectSession(
        frame: TrackpadTouchFrame,
        sequenceID: UInt64,
        contacts: [TrackpadTouchContact],
        admission: GestureInputAdmission,
        snapshot: GestureTargetSnapshot?
    ) {
        guard sessionGate.isValid(admission) else {
            ignoresDirectTouchesUntilEmpty = true
            return
        }
        guard let snapshot else {
            ignoresDirectTouchesUntilEmpty = true
            recordOutcome(.rejected(.invalidFrame), source: .multitouch)
            return
        }
        let frozenConfiguration = admission.context.configuration
        let profiles = frozenConfiguration.profiles.filter {
            guard $0.isEnabled, case .trackpad = $0.input else { return false }
            return true
        }
        let mode: SessionMode = admission.context.isDiagnostic
            || !diagnosticTokens.isEmpty
            || !suppressionTokens.isEmpty
            ? .diagnostic
            : .normal
        if mode == .normal,
           !Self.hasCandidates(admission, snapshot: snapshot)
        {
            // Nothing can fire in this application: free the gate for other
            // sources and ignore the rest of this contact sequence.
            sessionGate.release(admission)
            ignoresDirectTouchesUntilEmpty = true
            return
        }
        preparePendingTapForContactSequence(startedAt: frame.timestamp)
        directSession = DirectSession(
            sequenceID: sequenceID,
            revision: frozenConfiguration.revision,
            profiles: profiles,
            rules: frozenConfiguration.appRules,
            snapshot: snapshot,
            beganAt: frame.timestamp,
            mode: mode,
            centroid: Self.centroid(contacts.map(\.position))
        )
        state.activeSession = GestureActiveSessionSummary(
            source: .multitouch,
            configurationRevision: frozenConfiguration.revision,
            candidateCount: profiles.count
        )
        _ = frame
    }

    private func handleDirectRecognition(
        _ classification: TrackpadGestureClassification,
        session: DirectSession,
        timestamp: TimeInterval
    ) {
        switch classification {
        case .tap(let fingers):
            handleRawTap(
                fingers: fingers,
                centroid: session.centroid,
                beganAt: session.beganAt,
                timestamp: timestamp,
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot,
                mode: session.mode
            )
        case .swipe(let fingers, let direction):
            guard let count = StandardFingerCount(rawValue: fingers) else {
                recordOutcome(.noMatch, source: .multitouch)
                return
            }
            executeDirect(
                .swipe(count, direction.modelValue),
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot,
                mode: session.mode
            )
        case .pinch(let fingers, let direction):
            guard let count = TransformFingerCount(rawValue: fingers) else {
                recordOutcome(.noMatch, source: .multitouch)
                return
            }
            executeDirect(
                .pinch(count, direction.modelValue),
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot,
                mode: session.mode
            )
        case .rotate(let fingers, let direction):
            guard let count = TransformFingerCount(rawValue: fingers) else {
                recordOutcome(.noMatch, source: .multitouch)
                return
            }
            executeDirect(
                .rotate(count, direction.modelValue),
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot,
                mode: session.mode
            )
        }
    }

    private func handleRawTap(
        fingers: Int,
        centroid: CGPoint,
        beganAt sessionBeganAt: TimeInterval,
        timestamp: TimeInterval,
        profiles: [GestureProfile],
        rules: GestureAppRules,
        snapshot: GestureTargetSnapshot,
        mode: SessionMode
    ) {
        guard let count = StandardFingerCount(rawValue: fingers) else {
            interruptPendingTapSequence()
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        let availability = TrackpadTapAvailability(
            hasSingle: hasDirectMatch(
                .tap(count, .single),
                profiles: profiles,
                rules: rules,
                snapshot: snapshot
            ),
            hasDouble: hasDirectMatch(
                .tap(count, .double),
                profiles: profiles,
                rules: rules,
                snapshot: snapshot
            )
        )
        guard availability.hasSingle || availability.hasDouble else {
            interruptPendingTapSequence()
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        let current = PendingTapContext(
            profiles: profiles,
            rules: rules,
            snapshot: snapshot,
            tap: TrackpadTap(
                deviceID: 0,
                fingers: fingers,
                centroid: centroid,
                beganAt: sessionBeganAt,
                timestamp: timestamp
            ),
            mode: mode
        )
        let previous = pendingTapContext
        let resolutions = tapResolver.register(
            current.tap,
            availability: availability
        )
        if resolutions.contains(.invalidTimestamp) {
            interruptPendingTapSequence()
            recordOutcome(
                .rejected(.invalidFrame),
                source: .multitouch
            )
            return
        }
        var completedDouble = false
        for resolution in resolutions {
            switch resolution {
            case .single(let tap):
                guard let context = tapContext(
                    for: tap,
                    previous: previous,
                    current: current
                ) else {
                    continue
                }
                executeTap(.single, context: context)
            case .double(let first, _):
                completedDouble = true
                guard let context = tapContext(
                    for: first,
                    previous: previous,
                    current: current
                ) else {
                    continue
                }
                executeTap(.double, context: context)
            case .invalidTimestamp:
                break
            }
        }

        if completedDouble {
            pendingTapContext = nil
        } else if availability.hasDouble {
            pendingTapContext = current
        } else {
            pendingTapContext = nil
        }
        schedulePendingTapDeadline()
    }

    private func preparePendingTapForContactSequence(
        startedAt timestamp: TimeInterval
    ) {
        guard let context = pendingTapContext else { return }
        guard timestamp.isFinite,
              timestamp >= context.tap.timestamp
        else {
            interruptPendingTapSequence()
            return
        }
        let deadline = context.tap.timestamp + tapDoubleClickInterval
        if timestamp <= deadline {
            // A possible second tap owns the deadline until its classification
            // completes. Its contact-down time, not its lift time, determines
            // whether it belongs to the double-tap window.
            pendingTapTimer?.invalidate()
            pendingTapTimer = nil
        } else {
            resolvePendingTap(at: timestamp)
        }
    }

    private func schedulePendingTapDeadline() {
        pendingTapTimer?.invalidate()
        pendingTapTimer = nil
        guard let pendingTapContext else { return }
        let interval = tapDoubleClickInterval
        let deadline = pendingTapContext.tap.timestamp + interval + 0.001
        let timer = Timer(timeInterval: interval + 0.001, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingTapTimer = nil
                guard self.directSession == nil else { return }
                self.resolvePendingTap(at: deadline)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingTapTimer = timer
    }

    private func interruptPendingTapSequence() {
        let context = pendingTapContext
        let resolutions = tapResolver.interrupt()
        pendingTapContext = nil
        pendingTapTimer?.invalidate()
        pendingTapTimer = nil
        guard let context else { return }
        if resolutions.contains(where: {
            if case .single(let tap) = $0 {
                return tap == context.tap
            }
            return false
        }) {
            executeTap(.single, context: context)
        }
    }

    private func resetPendingTapSequence() {
        pendingTapTimer?.invalidate()
        pendingTapTimer = nil
        pendingTapContext = nil
        tapResolver = TrackpadTapSequenceResolver(
            doubleClickInterval: tapDoubleClickInterval
        )
    }

    private func downgradeActiveSessionToDiagnostics() {
        if var session = drawSession {
            finishDragScroll(cancelled: true)
            session = drawSession ?? session
            session.mode = .diagnostic
            drawSession = session
            GestureHUDController.shared.hide()
        }
        if var session = directSession {
            session.mode = .diagnostic
            directSession = session
        }
    }

    private func resolvePendingTap(at timestamp: TimeInterval) {
        guard let context = pendingTapContext else { return }
        let resolutions = tapResolver.advance(to: timestamp)
        if resolutions.contains(.invalidTimestamp) {
            interruptPendingTapSequence()
            recordOutcome(.rejected(.invalidFrame), source: .multitouch)
            return
        }
        pendingTapContext = nil
        pendingTapTimer?.invalidate()
        pendingTapTimer = nil
        guard resolutions.contains(where: {
            if case .single(let tap) = $0 {
                return tap == context.tap
            }
            return false
        }) else {
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        executeTap(.single, context: context)
    }

    private func executeTap(
        _ tapCount: TapCount,
        context: PendingTapContext,
        isClick: Bool = false
    ) {
        guard let count = StandardFingerCount(
            rawValue: context.tap.fingers
        ) else {
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        executeDirect(
            isClick ? .click(count, tapCount) : .tap(count, tapCount),
            profiles: context.profiles,
            rules: context.rules,
            snapshot: context.snapshot,
            mode: context.mode
        )
    }

    // MARK: - Physical clicks

    /// Runs at the press itself: the down edge has already been swallowed.
    private func handleTrackpadPress(_ press: TrackpadPress) {
        guard var session = directSession,
              session.sequenceID == press.sequenceID
        else {
            return
        }
        // The press owns this sequence: lifting the fingers afterwards must
        // not also produce a tap or a swipe.
        session.physicallyPressed = true
        session.terminalEventReceived = true
        directSession = session
        interruptPendingTapSequence()
        guard let count = StandardFingerCount(rawValue: press.fingers) else {
            interruptPendingClickSequence()
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        let availability = TrackpadTapAvailability(
            hasSingle: hasDirectMatch(
                .click(count, .single),
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot
            ),
            hasDouble: hasDirectMatch(
                .click(count, .double),
                profiles: session.profiles,
                rules: session.rules,
                snapshot: session.snapshot
            )
        )
        guard availability.hasSingle || availability.hasDouble else {
            interruptPendingClickSequence()
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        // Main-actor time keeps every click timestamp monotonic with the
        // deadline timer, which also runs here.
        let current = PendingTapContext(
            profiles: session.profiles,
            rules: session.rules,
            snapshot: session.snapshot,
            tap: TrackpadTap(
                deviceID: 0,
                fingers: press.fingers,
                centroid: press.centroid,
                timestamp: ProcessInfo.processInfo.systemUptime
            ),
            mode: session.mode
        )
        let previous = pendingClickContext
        let resolutions = clickResolver.register(
            current.tap,
            availability: availability
        )
        if resolutions.contains(.invalidTimestamp) {
            interruptPendingClickSequence()
            recordOutcome(.rejected(.invalidFrame), source: .multitouch)
            return
        }
        var completedDouble = false
        for resolution in resolutions {
            switch resolution {
            case .single(let tap):
                guard let context = tapContext(
                    for: tap,
                    previous: previous,
                    current: current
                ) else {
                    continue
                }
                executeTap(.single, context: context, isClick: true)
            case .double(let first, _):
                completedDouble = true
                guard let context = tapContext(
                    for: first,
                    previous: previous,
                    current: current
                ) else {
                    continue
                }
                executeTap(.double, context: context, isClick: true)
            case .invalidTimestamp:
                break
            }
        }
        pendingClickContext = !completedDouble && availability.hasDouble
            ? current
            : nil
        schedulePendingClickDeadline()
    }

    /// Unlike a tap, a second click arrives at its press, so the deadline is
    /// never deferred by a contact sequence in progress.
    private func schedulePendingClickDeadline() {
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
        guard pendingClickContext != nil else { return }
        let timer = Timer(
            timeInterval: tapDoubleClickInterval + 0.001,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingClickTimer = nil
                self.resolvePendingClick(
                    at: ProcessInfo.processInfo.systemUptime
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingClickTimer = timer
    }

    private func resolvePendingClick(at timestamp: TimeInterval) {
        guard let context = pendingClickContext else { return }
        let resolutions = clickResolver.advance(to: timestamp)
        if resolutions.contains(.invalidTimestamp) {
            interruptPendingClickSequence()
            recordOutcome(.rejected(.invalidFrame), source: .multitouch)
            return
        }
        pendingClickContext = nil
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
        guard resolutions.contains(.single(context.tap)) else {
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        executeTap(.single, context: context, isClick: true)
    }

    private func interruptPendingClickSequence() {
        let context = pendingClickContext
        let resolutions = clickResolver.interrupt()
        pendingClickContext = nil
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
        guard let context,
              resolutions.contains(.single(context.tap))
        else {
            return
        }
        executeTap(.single, context: context, isClick: true)
    }

    private func resetPendingClickSequence() {
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
        pendingClickContext = nil
        clickResolver = TrackpadTapSequenceResolver(
            doubleClickInterval: tapDoubleClickInterval
        )
    }

    private func tapContext(
        for tap: TrackpadTap,
        previous: PendingTapContext?,
        current: PendingTapContext
    ) -> PendingTapContext? {
        if previous?.tap == tap { return previous }
        if current.tap == tap { return current }
        return nil
    }

    private func hasDirectMatch(
        _ gesture: DirectTrackpadGesture,
        profiles: [GestureProfile],
        rules: GestureAppRules,
        snapshot: GestureTargetSnapshot
    ) -> Bool {
        switch DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: profiles,
            snapshot: snapshot,
            rules: rules
        ) {
        case .none: return false
        case .selected, .conflict: return true
        }
    }

    private func executeDirect(
        _ gesture: DirectTrackpadGesture,
        profiles: [GestureProfile],
        rules: GestureAppRules,
        snapshot: GestureTargetSnapshot,
        mode: SessionMode
    ) {
        switch DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: profiles,
            snapshot: snapshot,
            rules: rules
        ) {
        case .none:
            // Direct no-match is intentionally quiet during normal use.
            recordOutcome(.noMatch, source: .multitouch)
        case .conflict(let ids):
            recordOutcome(.conflict(ids), source: .multitouch)
        case .selected(let targeted):
            perform(
                targeted,
                action: targeted.profile.action,
                score: nil,
                mode: mode,
                source: .multitouch
            )
        }
    }

    // MARK: - Actions

    private func perform(
        _ targeted: TargetedGesture,
        action: GestureAction,
        usesSecondaryAction: Bool = false,
        /// Button mappings fire on every click, so their success stays quiet.
        announcesMatch: Bool = true,
        score: Double?,
        mode: SessionMode,
        source: GestureInputSource
    ) {
        let result = GestureMatchResult(
            profile: targeted.profile,
            score: score ?? 1,
            usesSecondaryAction: usesSecondaryAction
        )
        lastMatch = result
        lastError = nil
        recordOutcome(
            .matched(
                profileID: targeted.profile.id,
                score: score
            ),
            source: source
        )
        onMatch?(result)
        if mode.showsToast, announcesMatch {
            GestureToastController.shared.showMatched(
                name: targeted.profile.name,
                score: score ?? 1,
                usesSecondaryAction: usesSecondaryAction
            )
        }
        guard mode.executesActions else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.actionExecutor.execute(
                    action,
                    target: targeted.target
                )
            } catch {
                self?.lastError = error.localizedDescription
                self?.recordOutcome(
                    .actionFailed(error.localizedDescription),
                    source: source
                )
                GestureToastController.shared.showActionError(
                    error.localizedDescription
                )
            }
        }
    }

    private func recordOutcome(
        _ outcome: GestureRuntimeOutcome,
        source: GestureInputSource
    ) {
        state.lastOutcome = outcome
        if source == .multitouch {
            lastTrackpadOutcome = outcome
        }
    }

    private var recognitionPolicy: GestureRecognitionPolicy {
        recognitionPolicy(for: configuration)
    }

    private func recognitionPolicy(
        for configuration: GestureRuntimeConfiguration
    ) -> GestureRecognitionPolicy {
        GestureRecognitionPolicy(
            minimumPathLength: configuration.minimumStrokeDistance,
            matchThreshold: configuration.pathMatchThreshold,
            ambiguityResolution: configuration.ambiguityResolution
        )
    }

    // MARK: - Sleep / wake

    private func refreshCombinationDisplays() {
        combinationEnvironment.displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        }
    }

    private func installWorkspaceObservers() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshCombinationDisplays() }
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
    }

    // Internal so lifecycle ordering can be verified without sleeping a test Mac.
    func handleSleep() {
        isSystemSleeping = true
        stopMultitouchInput()
        trackpadClickEventTap.stop()
        resetPendingTapSequence()
        resetPendingClickSequence()
        cancelActiveSessions()
        if case .listening = state.inputs.multitouch {
            state.inputs.multitouch = .stopped
        }
        if case .listening = state.inputs.trackpadClick {
            state.inputs.trackpadClick = .stopped
        }
        updateLifecycle()
    }

    func handleWake() {
        isSystemSleeping = false
        guard configuration.isEnabled || !diagnosticTokens.isEmpty,
              suppressionTokens.isEmpty,
              inputDemand.needsMultitouch
        else {
            return
        }
        // Wake is the one automatic, visible lifecycle restart. A failure here
        // is latched again until the user explicitly retries.
        multitouchSource?.clearFailure()
        multitouchCallbackGeneration.clearFailure()
        state.inputs.multitouch = startMultitouchIfNeeded(true)
        state.inputs.trackpadClick = startTrackpadClickIfNeeded(
            inputDemand.needsTrackpadClicks
        )
        updateLifecycle()
    }

    // MARK: - Geometry

    nonisolated static func appKitLocation(
        fromQuartz point: CGPoint,
        zeroScreenMaxY: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: zeroScreenMaxY - point.y)
    }

    private static func appKitLocation(fromQuartz point: CGPoint) -> CGPoint {
        guard let zeroScreen = NSScreen.screens.first else {
            return NSEvent.mouseLocation
        }
        return appKitLocation(
            fromQuartz: point,
            zeroScreenMaxY: zeroScreen.frame.maxY
        )
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }
}

private extension TrackpadSwipeDirection {
    var modelValue: CardinalDirection {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

private extension TrackpadGestureClassification {
    var isTap: Bool {
        if case .tap = self { return true }
        return false
    }
}

private extension TrackpadPinchDirection {
    var modelValue: PinchDirection {
        switch self {
        case .inward: return .inward
        case .outward: return .outward
        }
    }
}

private extension TrackpadRotationDirection {
    var modelValue: RotationDirection {
        switch self {
        case .clockwise: return .clockwise
        case .counterclockwise: return .counterclockwise
        }
    }
}
