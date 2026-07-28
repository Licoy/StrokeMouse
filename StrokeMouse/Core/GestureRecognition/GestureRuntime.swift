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
        let clickQuartzLocation: CGPoint?
        let origin: CGPoint
        let recognitionPolicy: GestureRecognitionPolicy
        let showsHUD: Bool
        var mode: SessionMode
        var path: [CGPoint]
        var isDrawing: Bool
    }

    private struct DirectSession {
        let revision: UInt64
        let profiles: [GestureProfile]
        let snapshot: GestureTargetSnapshot
        let beganAt: TimeInterval
        var mode: SessionMode
        var classifier = TrackpadGestureClassifier()
        var centroid = CGPoint.zero
        var terminalEventReceived = false
    }

    private struct PendingTapContext {
        let profiles: [GestureProfile]
        let snapshot: GestureTargetSnapshot
        let tap: TrackpadTap
        let mode: SessionMode
    }

    private(set) var state = GestureRuntimeState()
    private(set) var currentPath: [CGPoint] = []
    private(set) var currentTouches: [TrackpadTouchContact] = []
    private(set) var lastTrackpadMetrics: TrackpadGestureMetrics?
    private(set) var lastTrackpadOutcome: GestureRuntimeOutcome?
    private(set) var lastMatch: GestureMatchResult?
    private(set) var lastError: String?
    private(set) var isDrawing = false

    private let mouseEventTap: any MouseGestureEventSource
    private let modifierEventTap: any ModifierGestureEventSource
    private let permissionManager: any GesturePermissionProviding
    private let actionExecutor: ActionExecutor
    private let targetCapturer: any GestureTargetCapturing
    private let multitouchSourceFactory: () -> any MultitouchFrameSource
    private let inputCoreQueue: DispatchQueue
    private let sessionGate = GestureSessionGate()
    private let drawCallbackGeneration = DrawCallbackGeneration()
    private let multitouchAdmission = MultitouchSessionAdmission()
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
        directTrackpadEnabled: true
    )
    private var drawSession: DrawSession?
    private var directSession: DirectSession?
    private var ignoresDirectTouchesUntilEmpty = false
    private var sampleTimer: Timer?
    private var pendingTapTimer: Timer?
    private let tapDoubleClickInterval: TimeInterval
    private var tapResolver: TrackpadTapSequenceResolver
    private var pendingTapContext: PendingTapContext?
    private var suppressionTokens = Set<UUID>()
    private var diagnosticTokens = Set<UUID>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSystemSleeping = false

    var onMatch: ((GestureMatchResult) -> Void)?

    init(
        permissionManager: any GesturePermissionProviding,
        actionExecutor: ActionExecutor,
        targetCapturer: (any GestureTargetCapturing)? = nil,
        mouseEventTap: any MouseGestureEventSource = MouseEventTap(),
        modifierEventTap: any ModifierGestureEventSource = ModifierEventTap(),
        doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval,
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
        self.mouseEventTap = mouseEventTap
        self.modifierEventTap = modifierEventTap
        self.multitouchSourceFactory = multitouchSourceFactory
        self.inputCoreQueue = inputCoreQueue
        let doubleClickInterval = max(0, doubleClickInterval)
        tapDoubleClickInterval = doubleClickInterval
        tapResolver = TrackpadTapSequenceResolver(
            doubleClickInterval: doubleClickInterval
        )
        let drawCallbacks = drawCallbackGeneration
        mouseEventTap.shouldCapture = { [weak sessionGate] button in
            guard drawCallbacks.token != nil else { return false }
            return sessionGate?.claim(.mouse(button)) != nil
        }
        mouseEventTap.onEvent = {
            [weak self, weak sessionGate, weak mouseEventTap]
            event, sourceGeneration in
            guard let mouseEventTap else { return }
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
                let snapshot: GestureTargetSnapshot?
                switch event {
                case .buttonDown(let button, let location):
                    admission = sessionGate?.admission(
                        for: .mouse(button)
                    )
                    snapshot = admission.map {
                        Self.captureTargetSnapshot(
                            for: $0,
                            at: location,
                            using: resolvedTargetCapturer
                        )
                    }
                case .buttonUp(let button, _):
                    if let completed = sessionGate?.admission(
                        for: .mouse(button)
                    ) {
                        sessionGate?.release(completed)
                    }
                    admission = nil
                    snapshot = nil
                case .interrupted(let button, _):
                    _ = sessionGate?.interrupt(.mouse(button))
                    admission = nil
                    snapshot = nil
                case .drained(let button):
                    _ = sessionGate?.completeDrain(.mouse(button))
                    admission = nil
                    snapshot = nil
                }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.handleMouseEvent(
                            event,
                            admission: admission,
                            snapshot: snapshot
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
                    admission = sessionGate?.claim(.modifier(key))
                    snapshot = admission.map {
                        Self.captureTargetSnapshot(
                            for: $0,
                            at: quartzLocation,
                            using: resolvedTargetCapturer
                        )
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
        publishAdmissionContext()
        installWorkspaceObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            sampleTimer?.invalidate()
            pendingTapTimer?.invalidate()
            mouseEventTap.onEvent = nil
            mouseEventTap.shouldCapture = nil
            modifierEventTap.onEvent = nil
            mouseEventTap.stop()
            modifierEventTap.stop()
            multitouchCallbackGeneration.invalidate()
            multitouchSource?.stop()
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
            downgradeActiveSessionToDiagnostics()
        }
        sessionGate.updateContext(admissionContext(
            for: configuration,
            isDiagnostic: true
        ))
        diagnosticTokens.insert(token)
        currentTouches = []
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
            guard drawn.points.count >= 2,
                  drawn.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
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
        modifierEventTap.watchedKeys = demand.modifierKeys

        guard configuration.isEnabled || !diagnosticTokens.isEmpty else {
            stopChannels()
            state.inputs = GestureRuntimeInputStatuses(
                mouse: demand.mouseButtons.isEmpty ? .notRequested : .stopped,
                modifier: demand.modifierKeys.isEmpty ? .notRequested : .stopped,
                multitouch: demand.needsMultitouch ? .stopped : .notRequested
            )
            state.lifecycle = .stopped
            return
        }
        guard suppressionTokens.isEmpty else {
            stopChannels()
            state.inputs = GestureRuntimeInputStatuses(
                mouse: demand.mouseButtons.isEmpty ? .notRequested : .stopped,
                modifier: demand.modifierKeys.isEmpty ? .notRequested : .stopped,
                multitouch: demand.needsMultitouch ? .stopped : .notRequested
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
        updateLifecycle()
    }

    private var inputDemand: (
        mouseButtons: Set<MouseTriggerButton>,
        modifierKeys: Set<GestureModifierKey>,
        needsMultitouch: Bool
    ) {
        var buttons = Set<MouseTriggerButton>()
        var modifiers = Set<GestureModifierKey>()
        var direct = false
        for profile in configuration.profiles where profile.isEnabled {
            switch profile.input {
            case .drawn(let drawn):
                switch drawn.activation {
                case .mouse(let trigger): buttons.insert(trigger.button)
                case .modifier(let key): modifiers.insert(key)
                }
            case .trackpad:
                direct = true
            }
        }
        return (
            buttons,
            modifiers,
            (direct || !diagnosticTokens.isEmpty)
                && configuration.directTrackpadEnabled
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
                                    targetSnapshot: snapshot
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
        inputCoreQueue.async { [weak self] in
            let releasedOwner = arbitrationGate.forceRelease(.multitouch)
            let resetSequence = admissionController.reset()
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
        stopMultitouchInput()
        cancelActiveSessions()
    }

    private func cancelActiveSessions() {
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
        snapshot: GestureTargetSnapshot?
    ) {
        switch event {
        case .buttonDown(let button, let quartzLocation):
            guard let admission else { return }
            beginDraw(
                source: .mouse(button),
                quartzLocation: quartzLocation,
                clickQuartzLocation: quartzLocation,
                admission: admission,
                snapshot: snapshot
            )
        case .buttonUp(let button, let quartzLocation):
            finishDraw(
                source: .mouse(button),
                quartzLocation: quartzLocation,
                wasCancelled: false
            )
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
                snapshot: snapshot
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
        snapshot: GestureTargetSnapshot?
    ) {
        guard admission.source == source,
              sessionGate.isValid(admission),
              drawSession == nil,
              let snapshot
        else {
            return
        }
        let frozenConfiguration = admission.context.configuration
        let candidates = frozenConfiguration.profiles.filter {
            $0.isEnabled && Self.matches(source: source, input: $0.input)
        }
        let targeted = GestureCandidateSelector.prepare(
            profiles: candidates,
            snapshot: snapshot
        )
        let point = Self.appKitLocation(fromQuartz: quartzLocation)
        drawSession = DrawSession(
            source: source,
            revision: frozenConfiguration.revision,
            targeted: targeted,
            clickQuartzLocation: clickQuartzLocation,
            origin: point,
            recognitionPolicy: recognitionPolicy(
                for: frozenConfiguration
            ),
            showsHUD: frozenConfiguration.showsHUD,
            mode: admission.context.isDiagnostic
                || !diagnosticTokens.isEmpty
                || !suppressionTokens.isEmpty
                ? .diagnostic
                : .normal,
            path: [point],
            isDrawing: false
        )
        currentPath = [point]
        state.activeSession = GestureActiveSessionSummary(
            source: source,
            configurationRevision: frozenConfiguration.revision,
            candidateCount: targeted.count
        )
        startSampling()
    }

    private func appendDrawSample(_ point: CGPoint) {
        guard var session = drawSession else { return }
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
        drawSession = session
        currentPath = session.path
        isDrawing = session.isDrawing
        if session.showsHUD, session.path.count >= 2 {
            GestureHUDController.shared.showPath(session.path)
        }
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
        appendDrawSample(Self.appKitLocation(fromQuartz: quartzLocation))
        let finished = drawSession ?? session
        stopSampling()
        drawSession = nil
        currentPath = []
        isDrawing = false
        state.activeSession = nil
        GestureHUDController.shared.hide()

        defer { reconcileChannels() }
        guard !wasCancelled else {
            state.lastOutcome = .cancelled
            return
        }
        if finished.isDrawing {
            recognizeDrawn(finished)
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
            state.lastOutcome = .noMatch
            if session.mode.showsToast {
                if evaluation.decision == .tooShort {
                    GestureToastController.shared.showTooShort()
                } else {
                    GestureToastController.shared.showNoMatch()
                }
            }
            return
        }
        perform(
            selected,
            score: accepted.score,
            mode: session.mode,
            source: session.source
        )
    }

    nonisolated private static func matches(
        source: GestureInputSource,
        input: GestureInput
    ) -> Bool {
        switch (source, input) {
        case (.mouse(let button), .drawn(let drawn)):
            guard case .mouse(let trigger) = drawn.activation else {
                return false
            }
            return button == trigger.button
        case (.modifier(let key), .drawn(let drawn)):
            guard case .modifier(let configured) = drawn.activation else {
                return false
            }
            return key == configured
        case (.multitouch, .trackpad):
            return true
        default:
            return false
        }
    }

    nonisolated private static func captureTargetSnapshot(
        for admission: GestureInputAdmission,
        at quartzLocation: CGPoint,
        using capturer: any GestureTargetCapturing
    ) -> GestureTargetSnapshot {
        let profiles = admission.context.configuration.profiles.filter {
            profile in
            guard profile.isEnabled else { return false }
            return matches(source: admission.source, input: profile.input)
        }
        return capturer.capture(
            policies: Set(profiles.map(\.targetPolicy)),
            at: quartzLocation
        )
    }

    private func startSampling() {
        stopSampling()
        let timer = Timer(timeInterval: 1 / 120, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.appendDrawSample(NSEvent.mouseLocation)
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
        targetSnapshot: GestureTargetSnapshot?
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
                contacts: activeContacts,
                admission: inputAdmission,
                snapshot: targetSnapshot
            )
        }
        guard var session = directSession else { return }
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
            case .recognized(let classification):
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
        preparePendingTapForContactSequence(startedAt: frame.timestamp)
        directSession = DirectSession(
            revision: frozenConfiguration.revision,
            profiles: profiles,
            snapshot: snapshot,
            beganAt: frame.timestamp,
            mode: admission.context.isDiagnostic
                || !diagnosticTokens.isEmpty
                || !suppressionTokens.isEmpty
                ? .diagnostic
                : .normal,
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
                snapshot: snapshot
            ),
            hasDouble: hasDirectMatch(
                .tap(count, .double),
                profiles: profiles,
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
            session.mode = .diagnostic
            drawSession = session
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
        context: PendingTapContext
    ) {
        guard let count = StandardFingerCount(
            rawValue: context.tap.fingers
        ) else {
            recordOutcome(.noMatch, source: .multitouch)
            return
        }
        executeDirect(
            .tap(count, tapCount),
            profiles: context.profiles,
            snapshot: context.snapshot,
            mode: context.mode
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
        snapshot: GestureTargetSnapshot
    ) -> Bool {
        switch DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: profiles,
            snapshot: snapshot
        ) {
        case .none: return false
        case .selected, .conflict: return true
        }
    }

    private func executeDirect(
        _ gesture: DirectTrackpadGesture,
        profiles: [GestureProfile],
        snapshot: GestureTargetSnapshot,
        mode: SessionMode
    ) {
        switch DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: profiles,
            snapshot: snapshot
        ) {
        case .none:
            // Direct no-match is intentionally quiet during normal use.
            recordOutcome(.noMatch, source: .multitouch)
        case .conflict(let ids):
            recordOutcome(.conflict(ids), source: .multitouch)
        case .selected(let targeted):
            perform(
                targeted,
                score: nil,
                mode: mode,
                source: .multitouch
            )
        }
    }

    // MARK: - Actions

    private func perform(
        _ targeted: TargetedGesture,
        score: Double?,
        mode: SessionMode,
        source: GestureInputSource
    ) {
        let result = GestureMatchResult(
            profile: targeted.profile,
            score: score ?? 1
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
        if mode.showsToast {
            GestureToastController.shared.showMatched(
                name: targeted.profile.name,
                score: score ?? 1
            )
        }
        guard mode.executesActions else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.actionExecutor.execute(
                    targeted.profile.action,
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
            matchThreshold: configuration.pathMatchThreshold
        )
    }

    // MARK: - Sleep / wake

    private func installWorkspaceObservers() {
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
        resetPendingTapSequence()
        cancelActiveSessions()
        if case .listening = state.inputs.multitouch {
            state.inputs.multitouch = .stopped
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
