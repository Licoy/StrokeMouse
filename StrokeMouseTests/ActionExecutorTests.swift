import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class ActionExecutorTests: XCTestCase {
    func testTargetedActionsReceiveTheExactFrozenWindowContext() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)
        let context = makeTargetContext()
        let target = GestureTargetResolution.resolved(context)

        try await executor.execute(
            .shortcut(keyCode: 42, modifiers: 7, display: "Shortcut"),
            target: target
        )
        try await executor.execute(.window(.close), target: target)

        XCTAssertEqual(platform.shortcuts.count, 1)
        XCTAssertEqual(platform.shortcuts[0].keyCode, 42)
        XCTAssertEqual(platform.shortcuts[0].modifiers, 7)
        XCTAssertTrue(platform.shortcuts[0].target.window === context.window)
        XCTAssertEqual(platform.windows.count, 1)
        XCTAssertEqual(platform.windows[0].command, .close)
        XCTAssertTrue(platform.windows[0].target.window === context.window)
    }

    func testUnavailableTargetFailsWithoutCallingPlatform() async {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)

        do {
            try await executor.execute(
                .window(.minimize),
                target: .unavailable(.windowUnavailable)
            )
            XCTFail("Expected unavailable target to throw")
        } catch GestureTargetError.windowUnavailable {
            // Expected typed failure.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(platform.windows.isEmpty)
        XCTAssertNotNil(executor.lastError)
    }

    func testTargetIndependentActionIgnoresUnavailableTarget() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)

        try await executor.execute(
            .none,
            target: .unavailable(.noElementAtPointer)
        )

        XCTAssertNil(executor.lastError)
        XCTAssertTrue(platform.shortcuts.isEmpty)
        XCTAssertTrue(platform.windows.isEmpty)
    }

    func testPlatformFailureIsRecordedAndRethrownWithoutFallback() async {
        let platform = RecordingGestureTargetActionPlatform()
        platform.error = GestureTargetError.activationFailed(101)
        let executor = ActionExecutor(targetPlatform: platform)

        do {
            try await executor.execute(
                .shortcut(keyCode: 1, modifiers: 0, display: "A"),
                target: .resolved(makeTargetContext())
            )
            XCTFail("Expected platform failure")
        } catch GestureTargetError.activationFailed(let pid) {
            XCTAssertEqual(pid, 101)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNotNil(executor.lastError)
        XCTAssertEqual(platform.shortcuts.count, 1)
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

@MainActor
private final class RecordingGestureTargetActionPlatform: GestureTargetActionPlatform {
    struct ShortcutCall {
        let keyCode: UInt16
        let modifiers: UInt
        let target: GestureTargetContext
    }

    struct WindowCall {
        let command: WindowCommand
        let target: GestureTargetContext
    }

    var error: Error?
    private(set) var shortcuts: [ShortcutCall] = []
    private(set) var windows: [WindowCall] = []

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) async throws {
        shortcuts.append(ShortcutCall(keyCode: keyCode, modifiers: modifiers, target: target))
        if let error { throw error }
    }

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {
        windows.append(WindowCall(command: command, target: target))
        if let error { throw error }
    }
}
