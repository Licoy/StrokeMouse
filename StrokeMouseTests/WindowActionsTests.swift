import AppKit
import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class WindowActionsTests: XCTestCase {
    func testDefaultMissionControlRunsFromFinderDesktopTarget() async throws {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [true]
        let executor = ActionExecutor(
            targetPlatform: WindowActions(system: system)
        )
        let profile = try XCTUnwrap(DefaultGestures.make().first)
        let context = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 101,
                bundleIdentifier: "com.apple.finder"
            ),
            application: nil,
            window: nil
        )
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .resolved(context),
            windowUnderPointer: .unavailable(
                .targetNotCaptured(.windowUnderPointer)
            )
        )

        let selected = try XCTUnwrap(
            GestureCandidateSelector.prepare(
                profiles: [profile],
                snapshot: snapshot
            ).first
        )
        try await executor.execute(
            selected.profile.action,
            target: selected.target
        )

        XCTAssertEqual(system.operations, [
            .isApplicationActive,
            .postShortcut(
                keyCode: 126,
                modifiers: UInt(NSEvent.ModifierFlags.control.rawValue)
            ),
        ])
    }

    func testApplicationOnlyShortcutPostsWhenFrozenApplicationIsAlreadyActive() async throws {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [true]
        let actions = WindowActions(system: system)

        try await actions.performShortcut(
            keyCode: 126,
            modifiers: UInt(NSEvent.ModifierFlags.control.rawValue),
            target: makeTargetContext(withWindow: false)
        )

        XCTAssertEqual(system.operations, [
            .isApplicationActive,
            .postShortcut(
                keyCode: 126,
                modifiers: UInt(NSEvent.ModifierFlags.control.rawValue)
            ),
        ])
    }

    func testApplicationOnlyShortcutActivatesFrozenApplicationBeforePosting() async throws {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false, true]
        let actions = WindowActions(
            system: system,
            activationTimeout: .seconds(1),
            pollInterval: .milliseconds(1)
        )

        try await actions.performShortcut(
            keyCode: 42,
            modifiers: 7,
            target: makeTargetContext(withWindow: false)
        )

        XCTAssertEqual(system.operations, [
            .isApplicationActive,
            .activateApplication,
            .isApplicationActive,
            .postShortcut(keyCode: 42, modifiers: 7),
        ])
    }

    func testApplicationOnlyActivationRejectionNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false]
        system.activationAccepted = false
        let actions = WindowActions(system: system)

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext(withWindow: false)
            )
            XCTFail("Expected activation rejection")
        } catch GestureTargetError.activationFailed(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(system.operations, [
            .isApplicationActive,
            .activateApplication,
        ])
    }

    func testApplicationOnlyActivationTimeoutNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false]
        let actions = WindowActions(
            system: system,
            activationTimeout: .zero,
            pollInterval: .milliseconds(1)
        )

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext(withWindow: false)
            )
            XCTFail("Expected activation timeout")
        } catch GestureTargetError.activationTimedOut(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(system.operations, [
            .isApplicationActive,
            .activateApplication,
            .isApplicationActive,
        ])
    }

    func testTerminatedApplicationOnlyTargetNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activeError = GestureTargetError.applicationTerminated(101)
        let actions = WindowActions(system: system)

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext(withWindow: false)
            )
            XCTFail("Expected terminated application to fail")
        } catch GestureTargetError.applicationTerminated(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(system.operations, [.isApplicationActive])
    }

    func testHideAllowsApplicationOnlyTarget() async throws {
        let system = RecordingGestureTargetSystemClient()
        let actions = WindowActions(system: system)

        try await actions.performWindow(
            .hide,
            target: makeTargetContext(withWindow: false)
        )

        XCTAssertEqual(system.operations, [.hideApplication])
    }

    func testWindowCommandsRequireAnOperableFrozenWindow() async {
        for command in [
            WindowCommand.close,
            .minimize,
            .zoom,
            .fullscreen,
            .center,
        ] {
            let system = RecordingGestureTargetSystemClient()
            let actions = WindowActions(system: system)

            do {
                try await actions.performWindow(
                    command,
                    target: makeTargetContext(withWindow: false)
                )
                XCTFail("Expected \(command) to require an operable window")
            } catch GestureTargetError.targetHasNoOperableWindow {
                // Expected typed failure.
            } catch {
                XCTFail("Unexpected error for \(command): \(error)")
            }

            XCTAssertTrue(system.operations.isEmpty)
        }
    }

    func testShortcutPreparesActivatesAndVerifiesBeforePosting() async throws {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false, true]
        let actions = WindowActions(
            system: system,
            activationTimeout: .seconds(1),
            pollInterval: .milliseconds(1)
        )
        let chord = ShortcutChord(modifiers: [.command, .option], keyCode: 42)

        try await actions.performShortcut(
            keyCode: 42,
            modifiers: 7,
            orderedChord: chord,
            target: makeTargetContext()
        )

        XCTAssertEqual(system.operations, [
            .validateWindow,
            .setMainWindow,
            .raiseWindow,
            .activateApplication,
            .isApplicationActive,
            .isApplicationActive,
            .verifyFocusedWindow,
            .postShortcut(keyCode: 42, modifiers: 7, orderedChord: chord),
        ])
    }

    func testActivationRejectionNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activationAccepted = false
        let actions = WindowActions(system: system)

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext()
            )
            XCTFail("Expected activation rejection")
        } catch GestureTargetError.activationFailed(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(system.operations.contains { operation in
            if case .postShortcut = operation { return true }
            return false
        })
    }

    func testActivationTimeoutNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false]
        let actions = WindowActions(
            system: system,
            activationTimeout: .zero,
            pollInterval: .milliseconds(1)
        )

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext()
            )
            XCTFail("Expected activation timeout")
        } catch GestureTargetError.activationTimedOut(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(system.operations.contains { operation in
            if case .postShortcut = operation { return true }
            return false
        })
    }

    func testActivationAfterDeadlineNeverPostsShortcut() async {
        let system = RecordingGestureTargetSystemClient()
        system.activeStates = [false, true]
        let actions = WindowActions(
            system: system,
            activationTimeout: .milliseconds(10),
            pollInterval: .seconds(1)
        )

        do {
            try await actions.performShortcut(
                keyCode: 42,
                modifiers: 7,
                target: makeTargetContext()
            )
            XCTFail("Expected hard activation deadline")
        } catch GestureTargetError.activationTimedOut(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(
            system.operations.filter { $0 == .isApplicationActive }.count,
            1
        )
        XCTAssertFalse(system.operations.contains { operation in
            if case .postShortcut = operation { return true }
            return false
        })
    }

    func testFullscreenFallbackUsesSameTargetedShortcutPath() async throws {
        let system = RecordingGestureTargetSystemClient()
        system.windowControlAvailable = false
        system.activeStates = [true]
        let actions = WindowActions(system: system)
        let target = makeTargetContext()

        try await actions.performWindow(.fullscreen, target: target)

        XCTAssertEqual(system.operations, [
            .validateWindow,
            .pressWindowControl(.fullscreen),
            .validateWindow,
            .setMainWindow,
            .raiseWindow,
            .activateApplication,
            .isApplicationActive,
            .verifyFocusedWindow,
            .postShortcut(
                keyCode: 3,
                modifiers: UInt(
                    NSEvent.ModifierFlags.control.rawValue
                        | NSEvent.ModifierFlags.command.rawValue
                )
            ),
        ])
        XCTAssertTrue(system.targets.allSatisfy { $0.window === target.window })
    }

    func testWindowCommandsRouteOnlyToTheFrozenTarget() async throws {
        let system = RecordingGestureTargetSystemClient()
        let actions = WindowActions(system: system)
        let target = makeTargetContext()

        try await actions.performWindow(.close, target: target)
        try await actions.performWindow(.center, target: target)
        try await actions.performWindow(.hide, target: target)

        XCTAssertEqual(system.operations, [
            .validateWindow,
            .pressWindowControl(.close),
            .validateWindow,
            .centerWindow,
            .hideApplication,
        ])
        XCTAssertTrue(system.targets.allSatisfy { $0.window === target.window })
    }

    func testInvalidFrozenWindowFailsWithoutTryingAnotherTarget() async {
        let system = RecordingGestureTargetSystemClient()
        system.validateError = GestureTargetError.axOperationFailed(
            operation: .validateWindow,
            code: .cannotComplete
        )
        let actions = WindowActions(system: system)

        do {
            try await actions.performWindow(.close, target: makeTargetContext())
            XCTFail("Expected invalid frozen target to fail")
        } catch GestureTargetError.axOperationFailed(let operation, let code) {
            XCTAssertEqual(operation, .validateWindow)
            XCTAssertEqual(code, .cannotComplete)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(system.operations, [.validateWindow])
    }

    func testTerminatedFrozenApplicationFailsHideWithoutFallback() async {
        let system = RecordingGestureTargetSystemClient()
        system.hideError = GestureTargetError.applicationTerminated(101)
        let actions = WindowActions(system: system)

        do {
            try await actions.performWindow(.hide, target: makeTargetContext())
            XCTFail("Expected terminated target application to fail")
        } catch GestureTargetError.applicationTerminated(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(system.operations, [.hideApplication])
    }

    private func makeTargetContext(withWindow: Bool = true) -> GestureTargetContext {
        GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 101,
                bundleIdentifier: "com.apple.Safari"
            ),
            application: nil,
            window: withWindow
                ? GestureWindowTarget(element: AXUIElementCreateApplication(101))
                : nil
        )
    }
}

