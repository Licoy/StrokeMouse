import AppKit
import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class WindowActionsTests: XCTestCase {
    func testShortcutPreparesActivatesAndVerifiesBeforePosting() async throws {
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
            .postShortcut(keyCode: 42, modifiers: 7),
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

    private func makeTargetContext() -> GestureTargetContext {
        GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 101,
                bundleIdentifier: "com.apple.Safari"
            ),
            application: nil,
            window: GestureWindowTarget(element: AXUIElementCreateApplication(101))
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
    case postShortcut(keyCode: UInt16, modifiers: UInt)
}

@MainActor
private final class RecordingGestureTargetSystemClient: GestureTargetSystemClient {
    var activationAccepted = true
    var activeStates = [true]
    var windowControlAvailable = true
    var validateError: Error?
    var hideError: Error?
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
        guard activeStates.count > 1 else { return activeStates[0] }
        return activeStates.removeFirst()
    }

    func verifyFocusedWindow(_ target: GestureTargetContext) throws {
        record(.verifyFocusedWindow, target: target)
    }

    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) throws {
        record(.postShortcut(keyCode: keyCode, modifiers: modifiers), target: target)
    }

    private func record(
        _ operation: TargetSystemOperation,
        target: GestureTargetContext
    ) {
        operations.append(operation)
        targets.append(target)
    }
}
