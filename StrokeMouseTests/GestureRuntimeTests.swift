import AppKit
import CoreGraphics
import XCTest
@testable import StrokeMouse

@MainActor
final class GestureRuntimeTests: XCTestCase {
    func testInvalidApplyKeepsPreviousConfigurationSnapshot() throws {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let valid = GestureProfile(
            name: "Valid",
            pattern: .freePath(PathTemplates.up)
        )
        try runtime.apply(configuration(
            revision: 7,
            enabled: false,
            profiles: [valid]
        ))

        XCTAssertThrowsError(try runtime.apply(configuration(
            revision: 8,
            enabled: false,
            profiles: [valid, valid]
        )))
        XCTAssertEqual(runtime.state.configurationRevision, 7)
    }

    func testMultitouchFailureIsTypedAndDoesNotRejectConfiguration() throws {
        let source = RuntimeMultitouchSource()
        source.startError = .frameworkUnavailable
        let runtime = makeRuntime(source: source)
        let profile = directProfile(
            gesture: .swipe(.three, .right)
        )

        let state = try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        XCTAssertEqual(
            state.inputs.multitouch,
            .failed(.multitouchFrameworkUnavailable)
        )
        XCTAssertEqual(state.lifecycle, .degraded)
        XCTAssertEqual(state.configurationRevision, 1)
    }

