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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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

    func testApplicationScopedMouseDrawOverridesIdenticalGlobalCandidate()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: MutableRuntimeTargetCapturer(
                processIdentifier: 101,
                bundleIdentifier: "com.google.Chrome"
            ),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { source }
        )
        let global = GestureProfile(
            name: "Global Up",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            )),
            action: .none
        )
        let applicationSpecific = GestureProfile(
            name: "Application Up",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            )),
            action: .none,
            scope: .apps(["com.google.Chrome"])
        )
        var matchedIDs: [UUID] = []
        runtime.onMatch = { matchedIDs.append($0.profile.id) }

        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [global, applicationSpecific]
        ))

        XCTAssertTrue(mouse.press(
            .right,
            at: CGPoint(x: 20, y: 300)
        ))
        mouse.release(
            .right,
            at: CGPoint(x: 20, y: 100)
        )
        await drainMainActor()

        XCTAssertEqual(matchedIDs, [applicationSpecific.id])
        guard case .matched(let profileID, _) = runtime.state.lastOutcome else {
            return XCTFail("Expected the application-scoped gesture to match")
        }
        XCTAssertEqual(profileID, applicationSpecific.id)
        XCTAssertEqual(mouse.replayedClicks, 0)
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
                trackpadClickEventTap: RuntimeTrackpadClickSource(),
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

    func testAmbiguityPolicyAndTargetFreezeForMouseAndModifierEvents()
        async throws
    {
        let activations: [DrawActivation] = [
            .mouse(.default),
            .modifier(.function),
        ]
        let transitions: [(GestureAmbiguityResolution, GestureAmbiguityResolution)] = [
            (.reject, .chooseBest),
            (.chooseBest, .reject),
        ]
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sampledPoint = GestureRuntime.appKitLocation(
            fromQuartz: CGPoint(x: 20, y: 200),
            zeroScreenMaxY: screen.frame.maxY
        )

        for activation in activations {
            for (initial, replacement) in transitions {
                let mouse = RuntimeMouseEventSource()
                let modifier = RuntimeModifierEventSource()
                let platform = RuntimeActionPlatform()
                let capturer = MutableRuntimeTargetCapturer(processIdentifier: 101)
                let firstSample = expectation(description: "First draw sampled")
                var pendingSample: XCTestExpectation? = firstSample
                let runtime = GestureRuntime(
                    permissionManager: RuntimePermissionProvider(trusted: true),
                    actionExecutor: ActionExecutor(targetPlatform: platform),
                    targetCapturer: capturer,
                    mouseEventTap: mouse,
                    modifierEventTap: modifier,
                    trackpadClickEventTap: RuntimeTrackpadClickSource(),
                    pointerLocation: {
                        pendingSample?.fulfill()
                        pendingSample = nil
                        return sampledPoint
                    },
                    multitouchSourceFactory: { RuntimeMultitouchSource() }
                )
                let earlier = drawnShortcutProfile(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    name: "Earlier",
                    activation: activation
                )
                let later = drawnShortcutProfile(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    name: "Later",
                    activation: activation
                )
                var matchedIDs: [UUID] = []
                runtime.onMatch = { matchedIDs.append($0.profile.id) }
                try runtime.apply(configuration(
                    revision: 1,
                    enabled: true,
                    profiles: [later, earlier],
                    ambiguityResolution: initial
                ))

                beginDraw(activation, mouse: mouse, modifier: modifier)
                await fulfillment(of: [firstSample], timeout: 1)
                XCTAssertEqual(runtime.currentPath.last, sampledPoint)
                capturer.processIdentifier = 202
                try runtime.apply(configuration(
                    revision: 2,
                    enabled: true,
                    profiles: [later, earlier],
                    ambiguityResolution: replacement
                ))
                endDraw(activation, mouse: mouse, modifier: modifier)
                await drainMainActor()

                if initial == .chooseBest {
                    XCTAssertEqual(matchedIDs, [earlier.id])
                    XCTAssertEqual(platform.shortcutProcessIdentifiers, [101])
                } else {
                    XCTAssertTrue(matchedIDs.isEmpty)
                    XCTAssertTrue(platform.shortcutProcessIdentifiers.isEmpty)
                }

                let secondSample = expectation(description: "Second draw sampled")
                pendingSample = secondSample
                beginDraw(activation, mouse: mouse, modifier: modifier)
                await fulfillment(of: [secondSample], timeout: 1)
                XCTAssertEqual(runtime.currentPath.last, sampledPoint)
                endDraw(activation, mouse: mouse, modifier: modifier)
                await drainMainActor()

                if replacement == .chooseBest {
                    XCTAssertEqual(matchedIDs, [earlier.id])
                    XCTAssertEqual(platform.shortcutProcessIdentifiers, [202])
                } else {
                    XCTAssertEqual(matchedIDs, [earlier.id])
                    XCTAssertEqual(platform.shortcutProcessIdentifiers, [101])
                }
            }
        }
    }

    func testDrawnDiagnosticsReportsChooseBestWithoutExecutingAction()
        async throws
    {
        let mouse = RuntimeMouseEventSource()
        let platform = RuntimeActionPlatform()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sampledPoint = GestureRuntime.appKitLocation(
            fromQuartz: CGPoint(x: 20, y: 200),
            zeroScreenMaxY: screen.frame.maxY
        )
        let sampled = expectation(description: "Diagnostic draw sampled")
        var pendingSample: XCTestExpectation? = sampled
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            pointerLocation: {
                pendingSample?.fulfill()
                pendingSample = nil
                return sampledPoint
            },
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        let profiles = [
            drawnShortcutProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Later",
                activation: .mouse(.default)
            ),
            drawnShortcutProfile(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Earlier",
                activation: .mouse(.default)
            ),
        ]
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: profiles,
            ambiguityResolution: .chooseBest
        ))
        let diagnostic = runtime.beginDiagnostics()
        defer { diagnostic.end() }

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        await fulfillment(of: [sampled], timeout: 1)
        XCTAssertEqual(runtime.currentPath.last, sampledPoint)
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        XCTAssertEqual(runtime.lastDrawDiagnostic?.evaluation?.decision, .accepted)
        XCTAssertEqual(
            runtime.lastDrawDiagnostic?.evaluation?.acceptedCandidate?.profile.id,
            profiles[1].id
        )
        XCTAssertEqual(platform.shortcutCount, 0)
    }

    // MARK: - Secondary action (left-click chord)

    func testChordClickRunsOnlySecondaryAction() async throws {
        var profile = drawnShortcutProfile(
            id: UUID(),
            name: "Paste",
            activation: .mouse(.default)
        )
        profile.secondaryAction = .shortcut(keyCode: 1, modifiers: 0, display: "S")

        let draw = try await drawUpWithRightButton(
            profiles: [profile],
            clickingLeft: true
        )

        XCTAssertEqual(
            draw.mouse.lastCaptureDecision,
            .capture(acceptsChordClick: true)
        )
        XCTAssertEqual(draw.platform.shortcutKeyCodes, [1])
        XCTAssertEqual(draw.matches.map(\.usesSecondaryAction), [true])
        XCTAssertEqual(draw.mouse.replayedClicks, 0)
    }

    func testDrawWithoutChordClickRunsPrimaryAction() async throws {
        var profile = drawnShortcutProfile(
            id: UUID(),
            name: "Paste",
            activation: .mouse(.default)
        )
        profile.secondaryAction = .shortcut(keyCode: 1, modifiers: 0, display: "S")

        let draw = try await drawUpWithRightButton(
            profiles: [profile],
            clickingLeft: false
        )

        XCTAssertEqual(draw.platform.shortcutKeyCodes, [0])
        XCTAssertEqual(draw.matches.map(\.usesSecondaryAction), [false])
    }

    func testChordClickOnGestureWithoutSecondaryActionRunsNothing()
        async throws
    {
        let plain = drawnShortcutProfile(
            id: UUID(),
            name: "Copy",
            activation: .mouse(.default)
        )
        let other = GestureProfile(
            name: "Paste",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.down
            )),
            secondaryAction: .shortcut(keyCode: 1, modifiers: 0, display: "S")
        )

        let draw = try await drawUpWithRightButton(
            profiles: [plain, other],
            clickingLeft: true
        )

        // The path still resolves to the gesture it matches; no fallback to
        // its primary action and no lower-scoring gesture takes over.
        XCTAssertTrue(draw.platform.shortcutKeyCodes.isEmpty)
        XCTAssertTrue(draw.matches.isEmpty)
        XCTAssertEqual(
            draw.runtime.state.lastOutcome,
            .secondaryActionUnavailable(profileID: plain.id)
        )
    }

    func testChordCaptureIgnoresSecondaryActionsOutsideTargetApplication()
        async throws
    {
        let plain = drawnShortcutProfile(
            id: UUID(),
            name: "Copy",
            activation: .mouse(.default)
        )
        let elsewhere = GestureProfile(
            name: "Paste",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.down
            )),
            secondaryAction: .shortcut(keyCode: 1, modifiers: 0, display: "S"),
            scope: .apps(["com.example.elsewhere"])
        )

        let draw = try await drawUpWithRightButton(
            profiles: [plain, elsewhere],
            clickingLeft: true
        )

        XCTAssertTrue(draw.mouse.installedChordClicks)
        XCTAssertEqual(
            draw.mouse.lastCaptureDecision,
            .capture(acceptsChordClick: false)
        )
        // The left click stayed with the app, so the primary action runs.
        XCTAssertEqual(draw.platform.shortcutKeyCodes, [0])
    }

    func testChordClickWithoutStrokeCancelsWithoutReplayingClick()
        async throws
    {
        let mouse = RuntimeMouseEventSource()
        let platform = RuntimeActionPlatform()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let pressPoint = CGPoint(x: 20, y: 300)
        let sampledPoint = GestureRuntime.appKitLocation(
            fromQuartz: pressPoint,
            zeroScreenMaxY: screen.frame.maxY
        )
        let sampled = expectation(description: "Press sampled")
        var pendingSample: XCTestExpectation? = sampled
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            pointerLocation: {
                pendingSample?.fulfill()
                pendingSample = nil
                return sampledPoint
            },
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        var profile = drawnShortcutProfile(
            id: UUID(),
            name: "Paste",
            activation: .mouse(.default)
        )
        profile.secondaryAction = .shortcut(keyCode: 1, modifiers: 0, display: "S")
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [profile]
        ))

        XCTAssertTrue(mouse.press(.right, at: pressPoint))
        await fulfillment(of: [sampled], timeout: 1)
        XCTAssertTrue(mouse.clickLeft())
        await drainMainActor()
        mouse.release(.right, at: pressPoint)
        await drainMainActor()

        XCTAssertEqual(mouse.replayedClicks, 0)
        XCTAssertEqual(runtime.state.lastOutcome, .cancelled)
        XCTAssertEqual(platform.shortcutCount, 0)
    }

    func testMouseTapInstallsChordMaskOnlyWhileSecondaryActionsExist()
        throws
    {
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        let plain = drawnShortcutProfile(
            id: UUID(),
            name: "Copy",
            activation: .mouse(.default)
        )
        var chorded = plain
        chorded.secondaryAction = GestureAction.none
        var modifierOnly = drawnShortcutProfile(
            id: UUID(),
            name: "Fn",
            activation: .modifier(.function)
        )
        modifierOnly.secondaryAction = GestureAction.none

        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [plain, modifierOnly]
        ))
        XCTAssertTrue(mouse.isActive)
        XCTAssertFalse(mouse.installedChordClicks)
        let stopsBeforeChord = mouse.stopCount

        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [chorded]
        ))
        XCTAssertTrue(mouse.installedChordClicks)
        XCTAssertEqual(mouse.stopCount, stopsBeforeChord + 1)

        try runtime.apply(configuration(
            revision: 3,
            enabled: true,
            profiles: [plain]
        ))
        XCTAssertFalse(mouse.installedChordClicks)
    }

    private struct RightButtonDraw {
        let runtime: GestureRuntime
        let mouse: RuntimeMouseEventSource
        let platform: RuntimeActionPlatform
        let matches: [GestureMatchResult]
    }

    private func drawUpWithRightButton(
        profiles: [GestureProfile],
        clickingLeft: Bool
    ) async throws -> RightButtonDraw {
        let mouse = RuntimeMouseEventSource()
        let platform = RuntimeActionPlatform()
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let sampledPoint = GestureRuntime.appKitLocation(
            fromQuartz: CGPoint(x: 20, y: 200),
            zeroScreenMaxY: screen.frame.maxY
        )
        let sampled = expectation(description: "Draw sampled")
        var pendingSample: XCTestExpectation? = sampled
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            pointerLocation: {
                pendingSample?.fulfill()
                pendingSample = nil
                return sampledPoint
            },
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        var matches: [GestureMatchResult] = []
        runtime.onMatch = { matches.append($0) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: profiles
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        await fulfillment(of: [sampled], timeout: 1)
        if clickingLeft {
            mouse.clickLeft()
            await drainMainActor()
        }
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        return RightButtonDraw(
            runtime: runtime,
            mouse: mouse,
            platform: platform,
            matches: matches
        )
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
        XCTAssertEqual(runtime.lastDrawDiagnostic?.configurationRevision, 1)
        let diagnosticID = runtime.lastDrawDiagnostic?.id
        await drainMainActor()
        XCTAssertEqual(runtime.lastDrawDiagnostic?.id, diagnosticID)
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
        XCTAssertNil(runtime.lastDrawDiagnostic)

        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        modifier.release(.function)
        await drainMainActor()

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 10, y: 10)))
        await drainMainActor()
        XCTAssertEqual(runtime.state.activeSession?.source, .mouse(.right))
        mouse.release(.right, at: CGPoint(x: 10, y: 10))
        await drainMainActor()
    }

    func testDiagnosticModifierCancellationProducesOneLogEntry() async throws {
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            modifierEventTap: modifier,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        let profile = GestureProfile(
            name: "Modifier",
            input: .drawn(DrawnGesture(
                activation: .modifier(.option),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 17,
            enabled: true,
            profiles: [profile]
        ))
        let diagnosticSession = runtime.beginDiagnostics()
        defer { diagnosticSession.end() }

        modifier.press(.option, at: CGPoint(x: 10, y: 10))
        await drainMainActor()
        modifier.interrupt(.option)
        await drainMainActor()

        let diagnostic = try XCTUnwrap(runtime.lastDrawDiagnostic)
        XCTAssertEqual(diagnostic.outcome, .cancelled)
        XCTAssertNil(diagnostic.evaluation)
        XCTAssertEqual(diagnostic.configurationRevision, 17)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GestureRuntimeCancelLog-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureTestLogStore(
            logURL: directory.appendingPathComponent("log.jsonl")
        )
        try store.append(GestureTestLogEntry(
            sessionID: UUID(),
            cancelledDiagnostic: diagnostic
        ))

        let entries = try store.readEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .cancelled)
        XCTAssertNil(entries.first?.decision)
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
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

    // MARK: - Physical clicks

    func testPressedTouchSequenceNeverYieldsTap() async throws {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let tap = directProfile(name: "Tap", gesture: .tap(.three, .single))
        let runtime = makeRuntime(source: source, click: click)
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [tap]
        ))

        XCTAssertTrue(click.isActive)
        XCTAssertFalse(click.installedIntercepts)
        source.emit(frame(at: 1, points: basePoints()))
        XCTAssertFalse(click.press())
        source.emit(frame(at: 1.07, points: basePoints()))
        source.emit(frame(at: 1.12, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [])
        XCTAssertEqual(
            runtime.lastTrackpadOutcome,
            .rejected(.physicallyPressed)
        )
    }

    func testClickGestureRunsAtPressAndOwnsItsSequence() async throws {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let tap = directProfile(name: "Tap", gesture: .tap(.three, .single))
        let pressed = directProfile(
            name: "Click",
            gesture: .click(.three, .single)
        )
        let runtime = makeRuntime(source: source, click: click)
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [tap, pressed]
        ))

        XCTAssertTrue(click.installedIntercepts)
        XCTAssertFalse(click.press(), "No resting fingers: a pointer click")
        source.emit(frame(at: 1, points: basePoints()))
        source.emit(frame(at: 1.07, points: basePoints()))
        XCTAssertTrue(click.press())
        source.emit(frame(at: 1.1, points: basePoints()))
        await drainMainActor()

        XCTAssertEqual(matches, [pressed.id])

        source.emit(frame(at: 1.12, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [pressed.id])
        XCTAssertEqual(
            runtime.lastTrackpadOutcome,
            .matched(profileID: pressed.id, score: nil)
        )
    }

    func testPressWithUnconfiguredFingerCountReachesApplications()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let fourFingers = directProfile(
            name: "Four",
            gesture: .click(.four, .single)
        )
        let runtime = makeRuntime(source: source, click: click)
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [fourFingers]
        ))

        source.emit(frame(at: 1, points: basePoints()))
        XCTAssertFalse(click.press())
        source.emit(frame(at: 1.07, points: basePoints()))
        source.emit(frame(at: 1.12, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [])
    }

    func testSecondPressWithinIntervalRunsDoubleClick() async throws {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let single = directProfile(
            name: "Single",
            gesture: .click(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .click(.three, .double)
        )
        let runtime = makeRuntime(
            source: source,
            click: click,
            doubleClickInterval: 5
        )
        var matches: [UUID] = []
        runtime.onMatch = { matches.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        source.emit(frame(at: 1, points: basePoints()))
        XCTAssertTrue(click.press())
        source.emit(frame(at: 1.05, points: basePoints()))
        source.emit(frame(at: 1.1, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [])

        source.emit(frame(at: 1.3, points: basePoints()))
        XCTAssertTrue(click.press())
        source.emit(frame(at: 1.35, points: basePoints()))
        source.emit(frame(at: 1.4, points: [:]))
        await drainMainActor()

        XCTAssertEqual(matches, [double.id])
    }

    func testLoneClickResolvesAfterDoubleClickInterval() async throws {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let single = directProfile(
            name: "Single",
            gesture: .click(.three, .single)
        )
        let double = directProfile(
            name: "Double",
            gesture: .click(.three, .double)
        )
        let runtime = makeRuntime(
            source: source,
            click: click,
            doubleClickInterval: 0.05
        )
        let resolved = expectation(description: "single click")
        var matches: [UUID] = []
        runtime.onMatch = {
            matches.append($0.profile.id)
            resolved.fulfill()
        }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [single, double]
        ))

        source.emit(frame(at: 1, points: basePoints()))
        XCTAssertTrue(click.press())
        source.emit(frame(at: 1.05, points: basePoints()))
        await drainMainActor()

        XCTAssertEqual(matches, [], "Waits for a possible second press")
        await fulfillment(of: [resolved], timeout: 2)
        XCTAssertEqual(matches, [single.id])
    }

    func testClickTapFiltersOnlyWhileClickGesturesExist() throws {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let runtime = makeRuntime(source: source, click: click)

        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [shortcutProfile(name: "Swipe")]
        ))
        XCTAssertFalse(click.isActive)
        XCTAssertEqual(runtime.state.inputs.trackpadClick, .notRequested)

        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [directProfile(gesture: .tap(.three, .single))]
        ))
        XCTAssertTrue(click.isActive)
        XCTAssertFalse(click.installedIntercepts)
        XCTAssertEqual(runtime.state.inputs.trackpadClick, .listening)

        try runtime.apply(configuration(
            revision: 3,
            enabled: true,
            profiles: [directProfile(gesture: .click(.three, .double))]
        ))
        XCTAssertTrue(click.isActive)
        XCTAssertTrue(click.installedIntercepts)

        try runtime.apply(configuration(
            revision: 4,
            enabled: false,
            profiles: [directProfile(gesture: .click(.three, .double))]
        ))
        XCTAssertFalse(click.isActive)
    }

    func testDiagnosticsReportsUnconfiguredClickWithoutLeakingIt()
        async throws
    {
        let source = RuntimeMultitouchSource()
        let click = RuntimeTrackpadClickSource()
        let runtime = makeRuntime(source: source, click: click)
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [directProfile(gesture: .tap(.three, .single))]
        ))
        let diagnostic = runtime.beginDiagnostics()

        XCTAssertTrue(click.installedIntercepts)
        source.emit(frame(at: 1, points: basePoints()))
        XCTAssertTrue(click.press())
        source.emit(frame(at: 1.05, points: basePoints()))
        await drainMainActor()

        XCTAssertEqual(runtime.lastTrackpadOutcome, .noMatch)
        diagnostic.end()
    }

    private func makeRuntime(
        source: RuntimeMultitouchSource,
        click: RuntimeTrackpadClickSource,
        doubleClickInterval: TimeInterval = 0.30
    ) -> GestureRuntime {
        GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            trackpadClickEventTap: click,
            doubleClickInterval: doubleClickInterval,
            multitouchSourceFactory: { source }
        )
    }

    private func makeRuntime(
        source: RuntimeMultitouchSource
    ) -> GestureRuntime {
        GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: RuntimeTargetCapturer(),
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { source }
        )
    }

    // MARK: - Button mappings

    func testButtonMappingClickRunsActionInsteadOfNativeClick() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let mapping = buttonMapping(name: "Back")
        var matchedIDs: [UUID] = []
        runtime.onMatch = { matchedIDs.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mapping]
        ))
        XCTAssertEqual(mouse.watchedButtons, [.sideBack])

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()

        XCTAssertEqual(matchedIDs, [mapping.id])
        XCTAssertEqual(platform.shortcutProcessIdentifiers, [101])
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testButtonMappingWithoutDrawnCandidateIgnoresMovement()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let mapping = buttonMapping(name: "Back")
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mapping]
        ))

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        await drainMainActor()
        XCTAssertTrue(runtime.currentPath.count <= 1)
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .matched(profileID: mapping.id, score: nil)
        )
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testStrokeOnMappedButtonDrawsAndSkipsMapping() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let drawn = GestureProfile(
            name: "Up",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger(button: .sideBack)),
                points: PathTemplates.up
            )),
            action: .none
        )
        let mapping = buttonMapping(name: "Back")
        var matchedIDs: [UUID] = []
        runtime.onMatch = { matchedIDs.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [drawn, mapping]
        ))

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(matchedIDs, [mapping.id])

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        XCTAssertEqual(matchedIDs, [mapping.id, drawn.id])
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testMostSpecificButtonMappingRunsAndTiesRunNothing()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let global = buttonMapping(name: "Global", keyCode: 1)
        let application = buttonMapping(
            name: "Application",
            keyCode: 2,
            scope: .apps(["com.example.target"])
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [global, application]
        ))

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutKeyCodes, [2])

        let duplicate = buttonMapping(
            name: "Duplicate",
            keyCode: 3,
            scope: .apps(["com.example.target"])
        )
        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [global, application, duplicate]
        ))
        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()

        XCTAssertEqual(
            runtime.state.lastOutcome,
            .conflict([application.id, duplicate.id])
        )
        XCTAssertEqual(platform.shortcutKeyCodes, [2])
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testUnmappedApplicationKeepsNativeSideButton() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime(
            bundleIdentifier: "com.google.Chrome"
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [buttonMapping(
                name: "Finder Back",
                scope: .apps(["com.apple.finder"])
            )]
        ))

        XCTAssertFalse(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()

        XCTAssertEqual(platform.shortcutCount, 0)
        XCTAssertEqual(mouse.replayedClicks, 0)
        XCTAssertNil(runtime.state.lastOutcome)
    }

    func testGlobalButtonMappingFollowsItsOwnSuppressionKind()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let mapping = buttonMapping(name: "Back")
        func rules(_ kinds: Set<GestureInputKind>) -> GestureAppRules {
            GestureAppRules(
                policies: [AppGesturePolicy(
                    bundleIdentifier: "com.example.target",
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: kinds)
                )],
                groups: []
            )
        }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [mapping],
            appRules: rules([.mouseDrawing])
        ))
        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)

        try runtime.apply(configuration(
            revision: 2,
            enabled: true,
            profiles: [mapping],
            appRules: rules([.mouseButton])
        ))
        XCTAssertFalse(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
    }

    func testModifierMappingRunsOnlyWithExactlyItsModifierHeld()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [buttonMapping(name: "Command Back", modifier: .command)]
        ))

        XCTAssertFalse(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        XCTAssertFalse(mouse.press(
            .sideBack,
            at: CGPoint(x: 20, y: 300),
            flags: [.maskCommand, .maskShift]
        ))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 0)

        // Caps Lock is not a gesture modifier and does not break the match.
        XCTAssertTrue(mouse.press(
            .sideBack,
            at: CGPoint(x: 20, y: 300),
            flags: [.maskCommand, .maskAlphaShift]
        ))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testPlainAndModifierMappingsShareButtonWithoutConflict()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                buttonMapping(name: "Back", keyCode: 1),
                buttonMapping(
                    name: "Command Back",
                    keyCode: 2,
                    modifier: .command
                ),
            ]
        ))

        XCTAssertTrue(mouse.press(.sideBack, at: CGPoint(x: 20, y: 300)))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        XCTAssertTrue(mouse.press(
            .sideBack,
            at: CGPoint(x: 20, y: 300),
            flags: .maskCommand
        ))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()

        XCTAssertEqual(platform.shortcutKeyCodes, [1, 2])
    }

    func testDrawnGestureKeepsReplayingWhenHeldModifierMissesMapping()
        async throws
    {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let drawn = GestureProfile(
            name: "Up",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger(button: .sideBack)),
                points: PathTemplates.up
            )),
            action: .none
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [
                drawn,
                buttonMapping(name: "Command Back", modifier: .command),
            ]
        ))

        XCTAssertTrue(mouse.press(
            .sideBack,
            at: CGPoint(x: 20, y: 300),
            flags: .maskAlternate
        ))
        mouse.release(.sideBack, at: CGPoint(x: 20, y: 300))
        await drainMainActor()

        XCTAssertEqual(platform.shortcutCount, 0)
        XCTAssertEqual(mouse.replayedClicks, 1)
    }

    func testRightButtonMappingIsInert() throws {
        let (runtime, mouse, _) = makeButtonMappingRuntime()
        let state = try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [buttonMapping(name: "Right", button: .right)]
        ))

        XCTAssertTrue(mouse.watchedButtons.isEmpty)
        XCTAssertEqual(state.inputs.mouse, .notRequested)
    }

    func testRightWheelRepeatsAndSuppressesClickReplay() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let combo = combinationProfile(action: .wheelUp)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        XCTAssertTrue(mouse.interceptsScroll)
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        XCTAssertTrue(mouse.scroll(.up, at: CGPoint(x: 200, y: 200)))
        XCTAssertFalse(mouse.scroll(.down, at: CGPoint(x: 200, y: 200)))
        XCTAssertTrue(mouse.scroll(.up, at: CGPoint(x: 200, y: 200)))
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 2)
        XCTAssertEqual(mouse.replayedClicks, 0)
        XCTAssertEqual(runtime.state.lastOutcome, .matched(profileID: combo.id, score: nil))
    }

    func testLogitechSmoothWheelRunsShortcutWithoutRepeatingEveryFrame() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let combo = combinationProfile(action: .wheelUp)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        let location = CGPoint(x: 200, y: 200)
        XCTAssertTrue(mouse.press(.right, at: location))
        for frame in 0...10 {
            XCTAssertTrue(mouse.scroll(.up, at: location, preciseTimestamp: 1 + Double(frame) / 100))
        }
        mouse.release(.right, at: location)
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
        // A new hold fires immediately, even within the previous hold's cooldown.
        XCTAssertTrue(mouse.press(.right, at: location))
        XCTAssertTrue(mouse.scroll(.up, at: location, preciseTimestamp: 1.11))
        mouse.release(.right, at: location)
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 2)
    }

    func testRightLeftCombinationNeedsNoStrokeAndFiresOncePerHold() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let combo = combinationProfile(action: .leftClick)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        XCTAssertTrue(mouse.clickLeft())
        XCTAssertTrue(mouse.clickLeft())
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testUncombinedRightClickStillReplaysContextMenu() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        try runtime.apply(configuration(revision: 1, enabled: true,
                                        profiles: [combinationProfile(action: .wheelUp)]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 0)
        XCTAssertEqual(mouse.replayedClicks, 1)
    }

    func testCombinationFiltersAppScopeBeforeCapturingHeldRight() throws {
        let (runtime, mouse, _) = makeButtonMappingRuntime()
        let combo = combinationProfile(action: .leftClick, scope: .apps(["com.other"]))
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        XCTAssertFalse(mouse.clickLeft())
    }

    func testAppCombinationOverridesGlobalAndDuplicateMappingConflicts() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let global = combinationProfile(action: .leftClick)
        let scoped = combinationProfile(action: .leftClick, scope: .apps(["com.example.target"]))
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [global, scoped]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.clickLeft()
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(runtime.state.lastOutcome, .matched(profileID: scoped.id, score: nil))
        let duplicate = combinationProfile(action: .leftClick, scope: scoped.scope)
        try runtime.apply(configuration(revision: 2, enabled: true, profiles: [global, scoped, duplicate]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.clickLeft()
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(runtime.state.lastOutcome, .conflict([scoped.id, duplicate.id]))
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testEdgeRightClickAndInteriorNativeClick() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let combo = combinationProfile(edge: .top, action: .rightClick)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        let frame = CGDisplayBounds(CGMainDisplayID())
        let edge = CGPoint(x: frame.midX, y: frame.minY + 1)
        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: frame.midX, y: frame.midY)))
        XCTAssertTrue(mouse.press(.right, at: edge))
        mouse.release(.right, at: edge)
        await drainMainActor()
        XCTAssertEqual(platform.shortcutCount, 1)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testEdgeWheelResolvesAppScopeAndReplaysUnmappedWheel() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        let combo = combinationProfile(edge: .top, action: .wheelUp)
        let frame = CGDisplayBounds(CGMainDisplayID())
        let edge = CGPoint(x: frame.midX, y: frame.minY + 1)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        XCTAssertFalse(mouse.press(.right, at: edge), "Wheel-only edges must not capture right clicks")
        XCTAssertFalse(mouse.scroll(.up, at: CGPoint(x: frame.midX, y: frame.midY)))
        XCTAssertTrue(mouse.scroll(.up, at: edge))
        await waitForCombination { platform.shortcutCount == 1 }
        XCTAssertEqual(mouse.replayedScrolls, 0)
        let otherApp = combinationProfile(edge: .top, action: .wheelUp, scope: .apps(["com.other"]))
        try runtime.apply(configuration(revision: 2, enabled: true, profiles: [otherApp]))
        XCTAssertTrue(mouse.scroll(.up, at: edge))
        await waitForCombination { mouse.replayedScrolls == 1 }
        XCTAssertEqual(platform.shortcutCount, 1)
    }

    func testEdgeWheelOnlyRunsMappedDirectionAndLimitsActionRate() async throws {
        var now: TimeInterval = 10
        let (runtime, mouse, platform) = makeButtonMappingRuntime(wheelActionTime: { now })
        let combo = combinationProfile(edge: .top, action: .wheelUp)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [combo]))
        let frame = CGDisplayBounds(CGMainDisplayID())
        let edge = CGPoint(x: frame.midX, y: frame.minY + 1)
        var matches = 0
        runtime.onMatch = { _ in matches += 1 }
        XCTAssertFalse(mouse.scroll(.down, at: edge))
        XCTAssertTrue(mouse.scroll(.up, at: edge))
        await waitForCombination { matches == 1 }
        // Include an app-scoped opposite mapping as a FIFO replay barrier.
        let otherApp = combinationProfile(edge: .top, action: .wheelDown, scope: .apps(["com.other"]))
        try runtime.apply(configuration(revision: 2, enabled: true, profiles: [combo, otherApp]))
        // A rapid burst is consumed without dispatching more actions, for both
        // precise and line-based wheels. Direction filtering stays exact.
        now = 10.05
        for _ in 0..<30 { XCTAssertTrue(mouse.scroll(.up, at: edge, preciseTimestamp: 100)) }
        for _ in 0..<30 { XCTAssertTrue(mouse.scroll(.up, at: edge)) }
        // FIFO queue barrier: an unmapped-app event is replayed after the burst.
        XCTAssertTrue(mouse.scroll(.down, at: edge))
        await waitForCombination { mouse.replayedScrolls == 1 }
        XCTAssertEqual(matches, 1)
        XCTAssertEqual(platform.shortcutCount, 1)
        now = 10.11
        XCTAssertTrue(mouse.scroll(.up, at: edge))
        await waitForCombination { matches == 2 && platform.shortcutCount == 2 }
        XCTAssertEqual(platform.shortcutCount, 2)
    }

    func testCombinationSuppressionAndPausePreventCapture() throws {
        let (runtime, mouse, _) = makeButtonMappingRuntime()
        let rules = GestureAppRules(policies: [AppGesturePolicy(
            bundleIdentifier: "com.example.target",
            suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.mouseCombination])
        )], groups: [])
        try runtime.apply(configuration(revision: 1, enabled: true,
            profiles: [combinationProfile(action: .wheelUp)], appRules: rules))
        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        try runtime.apply(configuration(revision: 2, enabled: false,
                                        profiles: [combinationProfile(action: .wheelUp)]))
        XCTAssertFalse(mouse.scroll(.up, at: CGPoint(x: 200, y: 200)))
    }

    func testEdgeWheelNeverHoldsTheSessionGate() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [
            combinationProfile(edge: .top, action: .wheelUp),
            combinationProfile(action: .leftClick),
        ]))
        let frame = CGDisplayBounds(CGMainDisplayID())
        let edge = CGPoint(x: frame.midX, y: frame.minY + 1)
        let interior = CGPoint(x: frame.midX, y: frame.midY)
        // A tick admitted and then dropped by a reinstalling tap leaves nothing behind.
        XCTAssertEqual(mouse.shouldCaptureScroll?(.up, edge), true)
        // A tick still resolving its target does not block a right press.
        XCTAssertTrue(mouse.scroll(.up, at: edge))
        XCTAssertTrue(mouse.press(.right, at: interior))
        XCTAssertTrue(mouse.clickLeft())
        mouse.release(.right, at: interior)
        await waitForCombination { platform.shortcutCount == 2 }
        XCTAssertEqual(mouse.replayedScrolls, 0)
    }

    func testSwallowedWheelIsReplayedWhenNoCombinationRuns() async throws {
        let (runtime, mouse, platform) = makeButtonMappingRuntime()
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [
            combinationProfile(edge: .top, action: .wheelUp),
            combinationProfile(action: .wheelUp),
        ]))
        let frame = CGDisplayBounds(CGMainDisplayID())
        let edge = CGPoint(x: frame.midX, y: frame.minY + 1)
        let interior = CGPoint(x: frame.midX, y: frame.midY)
        // Delivered after the tap was reinstalled: generation 0 predates every install.
        mouse.deliverSwallowedScroll(.up, at: edge, generation: 0)
        await waitForCombination { mouse.replayedScrolls == 1 }
        // Decided as held, delivered with no matching held combination.
        XCTAssertTrue(mouse.press(.right, at: interior))
        mouse.deliverSwallowedScroll(.down, at: interior)
        await waitForCombination { mouse.replayedScrolls == 2 }
        mouse.release(.right, at: interior)
        // Decided as held, delivered after the release.
        mouse.deliverSwallowedScroll(.up, at: interior)
        await waitForCombination { mouse.replayedScrolls == 3 }
        XCTAssertEqual(platform.shortcutCount, 0)
    }

    func testEdgeOnlyCombinationsSkipTargetLookupForOtherPresses() async throws {
        let mouse = RuntimeMouseEventSource()
        let capturer = IdentifyingRuntimeTargetCapturer(
            processIdentifier: 101,
            bundleIdentifier: "com.example.target"
        )
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [
            combinationProfile(edge: .top, action: .wheelUp),
            combinationProfile(edge: .left, action: .rightClick),
        ]))
        let frame = CGDisplayBounds(CGMainDisplayID())
        let top = CGPoint(x: frame.midX, y: frame.minY + 1)
        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: frame.midX, y: frame.midY)))
        XCTAssertFalse(mouse.press(.right, at: top), "Wheel-only edges never reserve a press")
        XCTAssertEqual(capturer.identityCount, 0)
        XCTAssertEqual(capturer.windowCaptureCount, 0)
        let left = CGPoint(x: frame.minX + 1, y: frame.midY)
        XCTAssertTrue(mouse.press(.right, at: left))
        mouse.release(.right, at: left)
        await drainMainActor()
        XCTAssertEqual(capturer.identityCount, 1)
        XCTAssertEqual(platform.shortcutCount, 1)
    }

    private func waitForCombination(_ predicate: () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for combination routing")
    }

    private func combinationProfile(
        edge: MouseScreenEdge? = nil, action: MouseCombinationAction, scope: AppScope = .global
    ) -> GestureProfile {
        GestureProfile(name: "Combo", input: .mouseCombination(MouseCombinationGesture(edge: edge, action: action)),
                       action: .shortcut(keyCode: 1, modifiers: 0, display: "S", orderedChord: nil), scope: scope)
    }

    private func makeButtonMappingRuntime(
        bundleIdentifier: String = "com.example.target",
        wheelActionTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        dragScrollPoster: ScrollEventPosting = DragScrollRuntimePoster(),
        dragScrollEventFactory: @escaping (MouseDragScrollSession.Frame) -> CGEvent? = {
            CGScrollEventPoster.makeEvent(deltaY: $0.y, deltaX: $0.x, flags: [], phase: $0.phase)
        }
    ) -> (GestureRuntime, RuntimeMouseEventSource, RuntimeActionPlatform) {
        let mouse = RuntimeMouseEventSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(
                processIdentifier: 101,
                bundleIdentifier: bundleIdentifier
            ),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            pointerLocation: pointerLocation,
            wheelActionTime: wheelActionTime,
            dragScrollPoster: dragScrollPoster,
            dragScrollEventFactory: dragScrollEventFactory,
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        return (runtime, mouse, platform)
    }

    private func buttonMapping(
        name: String,
        button: MouseTriggerButton = .sideBack,
        keyCode: UInt16 = 1,
        modifier: GestureModifierKey? = nil,
        scope: AppScope = .global
    ) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .mouseButton(MouseButtonGesture(
                button: button,
                modifier: modifier
            )),
            action: .shortcut(
                keyCode: keyCode,
                modifiers: 0,
                display: "S",
                orderedChord: nil
            ),
            scope: scope
        )
    }

    func testDragScrollPostsPairedPhasesAndOwnsSubsequentCombinationInput() async throws {
        var point = CGPoint.zero
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, platform) = makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
        let profile = dragScrollProfile()
        try runtime.apply(configuration(revision: 1, enabled: true,
            profiles: [profile, combinationProfile(action: .wheelUp), combinationProfile(action: .leftClick)]))
        let origin = CGPoint(x: 200, y: 200)
        point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
        XCTAssertTrue(mouse.press(.right, at: origin))
        await drainMainActor()
        point.x += 5
        await waitForCombination { poster.phases == [1] }
        XCTAssertEqual(runtime.state.lastOutcome, .matched(profileID: profile.id, score: nil))
        XCTAssertEqual(runtime.lastMatch?.profile.id, profile.id)
        point.x += 10
        point.y += 10
        await waitForCombination { poster.phases.contains(2) }
        XCTAssertTrue(runtime.currentPath.isEmpty)
        XCTAssertFalse(mouse.scroll(.up, at: origin))
        mouse.clickLeft()
        mouse.release(.right, at: CGPoint(x: origin.x + 15, y: origin.y - 10))
        await drainMainActor()
        XCTAssertEqual(poster.phases, [1, 2, 4])
        XCTAssertEqual(poster.deltas.last?.x, 0)
        XCTAssertEqual(poster.deltas.dropLast().last, CGPoint(x: 10, y: -10))
        XCTAssertEqual(platform.shortcutCount, 0)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testDragScrollFastFirstMovementAtReleaseRetainsDistanceBeyondDeadzone() async throws {
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, _) = makeButtonMappingRuntime(dragScrollPoster: poster)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [dragScrollProfile()]))
        // Both callbacks enqueue before any sampling task, so up is the first moved point.
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.release(.right, at: CGPoint(x: 214, y: 200))
        await drainMainActor()
        XCTAssertEqual(poster.phases, [1, 4])
        XCTAssertEqual(poster.deltas, [CGPoint(x: 10, y: 0), .zero])
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testDragScrollCancelsOnPermissionLossAndShortClickReplays() async throws {
        var point = CGPoint.zero
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, _) = makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [dragScrollProfile()]))
        let origin = CGPoint(x: 200, y: 200)
        point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
        XCTAssertTrue(mouse.press(.right, at: origin))
        mouse.release(.right, at: origin)
        await drainMainActor()
        XCTAssertEqual(mouse.replayedClicks, 1)
        XCTAssertTrue(poster.phases.isEmpty)
        XCTAssertTrue(mouse.press(.right, at: origin))
        await drainMainActor()
        point.x += 5
        await waitForCombination { poster.phases == [1] }
        runtime.accessibilityTrustDidChange(false)
        XCTAssertEqual(poster.phases, [1, 8])
        XCTAssertNil(runtime.state.activeSession)
    }

    func testDragScrollDiagnosticNeverCreatesOrPostsEvents() async throws {
        var point = CGPoint.zero
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, _) = makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
        let profile = dragScrollProfile()
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [profile]))
        let diagnostic = runtime.beginDiagnostics()
        defer { diagnostic.end() }
        let origin = CGPoint(x: 200, y: 200)
        point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
        XCTAssertTrue(mouse.press(.right, at: origin))
        await drainMainActor()
        point.x += 5
        await waitForCombination { runtime.state.lastOutcome == .matched(profileID: profile.id, score: nil) }
        mouse.release(.right, at: CGPoint(x: 210, y: 200))
        await drainMainActor()
        XCTAssertTrue(poster.phases.isEmpty)
        XCTAssertEqual(mouse.replayedClicks, 0)
    }

    func testDragScrollSameTierDrawingConflictRequiresMovementAndShortPressReplays() async throws {
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, platform) = makeButtonMappingRuntime(dragScrollPoster: poster)
        let drag = dragScrollProfile()
        let drawing = rightUpProfile(name: "Draw")
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [drag, drawing]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.release(.right, at: CGPoint(x: 200, y: 200))
        await drainMainActor()
        XCTAssertEqual(mouse.replayedClicks, 1)
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.release(.right, at: CGPoint(x: 205, y: 200))
        await drainMainActor()
        XCTAssertEqual(runtime.state.lastOutcome, .conflict([drag.id, drawing.id]))
        XCTAssertTrue(poster.phases.isEmpty)
        XCTAssertEqual(platform.shortcutCount, 0)
        XCTAssertEqual(mouse.replayedClicks, 1)
    }

    func testDragScrollCancellationPathsEndOnceAndNeverBeginFromCancelledRelease() async throws {
        for reason in ["sleep", "pause", "interrupt", "suppress"] {
            var point = CGPoint.zero
            let poster = DragScrollRuntimePoster()
            let (runtime, mouse, _) = makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
            let profile = dragScrollProfile()
            try runtime.apply(configuration(revision: 1, enabled: true, profiles: [profile]))
            let origin = CGPoint(x: 200, y: 200)
            point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
            XCTAssertTrue(mouse.press(.right, at: origin))
            await drainMainActor()
            point.x += 5
            await waitForCombination { poster.phases == [1] }
            switch reason {
            case "sleep": runtime.handleSleep()
            case "pause": try runtime.apply(configuration(revision: 2, enabled: false, profiles: [profile]))
            case "interrupt": mouse.interrupt(.right, at: CGPoint(x: 250, y: 200))
            default:
                let suppression = runtime.suppress(reason: .gestureEditor)
                suppression.release()
            }
            await drainMainActor()
            XCTAssertEqual(poster.phases, [1, 8], reason)
            if reason == "pause" {
                XCTAssertNotNil(runtime.state.activeSession)
                try runtime.apply(configuration(revision: 3, enabled: true, profiles: [profile]))
            }
            mouse.release(.right, at: CGPoint(x: 250, y: 200))
            await drainMainActor()
            XCTAssertEqual(poster.phases, [1, 8], reason)
        }
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, _) = makeButtonMappingRuntime(dragScrollPoster: poster)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [dragScrollProfile()]))
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 200, y: 200)))
        mouse.interrupt(.right, at: CGPoint(x: 250, y: 200))
        await drainMainActor()
        XCTAssertTrue(poster.phases.isEmpty, "Cancellation must not synthesize a movement first")
    }

    func testPendingDragScrollPauseAndReenableCannotReviveHeldPress() async throws {
        var point = CGPoint.zero
        let poster = DragScrollRuntimePoster()
        let (runtime, mouse, _) = makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
        let profile = dragScrollProfile()
        let origin = CGPoint(x: 200, y: 200)
        point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
        try runtime.apply(configuration(revision: 1, enabled: true, profiles: [profile]))
        XCTAssertTrue(mouse.press(.right, at: origin))
        await drainMainActor()
        try runtime.apply(configuration(revision: 2, enabled: false, profiles: [profile]))
        XCTAssertNotNil(runtime.state.activeSession, "Retain ownership until paired up")
        try runtime.apply(configuration(revision: 3, enabled: true, profiles: [profile]))
        point.x += 50
        mouse.release(.right, at: CGPoint(x: 250, y: 200))
        await drainMainActor()
        XCTAssertTrue(poster.phases.isEmpty)
        XCTAssertEqual(mouse.replayedClicks, 0)
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertTrue(mouse.press(.right, at: origin))
        mouse.release(.right, at: CGPoint(x: 214, y: 200))
        await drainMainActor()
        XCTAssertEqual(poster.phases, [1, 4], "A new physical press can scroll after reenable")
    }

    func testRuntimeDeinitializationCancelsActiveDragScrollPhase() async throws {
        var point = CGPoint.zero
        let poster = DragScrollRuntimePoster()
        var fixture: (GestureRuntime, RuntimeMouseEventSource, RuntimeActionPlatform)? =
            makeButtonMappingRuntime(pointerLocation: { point }, dragScrollPoster: poster)
        weak var releasedRuntime = fixture?.0
        let mouse = try XCTUnwrap(fixture?.1)
        let origin = CGPoint(x: 200, y: 200)
        point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
        try fixture?.0.apply(configuration(revision: 1, enabled: true, profiles: [dragScrollProfile()]))
        XCTAssertTrue(mouse.press(.right, at: origin))
        await drainMainActor()
        point.x += 5
        await waitForCombination { poster.phases == [1] }
        fixture = nil
        XCTAssertNil(releasedRuntime)
        XCTAssertEqual(poster.phases, [1, 8])
        XCTAssertFalse(mouse.isActive)
    }

    func testDragScrollCreationFailureStopsAndTerminatesOnlyAnExistingPhase() async throws {
        for failedPhase: Int64 in [1, 2] {
            var point = CGPoint.zero
            let poster = DragScrollRuntimePoster()
            let (runtime, mouse, platform) = makeButtonMappingRuntime(pointerLocation: { point },
                dragScrollPoster: poster, dragScrollEventFactory: { frame in
                    guard frame.phase != failedPhase else { return nil }
                    return CGScrollEventPoster.makeEvent(deltaY: frame.y, deltaX: frame.x, flags: [], phase: frame.phase)
                })
            try runtime.apply(configuration(revision: 1, enabled: true, profiles: [dragScrollProfile(), combinationProfile(action: .wheelUp), combinationProfile(action: .leftClick)]))
            let origin = CGPoint(x: 200, y: 200)
            point = GestureRuntime.appKitLocation(fromQuartz: origin, zeroScreenMaxY: try XCTUnwrap(NSScreen.screens.first).frame.maxY)
            XCTAssertTrue(mouse.press(.right, at: origin))
            await drainMainActor()
            point.x += 5
            if failedPhase == 2 {
                await waitForCombination { poster.phases == [1] }
                point.x += 10
            }
            await waitForCombination { runtime.lastError != nil }
            XCTAssertEqual(poster.phases, failedPhase == 1 ? [] : [1, 8])
            // Simulate already-swallowed tap callbacks reaching main after posting failed.
            mouse.deliverSwallowedChordClick(.right)
            mouse.deliverSwallowedScroll(.up, at: origin)
            await drainMainActor()
            XCTAssertEqual(mouse.replayedScrolls, 1)
            XCTAssertEqual(platform.shortcutCount, 0)
            mouse.release(.right, at: CGPoint(x: 250, y: 200))
            await drainMainActor()
            XCTAssertEqual(poster.phases, failedPhase == 1 ? [] : [1, 8])
            guard case .actionFailed = runtime.state.lastOutcome else { return XCTFail("Expected observable creation failure") }
            XCTAssertEqual(mouse.replayedClicks, 0)
        }
    }

    private func dragScrollProfile() -> GestureProfile {
        GestureProfile(name: "Drag", input: .mouseCombination(.init(action: .dragScroll)),
            action: .none, targetPolicy: .windowUnderPointer)
    }

    // MARK: - App rules

    func testSuppressedApplicationReceivesTriggerButtonUntouched() async throws {
        let mouse = RuntimeMouseEventSource()
        let capturer = MutableRuntimeTargetCapturer(
            processIdentifier: 101,
            bundleIdentifier: "com.blender.Blender"
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        var matchedIDs: [UUID] = []
        runtime.onMatch = { matchedIDs.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [rightUpProfile(name: "Global Up")],
            appRules: GestureAppRules(
                policies: [AppGesturePolicy(bundleIdentifier: "com.blender.blender")],
                groups: []
            )
        ))

        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        XCTAssertEqual(mouse.replayedClicks, 0)
        XCTAssertTrue(matchedIDs.isEmpty)
        XCTAssertNil(runtime.state.activeSession)
        XCTAssertNil(runtime.state.lastOutcome)
        XCTAssertEqual(capturer.captureCount, 1)

        // The gate stayed free: another application still gets the gesture.
        capturer.bundleIdentifier = "com.apple.Safari"
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()
        XCTAssertEqual(matchedIDs.count, 1)
        // The down-edge decision's target is reused, not captured again.
        XCTAssertEqual(capturer.captureCount, 2)
    }

    func testDeclinedMouseCaptureSkipsWindowTarget() async throws {
        let mouse = RuntimeMouseEventSource()
        let capturer = IdentifyingRuntimeTargetCapturer(
            processIdentifier: 101,
            bundleIdentifier: "com.blender.Blender"
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [rightUpProfile(name: "Global Up")],
            appRules: GestureAppRules(
                policies: [AppGesturePolicy(bundleIdentifier: "com.blender.Blender")],
                groups: []
            )
        ))

        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        await drainMainActor()
        XCTAssertEqual(capturer.identityCount, 1)
        XCTAssertEqual(capturer.windowCaptureCount, 0)

        capturer.bundleIdentifier = "com.apple.Safari"
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()
        XCTAssertEqual(capturer.identityCount, 2)
        XCTAssertEqual(capturer.windowCaptureCount, 1)
    }

    func testApplicationOnlyTriggerGesturesPassThroughElsewhere() async throws {
        let mouse = RuntimeMouseEventSource()
        let capturer = MutableRuntimeTargetCapturer(
            processIdentifier: 101,
            bundleIdentifier: "com.google.Chrome"
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        var safariOnly = rightUpProfile(name: "Safari Up")
        safariOnly.scope = .apps(["com.apple.Safari"])
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [safariOnly]
        ))

        XCTAssertFalse(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        XCTAssertEqual(mouse.replayedClicks, 0)

        capturer.bundleIdentifier = "com.apple.Safari"
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
        // A short press in a captured app is still replayed as a click.
        XCTAssertEqual(mouse.replayedClicks, 1)
    }

    func testSuppressionOnlyAffectsSelectedInputKinds() async throws {
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [rightUpProfile(name: "Global Up")],
            appRules: GestureAppRules(
                policies: [AppGesturePolicy(
                    bundleIdentifier: "com.example.target",
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.touchGesture])
                )],
                groups: []
            )
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))
        await drainMainActor()
    }

    func testGroupGestureWinsOverGlobalInsideMatchingDirectory() async throws {
        let mouse = RuntimeMouseEventSource()
        let capturer = MutableRuntimeTargetCapturer(
            processIdentifier: 101,
            bundleIdentifier: "com.studio.game",
            bundlePath: "/Users/test/Steam/steamapps/common/Game/Game.app"
        )
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: capturer,
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        let group = AppGroup(
            name: "Steam",
            matchers: [.directory("/Users/test/Steam/steamapps/common")]
        )
        let global = rightUpProfile(name: "Global Up")
        var grouped = rightUpProfile(name: "Group Up")
        grouped.scope = .group(group.id)
        var matchedIDs: [UUID] = []
        runtime.onMatch = { matchedIDs.append($0.profile.id) }
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [global, grouped],
            appRules: GestureAppRules(policies: [], groups: [group])
        ))

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 100))
        await drainMainActor()

        XCTAssertEqual(matchedIDs, [grouped.id])
    }

    func testDiagnosticsStillCaptureInSuppressedApplication() throws {
        let mouse = RuntimeMouseEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [rightUpProfile(name: "Global Up")],
            appRules: GestureAppRules(
                policies: [AppGesturePolicy(bundleIdentifier: "com.example.target")],
                groups: []
            )
        ))
        let diagnostic = runtime.beginDiagnostics()
        defer { diagnostic.end() }

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))
    }

    func testSuppressedModifierDrawingSkipsSessionAndFreesGate() async throws {
        let mouse = RuntimeMouseEventSource()
        let modifier = RuntimeModifierEventSource()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            modifierEventTap: modifier,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { RuntimeMultitouchSource() }
        )
        let modifierProfile = GestureProfile(
            name: "Fn",
            input: .drawn(DrawnGesture(
                activation: .modifier(.function),
                points: PathTemplates.up
            ))
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [modifierProfile, rightUpProfile(name: "Mouse")],
            appRules: GestureAppRules(
                policies: [AppGesturePolicy(
                    bundleIdentifier: "com.example.target",
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.trackpadDrawing])
                )],
                groups: []
            )
        ))

        modifier.press(.function)
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)

        // While Fn is still held, the mouse can own a session.
        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))
        modifier.release(.function)
        await drainMainActor()
    }

    func testSuppressedTouchGestureDoesNotRunAndFreesGate() async throws {
        let source = RuntimeMultitouchSource()
        let mouse = RuntimeMouseEventSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(processIdentifier: 101),
            mouseEventTap: mouse,
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { source }
        )
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [shortcutProfile(name: "Swipe"), rightUpProfile(name: "Mouse")],
            appRules: GestureAppRules(
                policies: [],
                groups: [AppGroup(
                    name: "Target",
                    matchers: [.bundleIdentifier("com.example.target")],
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.touchGesture])
                )]
            )
        ))

        source.emit(frame(at: 0, points: basePoints()))
        source.emit(frame(at: 0.07, points: basePoints()))
        await drainMainActor()
        XCTAssertNil(runtime.state.activeSession)

        XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        mouse.release(.right, at: CGPoint(x: 20, y: 300))

        source.emit(frame(
            at: 0.14,
            points: basePoints().mapValues {
                CGPoint(x: $0.x + 0.16, y: $0.y)
            }
        ))
        source.emit(frame(at: 0.20, points: [:]))
        await drainMainActor()

        XCTAssertEqual(platform.shortcutCount, 0)
    }

    func testGroupTouchGestureRunsInMatchingApplication() async throws {
        let source = RuntimeMultitouchSource()
        let platform = RuntimeActionPlatform()
        let runtime = GestureRuntime(
            permissionManager: RuntimePermissionProvider(trusted: true),
            actionExecutor: ActionExecutor(targetPlatform: platform),
            targetCapturer: MutableRuntimeTargetCapturer(
                processIdentifier: 101,
                bundleIdentifier: "unity.DefaultCompany.Game"
            ),
            trackpadClickEventTap: RuntimeTrackpadClickSource(),
            multitouchSourceFactory: { source }
        )
        let group = AppGroup(name: "Unity", matchers: [.bundleIdentifierPattern("unity.*")])
        var grouped = shortcutProfile(name: "Swipe")
        grouped.scope = .group(group.id)
        try runtime.apply(configuration(
            revision: 1,
            enabled: true,
            profiles: [grouped],
            appRules: GestureAppRules(policies: [], groups: [group])
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

        XCTAssertEqual(platform.shortcutProcessIdentifiers, [101])
    }

    private func rightUpProfile(name: String) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.up
            )),
            action: .none
        )
    }

    private func configuration(
        revision: UInt64,
        enabled: Bool,
        profiles: [GestureProfile],
        appRules: GestureAppRules = .empty,
        ambiguityResolution: GestureAmbiguityResolution = .reject
    ) -> GestureRuntimeConfiguration {
        GestureRuntimeConfiguration(
            revision: revision,
            isEnabled: enabled,
            profiles: profiles,
            minimumStrokeDistance: 40,
            pathMatchThreshold: 0.7,
            showsHUD: false,
            showsLiveMismatchFeedback: false,
            directTrackpadEnabled: true,
            appRules: appRules,
            ambiguityResolution: ambiguityResolution
        )
    }

    private func drawnShortcutProfile(
        id: UUID,
        name: String,
        activation: DrawActivation
    ) -> GestureProfile {
        GestureProfile(
            id: id,
            name: name,
            input: .drawn(DrawnGesture(
                activation: activation,
                points: PathTemplates.up
            )),
            action: .shortcut(
                keyCode: 0,
                modifiers: 0,
                display: "A",
                orderedChord: nil
            )
        )
    }

    private func beginDraw(
        _ activation: DrawActivation,
        mouse: RuntimeMouseEventSource,
        modifier: RuntimeModifierEventSource
    ) {
        switch activation {
        case .mouse:
            XCTAssertTrue(mouse.press(.right, at: CGPoint(x: 20, y: 300)))
        case .modifier(let key):
            modifier.press(key, at: CGPoint(x: 20, y: 300))
        }
    }

    private func endDraw(
        _ activation: DrawActivation,
        mouse: RuntimeMouseEventSource,
        modifier: RuntimeModifierEventSource
    ) {
        switch activation {
        case .mouse:
            mouse.release(.right, at: CGPoint(x: 20, y: 100))
        case .modifier(let key):
            modifier.release(key, at: CGPoint(x: 20, y: 100))
        }
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

private final class RuntimeTrackpadClickSource: TrackpadClickEventSource {
    var interceptsPresses = false
    var onPress: ((Bool) -> TrackpadClickEventTap.PressDecision)?
    private(set) var isActive = false
    private(set) var installedIntercepts = false

    func start() -> Bool {
        isActive = true
        installedIntercepts = interceptsPresses
        return true
    }

    func stop() {
        isActive = false
    }

    /// Returns whether the physical left down was swallowed.
    @discardableResult
    func press() -> Bool {
        guard isActive else { return false }
        return onPress?(installedIntercepts) == .swallow && installedIntercepts
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
    var interceptsChordClicks = false
    var interceptsScroll = false
    var shouldCaptureScroll: ((MouseWheelDirection, CGPoint) -> Bool)?
    var onEvent: ((MouseEventTap.EventKind, UInt64) -> Void)?
    var shouldCapture:
        ((MouseTriggerButton, CGPoint, CGEventFlags)
            -> MouseEventTap.CaptureDecision)?
    private(set) var isActive = false
    private(set) var stopCount = 0
    private(set) var replayedClicks = 0
    private(set) var replayedScrolls = 0
    private(set) var lastCaptureDecision: MouseEventTap.CaptureDecision?
    private(set) var installedChordClicks = false
    private var capturedButtons = Set<MouseTriggerButton>()
    private var chordClickButtons = Set<MouseTriggerButton>()
    private var interruptedButtons = Set<MouseTriggerButton>()
    private var eventGeneration: UInt64 = 0

    func start() -> Bool {
        // Mirrors `MouseEventTap`: a mask change reinstalls the tap.
        if isActive, installedChordClicks != interceptsChordClicks {
            stop()
        }
        eventGeneration &+= 1
        isActive = true
        installedChordClicks = interceptsChordClicks
        return true
    }

    func stop() {
        if isActive {
            stopCount += 1
        }
        eventGeneration &+= 1
        isActive = false
        capturedButtons.removeAll()
        chordClickButtons.removeAll()
        interruptedButtons.removeAll()
    }

    func isCurrentEventGeneration(_ generation: UInt64) -> Bool {
        isActive && eventGeneration == generation
    }

    func replayScroll(_ event: CGEvent) { replayedScrolls += 1 }

    @discardableResult
    func scroll(_ direction: MouseWheelDirection, at location: CGPoint,
                preciseTimestamp: TimeInterval? = nil) -> Bool {
        guard isActive, interceptsScroll,
              shouldCaptureScroll?(direction, location) == true,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 1, wheel1: direction == .up ? 1 : -1,
                                  wheel2: 0, wheel3: 0) else { return false }
        if let preciseTimestamp {
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.timestamp = CGEventTimestamp(preciseTimestamp * 1_000_000_000)
        }
        onEvent?(.scroll(direction, location, event), eventGeneration)
        return true
    }

    /// Delivers a tick the tap already swallowed, as when its capture decision
    /// raced with a release or a tap reinstall.
    func deliverSwallowedScroll(
        _ direction: MouseWheelDirection,
        at location: CGPoint,
        generation: UInt64? = nil
    ) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 1, wheel1: direction == .up ? 1 : -1,
                                  wheel2: 0, wheel3: 0) else { return }
        onEvent?(.scroll(direction, location, event), generation ?? eventGeneration)
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
        at location: CGPoint,
        flags: CGEventFlags = []
    ) -> Bool {
        guard isActive,
              watchedButtons.contains(button),
              !interruptedButtons.contains(button)
        else {
            return false
        }
        let decision = shouldCapture?(button, location, flags)
            ?? .capture(acceptsChordClick: false)
        lastCaptureDecision = decision
        guard case .capture(let acceptsChordClick) = decision else {
            return false
        }
        capturedButtons.insert(button)
        if acceptsChordClick {
            chordClickButtons.insert(button)
        }
        onEvent?(.buttonDown(button, location), eventGeneration)
        return true
    }

    func deliverSwallowedChordClick(_ button: MouseTriggerButton) {
        onEvent?(.chordClick(button), eventGeneration)
    }

    /// Returns whether the left click was swallowed as a chord.
    @discardableResult
    func clickLeft() -> Bool {
        guard installedChordClicks,
              let owner = chordClickButtons.first
        else {
            return false
        }
        onEvent?(.chordClick(owner), eventGeneration)
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
        chordClickButtons.remove(button)
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
    private var storedBundleIdentifier: String
    private var storedBundlePath: String?
    private(set) var captureCount = 0

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

    var bundleIdentifier: String {
        get { lock.withLock { storedBundleIdentifier } }
        set { lock.withLock { storedBundleIdentifier = newValue } }
    }

    var bundlePath: String? {
        get { lock.withLock { storedBundlePath } }
        set { lock.withLock { storedBundlePath = newValue } }
    }

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String = "com.example.target",
        bundlePath: String? = nil
    ) {
        storedProcessIdentifier = processIdentifier
        storedBundleIdentifier = bundleIdentifier
        storedBundlePath = bundlePath
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        let (capturedProcessIdentifier, capturedBundleIdentifier, capturedPath) =
            lock.withLock {
                captureCount += 1
                return (storedProcessIdentifier, storedBundleIdentifier, storedBundlePath)
            }
        let target = GestureTargetResolution.resolved(
            GestureTargetContext(
                policy: .frontmostWindow,
                identity: GestureTargetIdentity(
                    processIdentifier: capturedProcessIdentifier,
                    bundleIdentifier: capturedBundleIdentifier,
                    bundlePath: capturedPath
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

/// Separates the cheap identity read from the window capture so tests can
/// prove a declined session never asks for the AX window.
private final class IdentifyingRuntimeTargetCapturer: GestureTargetIdentifying,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedProcessIdentifier: pid_t
    private var storedBundleIdentifier: String
    private(set) var identityCount = 0
    private(set) var windowCaptureCount = 0

    var bundleIdentifier: String {
        get { lock.withLock { storedBundleIdentifier } }
        set { lock.withLock { storedBundleIdentifier = newValue } }
    }

    init(processIdentifier: pid_t, bundleIdentifier: String) {
        storedProcessIdentifier = processIdentifier
        storedBundleIdentifier = bundleIdentifier
    }

    func captureIdentity(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        lock.withLock { identityCount += 1 }
        return snapshot()
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        lock.withLock { windowCaptureCount += 1 }
        return snapshot()
    }

    private func snapshot() -> GestureTargetSnapshot {
        let (processIdentifier, bundleIdentifier) = lock.withLock {
            (storedProcessIdentifier, storedBundleIdentifier)
        }
        let target = GestureTargetResolution.resolved(
            GestureTargetContext(
                policy: .frontmostWindow,
                identity: GestureTargetIdentity(
                    processIdentifier: processIdentifier,
                    bundleIdentifier: bundleIdentifier
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
    private(set) var shortcutKeyCodes: [UInt16] = []

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext
    ) async throws {
        shortcutCount += 1
        shortcutProcessIdentifiers.append(target.processIdentifier)
        shortcutKeyCodes.append(keyCode)
    }

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {}
}

private final class DragScrollRuntimePoster: ScrollEventPosting {
    private let lock = NSLock()
    private var events: [CGEvent] = []
    var phases: [Int64] { lock.withLock { events.map { $0.getIntegerValueField(.scrollWheelEventScrollPhase) } } }
    var deltas: [CGPoint] { lock.withLock { events.map {
        CGPoint(x: CGFloat($0.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                y: CGFloat($0.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
    } } }
    func post(_ event: CGEvent) { lock.withLock { events.append(event) } }
}
