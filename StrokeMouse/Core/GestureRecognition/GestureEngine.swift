import AppKit
import CoreGraphics
import Foundation
import Observation

struct GestureMatchResult: Sendable {
    let profile: GestureProfile
    let score: Double
}

@MainActor
@Observable
final class GestureEngine {
    private(set) var isEnabled = true
    private(set) var isListening = false
    private(set) var isDrawing = false
    private(set) var currentPath: [CGPoint] = []
    private(set) var lastMatch: GestureMatchResult?
    private(set) var lastError: String?
    private(set) var statusMessageKey: String = "engine.idle"

    private let eventTap = MouseEventTap()
    private let configStore: ConfigStore
    private let actionExecutor: ActionExecutor
    private let permissionManager: PermissionManager
    private let targetSession: GestureStrokeTargetSession

    private var activeButton: MouseTriggerButton?
    private var strokeOrigin: CGPoint?
    private var pendingClickQuartzLocation: CGPoint?
    private var minStrokeDistance: CGFloat = Constants.defaultMinStrokeDistance
    /// Polling keeps path sampling smooth when apps coalesce drag events.
    private var sampleTimer: Timer?
    private var hudEnabled = true
    /// When true (e.g. gesture editor open), global capture + HUD are paused.
    private var isSuppressed = false
    private var suppressCount = 0

    var onMatch: ((GestureMatchResult) -> Void)?