    func testMultitouchFailureStaysLatchedUntilExplicitRetry() throws {
        let source = RuntimeMultitouchSource()
        source.startError = .frameworkUnavailable
        let runtime = makeRuntime(source: source)
        let profile = directProfile(gesture: .swipe(.three, .right))

        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))
        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [profile]
        ))
        XCTAssertEqual(source.startCount, 1)

        runtime.retryFailedInputs()

        XCTAssertEqual(source.startCount, 2)
        XCTAssertEqual(
            runtime.state.inputs.multitouch,
            .failed(.multitouchFrameworkUnavailable)
        )
    }

    func testAsynchronousMultitouchFailureLatchesBeforeMainDelivery()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let profile = directProfile(gesture: .swipe(.three, .right))
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.fail(.invalidFrame)
        let state = try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [profile]
        ))

        XCTAssertEqual(
            state.inputs.multitouch,
            .failed(.multitouchInvalidFrame)
        )
        XCTAssertEqual(source.startCount, 1)
        await drainMainActor()
        XCTAssertEqual(
            runtime.state.inputs.multitouch,
            .failed(.multitouchInvalidFrame)
        )

        runtime.retryFailedInputs()
        XCTAssertEqual(source.startCount, 2)
    }

    func testSleepStopsDeviceAndWakeAttemptsExactlyOneVisibleRestart()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let profile = directProfile(gesture: .swipe(.three, .right))
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))
        XCTAssertEqual(source.startCount, 1)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        await drainMainActor()
        XCTAssertFalse(source.isRunning)
        XCTAssertEqual(runtime.state.inputs.multitouch, .stopped)

        source.startError = .frameworkUnavailable
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await drainMainActor()

        XCTAssertEqual(source.startCount, 2)
        XCTAssertEqual(
            runtime.state.inputs.multitouch,
            .failed(.multitouchFrameworkUnavailable)
        )
        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [profile]
        ))
        XCTAssertEqual(source.startCount, 2)
    }

    func testQueuedFrameFromStoppedGenerationCannotPoisonWake()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let profile = directProfile(gesture: .swipe(.three, .right))
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        runtime.handleSleep()
        await drainMainActor()

        XCTAssertNil(runtime.state.activeSession)
        XCTAssertTrue(runtime.currentTouches.isEmpty)

        runtime.handleWake()
        source.emit(frame(at: 1, points: basePoints()))
        source.emit(frame(at: 1.07, points: basePoints()))
        source.emit(frame(
            at: 1.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 1.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [profile.id])
    }

    func testMultitouchFailureLeavesMouseCaptureOperational()
        async throws
    {
        let source = RuntimeMultitouchSource()
        source.startError = .frameworkUnavailable
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            multitouchSourceFactory: { source }
        )
        let drawn = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger.default),
                points: PathTemplates.up
            ))
        )
        let direct = directProfile(gesture: .swipe(.three, .right))

        let state = try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [drawn, direct]
        ))
        XCTAssertEqual(
            state.inputs.mouse,
            GestureInputChannelStatus.listening
        )
        XCTAssertEqual(
            state.inputs.multitouch,
            GestureInputChannelStatus.failed(
                .multitouchFrameworkUnavailable
            )
        )

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        await drainMainActor()

        XCTAssertEqual(mouse.replayedClicks, 1)
        XCTAssertEqual(runtime.state.inputs.mouse, .listening)
    }

    func testMouseAdmissionFreezesConfigurationBeforeMainActorBegin()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            multitouchSourceFactory: { source }
        )
        let original = GestureProfile(
            name: "Original",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger.default),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 10,
            enabled: true,
            profiles: [original]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        try runtime.apply(configuration(
            revision: 11,
            enabled: true,
            profiles: []
        ))
        await drainMainActor()

        XCTAssertEqual(runtime.state.activeSession?.configurationRevision, 10)
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 1)

        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        await drainMainActor()
        XCTAssertEqual(mouse.replayedClicks, 1)
        XCTAssertNil(runtime.state.activeSession)
    }

    func testPhysicalReleaseThenNewSourceIsProcessedInCoreOrder()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                GestureProfile(
                    name: "Mouse",
                    input: .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: PathTemplates.up
                    ))
                ),
                GestureProfile(
                    name: "Modifier",
                    input: .drawn(DrawnGesture(
                        activation: .modifier(.function),
                        points: PathTemplates.up
                    ))
                ),
            ]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        modifier.press(.function)
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        XCTAssertEqual(mouse.replayedClicks, 1)
        modifier.release(.function)
        await drainMainActor()
    }

    func testNextTouchSequenceFreezesNewRevisionAfterPhysicalEmpty()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let first = directProfile(
            name: "First",
            gesture: .swipe(.three, .right)
        )
        let second = directProfile(
            name: "Second",
            gesture: .swipe(.three, .left)
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [first]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.01, points: [:]))
        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [second]
        ))
        source.emit(frame(at: 1, points: basePoints()))
        await drainMainActor()

        XCTAssertEqual(runtime.state.activeSession?.configurationRevision, 2)
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 1)
        source.emit(frame(at: 1.01, points: [:]))
        await drainMainActor()
    }

    func testHardCancellationInvalidatesQueuedAdmission() async throws {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let permission = RuntimePermissionProvider(trusted: true)
        let runtime = GestureRuntime(
            permissionManager: permission,
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            multitouchSourceFactory: { source }
        )
        let profile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        permission.isAccessibilityTrusted = false
        runtime.accessibilityTrustDidChange(false)
        await drainMainActor()

        XCTAssertNil(runtime.state.activeSession)
        XCTAssertFalse(runtime.isDrawing)
    }

    func testAccessibilityRevocationInvalidatesPhysicallyReleasedAdmission()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let permission = RuntimePermissionProvider(trusted: true)
        let runtime = GestureRuntime(
            permissionManager: permission,
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                GestureProfile(
                    name: "Mouse",
                    input: .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: PathTemplates.up
                    ))
                ),
            ]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        permission.isAccessibilityTrusted = false
        runtime.accessibilityTrustDidChange(false)
        await drainMainActor()

        XCTAssertNil(runtime.state.activeSession)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testLateModifierBeginDuringPermissionStopCannotCreateSession()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let modifier = RuntimeModifierEventSource()
        modifier.beganEventOnStop = .function
        let permission = RuntimePermissionProvider(trusted: true)
        let runtime = GestureRuntime(
            permissionManager: permission,
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                GestureProfile(
                    name: "Modifier",
                    input: .drawn(DrawnGesture(
                        activation: .modifier(.function),
                        points: PathTemplates.up
                    ))
                ),
            ]
        ))

        permission.isAccessibilityTrusted = false
        runtime.accessibilityTrustDidChange(false)
        await drainMainActor()

        XCTAssertNil(runtime.state.activeSession)
        XCTAssertFalse(runtime.isDrawing)
    }

    func testDirectAdmissionFreezesConfigurationBeforeMainActorBegin()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let original = directProfile(
            gesture: .swipe(.three, .right)
        )
        try runtime.apply(configuration(
            revision: 20,
            enabled: true,
            profiles: [original]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        try runtime.apply(configuration(
            revision: 21,
            enabled: true,
            profiles: []
        ))
        await drainMainActor()

        XCTAssertEqual(runtime.state.activeSession?.configurationRevision, 20)
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 1)

        source.emit(frame(at: 0.10, points: [:]))
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)
    }

    func testDiagnosticsStartsTouchInputWithoutProfilesOrGlobalEnable() throws {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        try runtime.apply(configuration(
            revision: 1,
            enabled: false,
            profiles: []
        ))

        let diagnostic = runtime.beginDiagnostics()

        XCTAssertTrue(source.isRunning)
        XCTAssertEqual(runtime.state.inputs.multitouch, .listening)
        diagnostic.end()
        XCTAssertFalse(source.isRunning)
    }

    func testSuppressionLeasesAreNestedAndReleaseIsIdempotent() throws {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            multitouchSourceFactory: { source }
        )
        let profile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))
        let first = runtime.suppress(reason: .settings)
        let second = runtime.suppress(reason: .gestureEditor)

        XCTAssertEqual(runtime.state.lifecycle, .suppressed)
        first.release()
        first.release()
        XCTAssertEqual(runtime.state.lifecycle, .suppressed)

        second.release()
        XCTAssertEqual(runtime.state.lifecycle, .listening)
        XCTAssertTrue(mouse.isActive)
    }

    func testDirectGestureUsesFrozenProfileAndExecutesOnce() async throws {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let original = directProfile(
            name: "Original",
            gesture: .swipe(.three, .right)
        )
        let replacement = directProfile(
            name: "Replacement",
            gesture: .swipe(.three, .right)
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [original]
        ))

        source.emit(frame(
            at: 0,
            points: basePoints()
        ))
        await drainMainActor()
        source.emit(frame(
            at: 0.07,
            points: basePoints()
        ))
        await drainMainActor()

        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [replacement]
        ))
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [original.id])
        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: original.id, score: nil)
        )
    }

    func testDiagnosticsRecognizesWithoutExecutingAction() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: PermissionManager(),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
        let profile = GestureProfile(
            name: "Diagnostic",
            input: .trackpad(.swipe(.three, .right)),
            action: .shortcut(
                keyCode: 0,
                modifiers: 0,
                display: "A",
                orderedChord: nil
            )
        )
        let diagnostic = runtime.beginDiagnostics()
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: profile.id, score: nil)
        )
        XCTAssertEqual(platform.shortcutCount, 0)
        diagnostic.end()
    }

    func testDiagnosticModeIsFrozenAcrossDelayedDoubleTap() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: PermissionManager(),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
        let profile = GestureProfile(
            name: "Double",
            input: .trackpad(.tap(.three, .double)),
            action: .shortcut(
                keyCode: 0,
                modifiers: 0,
                display: "A",
                orderedChord: nil
            )
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))
        let diagnostic = runtime.beginDiagnostics()
        emitTap(source, startedAt: 1)
        await drainMainActor()
        diagnostic.end()

        emitTap(source, startedAt: 1.15)
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: profile.id, score: nil)
        )
        XCTAssertEqual(platform.shortcutCount, 0)
    }

    func testSecondTapUsesContactBeginForDoubleClickDeadline()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let single = directProfile(
            name: "Single",
            gesture: .tap(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .tap(.three, .double)
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            doubleClickInterval: 0.30,
            multitouchSourceFactory: { source }
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        emitTap(source, startedAt: 1)
        emitTap(source, startedAt: 1.39)
        await drainMainActor()

        XCTAssertEqual(matches, [double.id])
    }

    func testUnconfiguredSecondTapFlushesPendingSingle()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let single = directProfile(
            name: "Single",
            gesture: .tap(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .tap(.three, .double)
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            doubleClickInterval: 0.30,
            multitouchSourceFactory: { source }
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        emitTap(source, startedAt: 1)
        let fourPoints = basePoints().merging([
            4: CGPoint(x: 0.5, y: 0.5),
        ]) { current, _ in current }
        source.emit(frame(at: 1.30, points: fourPoints))
        source.emit(frame(at: 1.37, points: fourPoints))
        source.emit(frame(at: 1.42, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [single.id])
    }

    func testBackwardSecondSequenceFlushesPendingSingleWithoutNewMatch()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let single = directProfile(
            name: "Single",
            gesture: .tap(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .tap(.three, .double)
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            doubleClickInterval: 0.30,
            multitouchSourceFactory: { source }
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        emitTap(source, startedAt: 1)
        emitTap(source, startedAt: 0.5)
        await drainMainActor()

        XCTAssertEqual(matches, [single.id])
        XCTAssertEqual(runtime.lastTrackpadOutcome, .rejected(.invalidFrame))
    }

    func testNonFiniteSecondSequenceFlushesPendingSingle()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let single = directProfile(
            name: "Single",
            gesture: .tap(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .tap(.three, .double)
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            doubleClickInterval: 0.30,
            multitouchSourceFactory: { source }
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        emitTap(source, startedAt: 1)
        source.emit(frame(at: .nan, points: basePoints()))
        source.emit(frame(at: 2, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [single.id])
        XCTAssertEqual(runtime.lastTrackpadOutcome, .rejected(.invalidFrame))
    }

    func testEnteringDiagnosticsDowngradesActiveNormalSession() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
        let profile = shortcutProfile(name: "Normal then diagnostic")
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        await drainMainActor()
        let diagnostic = runtime.beginDiagnostics()
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: profile.id, score: nil)
        )
        XCTAssertEqual(platform.shortcutCount, 0)
        diagnostic.end()
    }

    func testEnteringSuppressionDowngradesActiveNormalSession() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
        let profile = shortcutProfile(name: "Normal then suppressed")
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        await drainMainActor()
        let suppression = runtime.suppress(reason: .settings)
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: profile.id, score: nil)
        )
        XCTAssertEqual(platform.shortcutCount, 0)
        suppression.release()
    }

    func testDiagnosticsReportsUnconfiguredTapAsNoMatch() async throws {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        try runtime.apply(configuration(
            revision: 1,
            enabled: false,
            profiles: []
        ))
        let diagnostic = runtime.beginDiagnostics()

        emitTap(source, startedAt: 1)
        await drainMainActor()

        XCTAssertEqual(runtime.lastTrackpadOutcome, .noMatch)
        diagnostic.end()
    }

    func testAccessibilityRevocationCancelsDrawSourcesAndRestartsThem()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let permission = RuntimePermissionProvider(trusted: true)
        let runtime = GestureRuntime(
            permissionManager: permission,
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let profiles = [
            GestureProfile(
                name: "Mouse",
                input: .drawn(DrawnGesture(
                    activation: .mouse(GestureTrigger.default),
                    points: PathTemplates.up
                ))
            ),
            GestureProfile(
                name: "Modifier",
                input: .drawn(DrawnGesture(
                    activation: .modifier(.function),
                    points: PathTemplates.up
                ))
            ),
        ]
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: profiles
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .mouse(.right))

        permission.isAccessibilityTrusted = false
        runtime.accessibilityTrustDidChange(false)
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertFalse(mouse.isActive)
        XCTAssertFalse(modifier.isActive)
        XCTAssertEqual(
            runtime.state.inputs.mouse,
            .failed(.accessibilityRequired)
        )
        XCTAssertEqual(
            runtime.state.inputs.modifier,
            .failed(.accessibilityRequired)
        )

        permission.isAccessibilityTrusted = true
        runtime.accessibilityTrustDidChange(true)
        XCTAssertTrue(mouse.isActive)
        XCTAssertTrue(modifier.isActive)
        XCTAssertEqual(runtime.state.inputs.mouse, .listening)
        XCTAssertEqual(runtime.state.inputs.modifier, .listening)

        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        permission.isAccessibilityTrusted = false
        runtime.accessibilityTrustDidChange(false)
        XCTAssertNil(runtime.state.activeSession)
    }

    func testActiveTouchSessionSurvivesDemandChangeUntilAllTouchesLift()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let runtime = makeRuntime(source: source)
        let profile = directProfile(gesture: .swipe(.three, .right))
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))
        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        await drainMainActor()

        try runtime.apply(configuration(
            revision: 2,
            enabled: false,
            profiles: []
        ))
        XCTAssertTrue(source.isRunning)
        XCTAssertNotNil(runtime.state.activeSession)

        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertFalse(source.isRunning)
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertEqual(runtime.state.lifecycle, .stopped)
    }

    func testDirectConflictExecutesNoAction() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: PermissionManager(),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
        let first = shortcutProfile(name: "First")
        let second = shortcutProfile(name: "Second")
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [first, second]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(runtime.state.lastOutcome, .conflict([
            first.id,
            second.id,
        ]))
        XCTAssertEqual(platform.shortcutCount, 0)
    }

    func testDirectGestureUsesTargetFrozenAtContactBegin() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let capturer = MutableRuntimeTargetCapturer(processIdentifier: 101)
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: capturer,
            multitouchSourceFactory: { source }
        )
        var profile = shortcutProfile(name: "Frozen target")
        profile.scope = .apps(["com.example.target"])
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        source.emit(frame(at: 0, points: basePoints()))
        capturer.processIdentifier = 202
        source.emit(frame(at: 0.07, points: basePoints()))
        await drainMainActor()
        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(platform.shortcutProcessIdentifiers, [101])
    }

    func testFirstOfThreeInputSourcesOwnsSessionUntilPhysicalDrain()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let mouseProfile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger.default),
                points: PathTemplates.up
            ))
        )
        let modifierProfile = GestureProfile(
            name: "Modifier",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            ))
        )
        let direct = directProfile(gesture: .swipe(.three, .right))
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mouseProfile, modifierProfile, direct]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        modifier.press(.function)
        source.emit(frame(at: 0, points: basePoints()))
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .mouse(.right))

        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        modifier.release(.function)
        source.emit(frame(at: 0.07, points: basePoints()))
        source.emit(frame(at: 0.10, points: [:]))
        await drainMainActor()

        source.emit(frame(at: 1, points: basePoints()))
        source.emit(frame(at: 1.07, points: basePoints()))
        source.emit(frame(
            at: 1.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 1.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: direct.id, score: nil)
        )
    }

    func testBusyGatePassesMouseDownAndUpThroughUncaptured()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                GestureProfile(
                    name: "Mouse",
                    input: .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: PathTemplates.up
                    ))
                ),
                GestureProfile(
                    name: "Modifier",
                    input: .drawn(DrawnGesture(
                        activation: .modifier(.function),
                        points: PathTemplates.up
                    ))
                ),
            ]
        ))

        modifier.press(.function)
        await drainMainActor()
        XCTAssertFalse(mouse.press(
            .right,
            at: CGPoint(x: 10, y: 10)
        ))
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        XCTAssertEqual(mouse.replayedClicks, 0)
        modifier.release(.function)
        await drainMainActor()
    }

    func testSharedMouseProfileEnablesItsModifierInput() async throws {
        let source = RuntimeMultitouchSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let profile = GestureProfile(
            name: "Shared",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up,
                trackpadModifierKey: .function
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        XCTAssertEqual(modifier.watchedKeys, Set([.function]))
        modifier.press(.option)
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)

        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .modifier(.function))
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 1)
        modifier.release(.function)
        await drainMainActor()
    }

    func testStandaloneModifierProfileCompletesSameRecognitionAsSharedMouseProfile()
        async throws
    {
        let inputs: [GestureInput] = [
            .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            )),
            .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up,
                trackpadModifierKey: .function
            )),
        ]

        for (index, input) in inputs.enumerated() {
            let source = RuntimeMultitouchSource()
            let modifier = RuntimeModifierEventSource()
            let runtime = GestureRuntime(
                permissionManager: RuntimePermissionProvider(trusted: true),
                actionExecutor: ActionExecutor(),
                targetCapturer: RuntimeTargetCapturer(),
                modifierEventTap: modifier,
                multitouchSourceFactory: { source }
            )
            let profile = GestureProfile(name: "Profile \(index)", input: input)
            var matchedIDs: [UUID] = []
            runtime.onMatch = { matchedIDs.append($0.profile.id) }
            try runtime.apply(configuration(
                revision: UInt64(index + 1),
                enabled: true,
                profiles: [profile]
            ))

            modifier.press(.function, at: CGPoint(x: 20, y: 300))
            modifier.release(.function, at: CGPoint(x: 20, y: 100))
            await drainMainActor()

            XCTAssertEqual(matchedIDs, [profile.id])
            guard case .matched(let profileID, _) = runtime.state.lastOutcome else {
                return XCTFail("Expected a completed modifier-draw match")
            }
            XCTAssertEqual(profileID, profile.id)
        }
    }

    func testDiagnosticModifierInputReportsNoMatchWithoutConfiguredProfile()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: false,
            profiles: []
        ))
        let diagnostic = runtime.beginDiagnostics()

        XCTAssertEqual(
            modifier.watchedKeys,
            Set(GestureModifierKey.allCases)
        )
        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 0)
        modifier.release(.function)
        await drainMainActor()

        XCTAssertEqual(
            runtime.lastDrawDiagnostic?.source,
            .modifier(.function)
        )
        XCTAssertEqual(runtime.lastDrawDiagnostic?.outcome, .noMatch)
        diagnostic.end()
    }

    func testConfigurationApplyDuringDiagnosticsKeepsModifierAdmissionDiagnostic()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: false,
            profiles: []
        ))
        let diagnostic = runtime.beginDiagnostics()

        try runtime.apply(configuration(
            revision: 2,
            enabled: false,
            profiles: []
        ))
        modifier.press(.function)
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        XCTAssertEqual(runtime.state.activeSession?.candidateCount, 0)
        modifier.release(.function)
        await drainMainActor()
        diagnostic.end()
    }

    func testNewModifierDiagnosticClearsPreviousPathBeforeMinimumDistance()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: false,
            profiles: []
        ))
        let diagnostic = runtime.beginDiagnostics()
        let pointerLocation = try XCTUnwrap(CGEvent(source: nil)).location
        modifier.press(.function, at: pointerLocation)
        await drainMainActor()
        modifier.release(.function, at: pointerLocation)
        await drainMainActor()
        XCTAssertNotNil(runtime.lastDrawDiagnostic)

        modifier.press(.option, at: pointerLocation)
        await drainMainActor()

        XCTAssertNil(runtime.lastDrawDiagnostic)
        XCTAssertEqual(runtime.currentPath.count, 1)
        XCTAssertFalse(runtime.isDrawing)
        modifier.release(.option, at: pointerLocation)
        await drainMainActor()
        diagnostic.end()
    }

    func testInterruptedMouseCaptureWaitsForDrainBeforeReleasingGate()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let mouseProfile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            ))
        )
        let modifierProfile = GestureProfile(
            name: "Modifier",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mouseProfile, modifierProfile]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .mouse(.right))

        mouse.interrupt(.right, at: CGPoint(x: 12, y: 12))
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertEqual(runtime.state.lastOutcome, .cancelled)

        modifier.press(.function)
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)
        modifier.release(.function)
        mouse.release(.right, at: CGPoint(x: 12, y: 12))
        await drainMainActor()

        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        modifier.release(.function)
        await drainMainActor()
    }

    func testInterruptedModifierCaptureWaitsForDrainBeforeReleasingGate()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let mouseProfile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            ))
        )
        let modifierProfile = GestureProfile(
            name: "Modifier",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mouseProfile, modifierProfile]
        ))

        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )

        modifier.interrupt(.function)
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertEqual(runtime.state.lastOutcome, .cancelled)

        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        modifier.release(.function)
        await drainMainActor()

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .mouse(.right))
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        await drainMainActor()
    }

    func testAlreadyReleasedInputDrainsInterruptedGateImmediately()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        let mouseProfile = GestureProfile(
            name: "Mouse",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            ))
        )
        let modifierProfile = GestureProfile(
            name: "Modifier",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mouseProfile, modifierProfile]
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        mouse.interrupt(
            .right,
            at: CGPoint(x: 12, y: 12),
            isStillPressed: false
        )
        await drainMainActor()

        modifier.press(.function)
        await drainMainActor()
        XCTAssertEqual(
            runtime.state.activeSession?.source,
            .modifier(.function)
        )
        modifier.release(.function)
        await drainMainActor()
    }

    func testRuntimeDeinitStopsAndDetachesAllInputSources() throws {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        var capturer: RuntimeLifecycleTargetCapturer? =
            RuntimeLifecycleTargetCapturer()
        weak var releasedCapturer = capturer
        weak var releasedRuntime: GestureRuntime?
        var runtime: GestureRuntime? = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            multitouchSourceFactory: { source }
        )
        releasedRuntime = runtime
        try runtime?.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                GestureProfile(
                    name: "Mouse",
                    input: .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: PathTemplates.up
                    ))
                ),
                GestureProfile(
                    name: "Modifier",
                    input: .drawn(DrawnGesture(
                        activation: .modifier(.function),
                        points: PathTemplates.up
                    ))
                ),
                directProfile(gesture: .tap(.three, .single)),
            ]
        ))
        capturer = nil

        runtime = nil

        XCTAssertNil(releasedRuntime)
        XCTAssertNil(releasedCapturer)
        XCTAssertFalse(mouse.isActive)
        XCTAssertFalse(modifier.isActive)
        XCTAssertFalse(source.isRunning)
        XCTAssertEqual(mouse.stopCount, 1)
        XCTAssertEqual(modifier.stopCount, 1)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertNil(mouse.onEvent)
        XCTAssertNil(mouse.shouldCapture)
        XCTAssertNil(modifier.onEvent)
    }

    private func makeRuntime(
        source: RuntimeMultitouchSource
    ) -> GestureRuntime {
        GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            multitouchSourceFactory: { source }
        )
    }

    private func configuration(
        revision: UInt64,
        enabled: Bool,
        profiles: [GestureProfile]
    ) -> GestureRuntimeConfiguration {
        GestureRuntimeConfiguration(
            revision: revision,
            isEnabled: enabled,
            profiles: profiles,
            minimumStrokeDistance: 40,
            pathMatchThreshold: 0.7,
            showsHUD: false,
            showsLiveMismatchFeedback: false,
            directTrackpadEnabled: true
        )
    }

    private func directProfile(
        name: String = "Direct",
        gesture: DirectTrackpadGesture
    ) -> GestureProfile {
        GestureProfile(name: name, input: .trackpad(gesture))
    }

    private func shortcutProfile(name: String) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .trackpad(.swipe(.three, .right)),
            action: .shortcut(
                keyCode: 0,
                modifiers: 0,
                display: "A",
                orderedChord: nil
            )
        )
    }

    private func emitTap(
        _ source: RuntimeMultitouchSource,
        startedAt: TimeInterval
    ) {
        source.emit(frame(at: startedAt, points: basePoints()))
        source.emit(frame(
            at: startedAt + 0.07,
            points: basePoints()
        ))
        source.emit(frame(at: startedAt + 0.12, points: [:]))
    }

    private func frame(
        at timestamp: TimeInterval,
        points: [Int: CGPoint]
    ) -> TrackpadTouchFrame {
        TrackpadTouchFrame(
            timestamp: timestamp,
            contacts: points.map {
                TrackpadTouchContact(
                    id: $0.key,
                    phase: .moved,
                    position: $0.value
                )
            }
        )
    }

    private func basePoints() -> [Int: CGPoint] {
        [
            1: CGPoint(x: 0.2, y: 0.4),
            2: CGPoint(x: 0.3, y: 0.5),
            3: CGPoint(x: 0.4, y: 0.4),
        ]
    }

    private func drainMainActor() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