private enum TargetSystemOperation: Equatable {
    case validateWindow
    case pressWindowControl(WindowCommand)
    case hideApplication
    case centerWindow
    case setMainWindow
    case raiseWindow
    case activateApplication
    case isApplicationActive
    case verifyFocusedWindow
    case postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord? = nil
    )
}

@MainActor
private final class RecordingGestureTargetSystemClient: GestureTargetSystemClient {
    var activationAccepted = true
    var activeStates = [true]
    var windowControlAvailable = true
    var validateError: Error?
    var hideError: Error?
    var activeError: Error?
    private(set) var operations: [TargetSystemOperation] = []
    private(set) var targets: [GestureTargetContext] = []

    func validateWindow(_ target: GestureTargetContext) throws {
        record(.validateWindow, target: target)
        if let validateError { throw validateError }
    }

    func pressWindowControl(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) throws -> Bool {
        record(.pressWindowControl(command), target: target)
        return windowControlAvailable
    }

    func hideApplication(_ target: GestureTargetContext) throws {
        record(.hideApplication, target: target)
        if let hideError { throw hideError }
    }

    func centerWindow(_ target: GestureTargetContext) throws {
        record(.centerWindow, target: target)
    }

    func setMainWindow(_ target: GestureTargetContext) throws {
        record(.setMainWindow, target: target)
    }

    func raiseWindow(_ target: GestureTargetContext) throws {
        record(.raiseWindow, target: target)
    }

    func activateApplication(_ target: GestureTargetContext) -> Bool {
        record(.activateApplication, target: target)
        return activationAccepted
    }

    func isApplicationActive(_ target: GestureTargetContext) throws -> Bool {
        record(.isApplicationActive, target: target)
        if let activeError { throw activeError }
        guard activeStates.count > 1 else { return activeStates[0] }
        return activeStates.removeFirst()
    }

    func verifyFocusedWindow(_ target: GestureTargetContext) throws {
        record(.verifyFocusedWindow, target: target)
    }

    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext
    ) throws {
        record(.postShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord
        ), target: target)
    }

    private func record(
        _ operation: TargetSystemOperation,
        target: GestureTargetContext
    ) {
        operations.append(operation)
        targets.append(target)
    }
}