    /// The capture dependency is separate from the three runtime services so button-down target
    /// freezing can be tested without invoking the system Accessibility API.
    init(
        configStore: ConfigStore,
        actionExecutor: ActionExecutor,
        permissionManager: PermissionManager,
        targetCapturer: (any GestureTargetCapturing)? = nil
    ) {
        self.configStore = configStore
        self.actionExecutor = actionExecutor
        self.permissionManager = permissionManager
        targetSession = GestureStrokeTargetSession(
            capturer: targetCapturer ?? MacGestureTargetCapturer()
        )

        eventTap.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTapEvent(event)
            }
        }
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

    /// - Parameter startIfEnabled: When false, only stores preference flags (used during
    ///   early launch so the event tap is not created before the run loop is ready).
    func applyPreferences(minDistance: CGFloat, enabled: Bool, startIfEnabled: Bool = true) {
        minStrokeDistance = minDistance
        hudEnabled = DrawingStyle.showHUD
        refreshWatchedButtons()
        if startIfEnabled {
            setEnabled(enabled)
        } else {
            isEnabled = enabled
            if !enabled {
                stop()
                statusMessageKey = "engine.paused"
            }
        }
    }

    /// Rebuild the set of mouse buttons that arm gesture capture from enabled profiles.
    func refreshWatchedButtons() {
        let buttons = Set(configStore.gestures.compactMap { profile -> MouseTriggerButton? in
            profile.isEnabled ? profile.trigger.button : nil
        })
        // Always keep at least right so first-run with empty/corrupt config still listens.
        eventTap.watchedButtons = buttons.isEmpty ? [.right] : buttons
    }

    func setHUDEnabled(_ enabled: Bool) {
        hudEnabled = enabled
        DrawingStyle.showHUD = enabled
        if !enabled {
            GestureHUDController.shared.hide()
        }
    }

    /// Temporarily pause global gesture capture (reference-counted).
    /// Used while the in-app gesture recorder is open.
    func pushSuppression() {
        suppressCount += 1
        isSuppressed = true
        stopSampling()
        activeButton = nil
        strokeOrigin = nil
        pendingClickQuartzLocation = nil
        targetSession.cancel()
        isDrawing = false
        currentPath = []
        GestureHUDController.shared.hide()
        eventTap.stop()
        isListening = false
        statusMessageKey = "engine.suppressed"
    }

    func popSuppression() {
        suppressCount = max(0, suppressCount - 1)
        isSuppressed = suppressCount > 0
        if !isSuppressed, isEnabled {
            startIfPossible()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startIfPossible()
        } else {
            stop()
            statusMessageKey = "engine.paused"
        }
    }

    @discardableResult
    func startIfPossible() -> Bool {
        guard isEnabled else {
            statusMessageKey = "engine.paused"
            return false
        }
        if isSuppressed {
            statusMessageKey = "engine.suppressed"
            return false
        }
        permissionManager.refresh()
        guard permissionManager.isAccessibilityTrusted else {
            lastError = "Accessibility permission required"
            statusMessageKey = "engine.needPermission"
            stop()
            return false
        }

        refreshWatchedButtons()
        hudEnabled = DrawingStyle.showHUD
        let started = eventTap.start()
        isListening = started
        statusMessageKey = started ? "engine.listening" : "engine.failed"
        if !started {
            lastError = "Failed to create event tap"
        }
        return started
    }

    func stop() {
        stopSampling()
        eventTap.stop()
        isListening = false
        isDrawing = false
        currentPath = []
        activeButton = nil
        strokeOrigin = nil
        pendingClickQuartzLocation = nil
        targetSession.cancel()
        GestureHUDController.shared.hide()
    }

    func restart() {
        stop()
        startIfPossible()
    }

    // MARK: - Event handling

    private func handleTapEvent(_ event: MouseEventTap.EventKind) {
        guard isEnabled, isListening, !isSuppressed else { return }

        switch event {
        case .buttonDown(let button, let quartzLocation):
            beginStroke(button: button, quartzLocation: quartzLocation)

        case .buttonUp(let button, _):
            // Ignore up from a different button than the active stroke.
            if let active = activeButton, active != button { return }
            endStroke()
        }
    }

    private func beginStroke(button: MouseTriggerButton, quartzLocation: CGPoint) {
        activeButton = button
        pendingClickQuartzLocation = quartzLocation
        targetSession.handleButtonDown(
            profiles: configStore.enabledGestures(button: button),
            at: quartzLocation
        )
        let point = Self.appKitMouseLocation()
        strokeOrigin = point
        currentPath = [point]
        isDrawing = false
        startSampling()
        updateHUD()
    }

    private func appendSample(_ point: CGPoint) {
        guard activeButton != nil else { return }

        // Throttle near-duplicate points.
        if let last = currentPath.last {
            let d = hypot(point.x - last.x, point.y - last.y)
            if d < 1.5 { return }
        }

        currentPath.append(point)
        if let origin = strokeOrigin {
            let dist = hypot(point.x - origin.x, point.y - origin.y)
            if dist >= minStrokeDistance {
                isDrawing = true
            }
        }
        updateHUD()
    }

    private func endStroke() {
        // Capture the release position in case a fast stroke ends before the next timer tick.
        appendSample(Self.appKitMouseLocation())
        stopSampling()
        let path = currentPath
        let button = activeButton
        let drawing = isDrawing
        let clickLocation = pendingClickQuartzLocation
        let targetSnapshot = targetSession.takeAtButtonUp()

        activeButton = nil
        strokeOrigin = nil
        pendingClickQuartzLocation = nil
        isDrawing = false
        currentPath = []
        GestureHUDController.shared.hide()

        guard let button else { return }
        if drawing, let targetSnapshot {
            recognize(path: path, button: button, targetSnapshot: targetSnapshot)
        } else if let clickLocation,
                  !eventTap.replayClick(button: button, location: clickLocation) {
            lastError = "Failed to replay mouse click"
            statusMessageKey = "engine.failed"
        }
    }

    private func updateHUD() {
        guard hudEnabled, activeButton != nil, currentPath.count >= 2 else {
            return
        }
        GestureHUDController.shared.showPath(currentPath)
    }

    private func startSampling() {
        stopSampling()
        // High-frequency sampling while trigger is held.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeButton != nil else { return }
                self.appendSample(Self.appKitMouseLocation())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    private func stopSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    private func recognize(
        path: [CGPoint],
        button: MouseTriggerButton,
        targetSnapshot: GestureTargetSnapshot
    ) {
        let targeted = GestureCandidateSelector.prepare(
            profiles: configStore.enabledGestures(button: button),
            snapshot: targetSnapshot
        )
        let evaluation = GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: targeted.map(\.profile),
            button: button,
            minimumLength: minStrokeDistance
        )

        if evaluation.decision == .tooShort {
            statusMessageKey = "engine.noMatch"
            GestureToastController.shared.showTooShort()
            return
        }

        guard let accepted = evaluation.acceptedCandidate,
              let selected = targeted.first(where: { $0.profile.id == accepted.profile.id })
        else {
            statusMessageKey = "engine.noMatch"
            GestureToastController.shared.showNoMatch()
            return
        }

        let result = GestureMatchResult(profile: accepted.profile, score: accepted.score)
        lastMatch = result
        lastError = nil
        statusMessageKey = "engine.matched"
        onMatch?(result)
        GestureToastController.shared.showMatched(name: accepted.profile.name, score: accepted.score)
        Task { @MainActor [weak self] in
            do {
                try await self?.actionExecutor.execute(
                    accepted.profile.action,
                    target: selected.target
                )
            } catch {
                self?.lastError = error.localizedDescription
                self?.statusMessageKey = "engine.actionFailed"
                GestureToastController.shared.showActionError(error.localizedDescription)
            }
        }
    }

    /// Evaluate against every enabled profile for the selected trigger without
    /// applying app scope and without executing an action.
    func evaluateForTesting(
        path: [CGPoint],
        button: MouseTriggerButton
    ) -> GestureRecognitionEvaluation {
        GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: configStore.gestures,
            button: button,
            minimumLength: minStrokeDistance
        )
    }

    /// AppKit global mouse location (origin bottom-left).
    private static func appKitMouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
}