private final class RuntimeMultitouchSource: MultitouchFrameSource {
    var isRunning = false
    var startError: MultitouchSupportAdapterError?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onFrame: (@Sendable (TrackpadTouchFrame) -> Void)?
    private var onFailure:
        (@Sendable (MultitouchSupportAdapterError) -> Void)?

    func start(
        onFrame: @escaping @Sendable (TrackpadTouchFrame) -> Void,
        onFailure: @escaping @Sendable (
            MultitouchSupportAdapterError
        ) -> Void
    ) throws {
        startCount += 1
        if let startError { throw startError }
        isRunning = true
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stop() {
        if isRunning {
            stopCount += 1
        }
        isRunning = false
        onFrame = nil
        onFailure = nil
    }

    func emit(_ frame: TrackpadTouchFrame) {
        onFrame?(frame)
    }

    func fail(_ error: MultitouchSupportAdapterError) {
        onFailure?(error)
    }
}

@MainActor
private final class RuntimePermissionProvider: GesturePermissionProviding {
    var isAccessibilityTrusted: Bool

    init(trusted: Bool) {
        isAccessibilityTrusted = trusted
    }

    func refresh() {}
}

private final class RuntimeMouseEventSource: MouseGestureEventSource {
    var watchedButtons = Set<MouseTriggerButton>()
    var onEvent: ((MouseEventTap.EventKind, UInt64) -> Void)?
    var shouldCapture: ((MouseTriggerButton) -> Bool)?
    private(set) var isActive = false
    private(set) var stopCount = 0
    private(set) var replayedClicks = 0
    private var capturedButtons = Set<MouseTriggerButton>()
    private var interruptedButtons = Set<MouseTriggerButton>()
    private var eventGeneration: UInt64 = 0

