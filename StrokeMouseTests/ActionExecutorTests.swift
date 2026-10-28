import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class ActionExecutorTests: XCTestCase {
    func testShortcutReceivesResolvedApplicationOnlyTarget() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)
        let context = makeTargetContext(withWindow: false)

        try await executor.execute(
            .shortcut(keyCode: 126, modifiers: 0, display: "Mission Control"),
            target: .resolved(context)
        )

        XCTAssertEqual(platform.shortcuts.count, 1)
        XCTAssertNil(platform.shortcuts[0].target.window)
        XCTAssertEqual(platform.shortcuts[0].target.identity, context.identity)
    }

    func testTargetedActionsReceiveTheExactFrozenWindowContext() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)
        let context = makeTargetContext()
        let target = GestureTargetResolution.resolved(context)
        let chord = ShortcutChord(modifiers: [.command, .option], keyCode: 42)

        try await executor.execute(
            .shortcut(
                keyCode: 42,
                modifiers: 7,
                display: "Shortcut",
                orderedChord: chord
            ),
            target: target
        )
        try await executor.execute(.window(.close), target: target)

        XCTAssertEqual(platform.shortcuts.count, 1)
        XCTAssertEqual(platform.shortcuts[0].keyCode, 42)
        XCTAssertEqual(platform.shortcuts[0].modifiers, 7)
        XCTAssertEqual(platform.shortcuts[0].orderedChord, chord)
        XCTAssertTrue(platform.shortcuts[0].target.window === context.window)
        XCTAssertEqual(platform.windows.count, 1)
        XCTAssertEqual(platform.windows[0].command, .close)
        XCTAssertTrue(platform.windows[0].target.window === context.window)
    }

    func testShortcutSequencePostsEveryChordInOrderToTheSameTarget() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform)
        let context = makeTargetContext()
        let paste = ShortcutChord(modifiers: [.command], keyCode: 9)
        let send = ShortcutChord(modifiers: [], keyCode: 36)

        try await executor.execute(
            .shortcutSequence([paste, send]),
            target: .resolved(context)
        )

        XCTAssertEqual(platform.shortcuts.map(\.orderedChord), [paste, send])
        XCTAssertEqual(platform.shortcuts.map(\.keyCode), [paste.legacyKeyCode, send.legacyKeyCode])
        XCTAssertEqual(platform.shortcuts.map(\.modifiers), [paste.legacyModifiers, send.legacyModifiers])
        XCTAssertTrue(platform.shortcuts.allSatisfy { $0.target.window === context.window })
    }

    func testShortcutSequenceStopsAtFirstFailure() async {
        let platform = RecordingGestureTargetActionPlatform()
        platform.error = GestureTargetError.windowUnavailable
        let executor = ActionExecutor(targetPlatform: platform)

        do {
            try await executor.execute(
                .shortcutSequence([
                    ShortcutChord(modifiers: [.command], keyCode: 9),
                    ShortcutChord(modifiers: [], keyCode: 36),
                ]),
                target: .resolved(makeTargetContext())
            )
            XCTFail("Expected the first chord failure to stop the sequence")
        } catch GestureTargetError.windowUnavailable {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(platform.shortcuts.count, 1)
        XCTAssertNotNil(executor.lastError)
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

    func testApplicationSwitchIgnoresUnavailableTargetAndTargetPlatform() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        let applicationSwitcher = RecordingApplicationSwitcher()
        let executor = ActionExecutor(
            targetPlatform: platform,
            applicationSwitcher: applicationSwitcher
        )

        try await executor.execute(
            .applicationSwitch(.commandTab),
            target: .unavailable(.windowUnavailable)
        )

        XCTAssertEqual(applicationSwitcher.commands, [.commandTab])
        XCTAssertTrue(platform.shortcuts.isEmpty)
        XCTAssertTrue(platform.windows.isEmpty)
        XCTAssertNil(executor.lastError)
    }

    func testApplicationSwitchFailureIsRecordedAndRethrown() async {
        let platform = RecordingGestureTargetActionPlatform()
        let applicationSwitcher = RecordingApplicationSwitcher()
        applicationSwitcher.error = ShortcutActionError.eventSourceUnavailable
        let executor = ActionExecutor(
            targetPlatform: platform,
            applicationSwitcher: applicationSwitcher
        )

        do {
            try await executor.executeForTesting(
                .applicationSwitch(.shiftCommandTab)
            )
            XCTFail("Expected application switch failure")
        } catch ShortcutActionError.eventSourceUnavailable {
            // Expected typed failure.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(applicationSwitcher.commands, [.shiftCommandTab])
        XCTAssertTrue(platform.shortcuts.isEmpty)
        XCTAssertTrue(platform.windows.isEmpty)
        XCTAssertNotNil(executor.lastError)
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

    func testGlobalSystemCommandsIgnoreUnavailableAndCapturedTargets() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        var chords: [ShortcutChord] = []
        let executor = ActionExecutor(targetPlatform: platform, globalChordPoster: { chords.append($0) })
        for command in [SystemCommand.missionControl, .spaceLeft, .spaceRight] {
            try await executor.execute(.system(SystemAction(command: command)),
                                       target: .unavailable(.windowUnavailable))
            try await executor.execute(.system(SystemAction(command: command)),
                                       target: .resolved(makeTargetContext()))
        }
        XCTAssertEqual(chords, [SystemCommand.missionControl, .spaceLeft, .spaceRight]
            .flatMap { [$0.defaultChord, $0.defaultChord] })
        XCTAssertTrue(platform.shortcuts.isEmpty)
        XCTAssertTrue(platform.windows.isEmpty)
    }

    func testApplicationWindowsUsesExactFrozenTargetAndOverride() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        var postedGlobally = false
        let executor = ActionExecutor(targetPlatform: platform, globalChordPoster: { _ in postedGlobally = true })
        let target = makeTargetContext()
        let chord = ShortcutChord(modifiers: [.function], keyCode: nil)
        let action = GestureAction.system(SystemAction(command: .applicationWindows, shortcutOverride: chord))
        try await executor.execute(action, target: .resolved(target))
        XCTAssertEqual(platform.shortcuts.map(\.orderedChord), [chord])
        XCTAssertTrue(platform.shortcuts[0].target.window === target.window)
        XCTAssertFalse(postedGlobally)
        do {
            try await executor.executeForTesting(action)
            XCTFail("Application Windows needs a captured target")
        } catch ActionExecutionError.targetRequiredForTest {
        }
        XCTAssertEqual(platform.shortcuts.count, 1)
    }

    func testGlobalSystemOverrideIsTestableAndFailuresPropagate() async throws {
        let chord = ShortcutChord(modifiers: [.function, .control], keyCode: 123)
        var received: ShortcutChord?
        let executor = ActionExecutor(globalChordPoster: { received = $0 })
        try await executor.executeForTesting(.system(SystemAction(command: .spaceLeft, shortcutOverride: chord)))
        XCTAssertEqual(received, chord)
        let failing = ActionExecutor(globalChordPoster: { _ in throw ShortcutActionError.eventSourceUnavailable })
        do {
            try await failing.executeForTesting(.system(SystemAction(command: .missionControl)))
            XCTFail("Expected event posting failure")
        } catch ShortcutActionError.eventSourceUnavailable {
        }
        XCTAssertNotNil(failing.lastError)
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

@MainActor
private final class RecordingGestureTargetActionPlatform: GestureTargetActionPlatform {
    struct ShortcutCall {
        let keyCode: UInt16
        let modifiers: UInt
        let orderedChord: ShortcutChord?
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
        orderedChord: ShortcutChord?,
        target: GestureTargetContext
    ) async throws {
        shortcuts.append(ShortcutCall(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord,
            target: target
        ))
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

@MainActor
private final class RecordingApplicationSwitcher: ApplicationSwitching {
    var error: Error?
    private(set) var commands: [ApplicationSwitchCommand] = []

    func perform(_ command: ApplicationSwitchCommand) throws {
        commands.append(command)
        if let error { throw error }
    }
}