    func start() -> Bool {
        eventGeneration &+= 1
        isActive = true
        return true
    }

    func stop() {
        if isActive {
            stopCount += 1
        }
        eventGeneration &+= 1
        isActive = false
        capturedButtons.removeAll()
        interruptedButtons.removeAll()
    }

    func isCurrentEventGeneration(_ generation: UInt64) -> Bool {
        isActive && eventGeneration == generation
    }

    func replayClick(
        button: MouseTriggerButton,
        location: CGPoint
    ) -> Bool {
        replayedClicks += 1
        return true
    }

    func press(
        _ button: MouseTriggerButton,
        at location: CGPoint
    ) -> Bool {
        guard isActive,
              watchedButtons.contains(button),
              !interruptedButtons.contains(button),
              shouldCapture?(button) ?? true
        else {
            return false
        }
        capturedButtons.insert(button)
        onEvent?(.buttonDown(button, location), eventGeneration)
        return true
    }

    func release(
        _ button: MouseTriggerButton,
        at location: CGPoint
    ) {
        if interruptedButtons.remove(button) != nil {
            onEvent?(.drained(button), eventGeneration)
            return
        }
        guard capturedButtons.remove(button) != nil else { return }
        onEvent?(.buttonUp(button, location), eventGeneration)
    }

    func interrupt(
        _ button: MouseTriggerButton,
        at location: CGPoint,
        isStillPressed: Bool = true
    ) {
        guard capturedButtons.remove(button) != nil else { return }
        eventGeneration &+= 1
        onEvent?(.interrupted(button, location), eventGeneration)
        if isStillPressed {
            interruptedButtons.insert(button)
        } else {
            onEvent?(.drained(button), eventGeneration)
        }
    }
}

private final class RuntimeModifierEventSource: ModifierGestureEventSource {
    var watchedKeys = Set<GestureModifierKey>()
    var onEvent:
        (@Sendable (
            ModifierFlagsStateMachine.Event,
            CGPoint,
            UInt64
        ) -> Void)?
    private(set) var isActive = false
    private(set) var stopCount = 0
    var beganEventOnStop: GestureModifierKey?
    private var interruptedKey: GestureModifierKey?
    private var eventGeneration: UInt64 = 0

    func start() -> Result<Void, ModifierEventTapError> {
        eventGeneration &+= 1
        isActive = true
        return .success(())
    }

    func stop() {
        let stoppedGeneration = eventGeneration
        if isActive {
            stopCount += 1
        }
        eventGeneration &+= 1
        isActive = false
        interruptedKey = nil
        if let beganEventOnStop {
            onEvent?(.began(beganEventOnStop), .zero, stoppedGeneration)
        }
    }

    func isCurrentEventGeneration(_ generation: UInt64) -> Bool {
        isActive && eventGeneration == generation
    }

    func press(
        _ key: GestureModifierKey,
        at location: CGPoint = .zero
    ) {
        guard isActive,
              interruptedKey == nil,
              watchedKeys.contains(key)
        else {
            return
        }
        onEvent?(.began(key), location, eventGeneration)
    }

    func release(
        _ key: GestureModifierKey,
        at location: CGPoint = .zero
    ) {
        guard isActive else { return }
        if interruptedKey == key {
            interruptedKey = nil
            onEvent?(.drained(key), location, eventGeneration)
            return
        }
        onEvent?(.ended(key), location, eventGeneration)
    }

    func interrupt(_ key: GestureModifierKey) {
        guard isActive else { return }
        interruptedKey = key
        eventGeneration &+= 1
        onEvent?(.interrupted(key), .zero, eventGeneration)
    }
}

private final class RuntimeTargetCapturer: GestureTargetCapturing,
    @unchecked Sendable
{
    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        GestureTargetSnapshot(
            frontmostWindow: .unavailable(.noFrontmostApplication),
            windowUnderPointer: .unavailable(.noElementAtPointer)
        )
    }
}

private final class RuntimeLifecycleTargetCapturer:
    GestureTargetCapturing,
    @unchecked Sendable
{
    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        GestureTargetSnapshot(
            frontmostWindow: .unavailable(.noFrontmostApplication),
            windowUnderPointer: .unavailable(.noElementAtPointer)
        )
    }
}

private final class MutableRuntimeTargetCapturer: GestureTargetCapturing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedProcessIdentifier: pid_t

    var processIdentifier: pid_t {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedProcessIdentifier
        }
        set {
            lock.lock()
            storedProcessIdentifier = newValue
            lock.unlock()
        }
    }

    init(processIdentifier: pid_t) {
        storedProcessIdentifier = processIdentifier
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        let capturedProcessIdentifier = processIdentifier
        let target = GestureTargetResolution.resolved(
            GestureTargetContext(
                policy: .frontmostWindow,
                identity: GestureTargetIdentity(
                    processIdentifier: capturedProcessIdentifier,
                    bundleIdentifier: "com.example.target"
                ),
                application: nil,
                window: nil
            )
        )
        return GestureTargetSnapshot(
            frontmostWindow: target,
            windowUnderPointer: target
        )
    }
}

@MainActor
private final class RuntimeActionPlatform: GestureTargetActionPlatform {
    private(set) var shortcutCount = 0
    private(set) var shortcutProcessIdentifiers: [pid_t] = []

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext
    ) async throws {
        shortcutCount += 1
        shortcutProcessIdentifiers.append(target.processIdentifier)
    }

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {}
}
