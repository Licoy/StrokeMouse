import AppKit
import ApplicationServices
import Carbon.HIToolbox
import XCTest
@testable import StrokeMouse

@MainActor
final class ActionExecutorTests: XCTestCase {
    func testSelectionURLCopiesInFrozenWindowAndEncodesOnlySelection() async throws {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let platform = RecordingGestureTargetActionPlatform()
        platform.onPostShortcut = {
            pasteboard.clearContents()
            Task { @MainActor in
                pasteboard.setString("中文 a+b & #?", forType: .string)
                pasteboard.setData(Data([1]), forType: .rtf)
            }
        }
        var opened: [String] = []
        let executor = ActionExecutor(targetPlatform: platform, pasteboard: pasteboard) {
            opened.append($0.absoluteString)
            return true
        }
        let target = makeTargetContext()
        try await executor.execute(
            .openURLWithSelection(template: "https://www.baidu.com/s?other=a+b%2f&wd={0}#results"),
            target: .resolved(target)
        )

        XCTAssertEqual(platform.shortcuts.map(\.orderedChord), [
            ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_C))
        ])
        XCTAssertTrue(platform.shortcuts.first?.target.window === target.window)
        XCTAssertEqual(opened, ["https://www.baidu.com/s?other=a+b%2f&wd=%E4%B8%AD%E6%96%87%20a%2Bb%20%26%20%23%3F#results"])
        XCTAssertEqual(pasteboard.string(forType: .string), "中文 a+b & #?")
        XCTAssertEqual(pasteboard.data(forType: .rtf), Data([1]))
    }

    func testSelectionURLTimesOutWithOldTextAndRejectsOverlappingCopy() async throws {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        let platform = RecordingGestureTargetActionPlatform()
        let executor = ActionExecutor(targetPlatform: platform, pasteboard: pasteboard) { _ in
            XCTFail("No URL should open for old clipboard content")
            return false
        }
        let action = GestureAction.openURLWithSelection(template: "https://example.com/?q={0}")
        let target = GestureTargetResolution.resolved(makeTargetContext())
        let overlap = expectation(description: "Concurrent copy rejected")
        platform.onPostShortcut = { [weak executor] in
            Task { @MainActor in
                defer { overlap.fulfill() }
                guard let executor else { return XCTFail("Executor was released") }
                do {
                    try await executor.execute(action, target: target)
                    XCTFail("Expected overlapping action to fail")
                } catch ActionExecutionError.selectionCopyInProgress {
                } catch { XCTFail("Unexpected error: \(error)") }
            }
        }

        do {
            try await executor.execute(action, target: target)
            XCTFail("Expected unchanged clipboard to time out")
        } catch ActionExecutionError.selectionCopyTimedOut {}
        await fulfillment(of: [overlap], timeout: 1)
        XCTAssertEqual(platform.shortcuts.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "old")
    }

    func testSelectionURLRejectsNonTextAndUnavailableWindow() async throws {
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let platform = RecordingGestureTargetActionPlatform()
        platform.onPostShortcut = {
            pasteboard.clearContents()
            pasteboard.setData(Data([1]), forType: .png)
        }
        let executor = ActionExecutor(targetPlatform: platform, pasteboard: pasteboard) { _ in
            XCTFail("No URL should open")
            return false
        }
        let action = GestureAction.openURLWithSelection(template: "https://example.com/?q={0}")

        do {
            try await executor.execute(action, target: .resolved(makeTargetContext()))
            XCTFail("Expected non-text copy to fail")
        } catch ActionExecutionError.selectionCopyHasNoText {}

        do {
            try await executor.execute(action, target: .unavailable(.windowUnavailable))
            XCTFail("Expected unavailable target to fail")
        } catch GestureTargetError.windowUnavailable {}
        XCTAssertEqual(platform.shortcuts.count, 1)
    }

    func testFixedURLStillOpensWithoutTargetOrCopy() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        var opened: [String] = []
        let executor = ActionExecutor(targetPlatform: platform) {
            opened.append($0.absoluteString)
            return true
        }
        try await executor.executeForTesting(.openURL("https://example.com/?q=a+b"))
        XCTAssertEqual(opened, ["https://example.com/?q=a+b"])
        XCTAssertTrue(platform.shortcuts.isEmpty)
    }

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

    func testMaximizeUsesFrozenTargetAndReportsVerificationFailure() async {
        let platform = RecordingGestureTargetActionPlatform()
        platform.error = GestureTargetError.windowMaximizeFailed
        let executor = ActionExecutor(targetPlatform: platform)
        let context = makeTargetContext()
        do {
            try await executor.execute(.window(.maximize), target: .resolved(context))
            XCTFail("Expected maximize failure")
        } catch GestureTargetError.windowMaximizeFailed {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(platform.windows.count, 1)
        XCTAssertEqual(platform.windows.first?.command, .maximize)
        XCTAssertTrue(platform.windows.first?.target.window === context.window)
        XCTAssertEqual(executor.lastError, L10n.string("action.targetWindowMaximizeFailed"))
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
        let executor = ActionExecutor(targetPlatform: platform, globalChordPoster: { chords.append($0) },
                                      systemShortcutStatus: { _ in .unknown })
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
        let executor = ActionExecutor(targetPlatform: platform, globalChordPoster: { _ in postedGlobally = true },
                                      systemShortcutStatus: { _ in .disabled })
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
        let executor = ActionExecutor(globalChordPoster: { received = $0 },
                                      systemShortcutStatus: { _ in .disabled })
        try await executor.executeForTesting(.system(SystemAction(command: .spaceLeft, shortcutOverride: chord)))
        XCTAssertEqual(received, chord)
        let failing = ActionExecutor(globalChordPoster: { _ in throw ShortcutActionError.eventSourceUnavailable },
                                     systemShortcutStatus: { _ in .unknown })
        do {
            try await failing.executeForTesting(.system(SystemAction(command: .missionControl)))
            XCTFail("Expected event posting failure")
        } catch ShortcutActionError.eventSourceUnavailable {
        }
        XCTAssertNotNil(failing.lastError)
    }

    func testDisabledSystemShortcutFailsVisiblyUnlessOverridden() async throws {
        let platform = RecordingGestureTargetActionPlatform()
        var chords: [ShortcutChord] = []
        let executor = ActionExecutor(targetPlatform: platform, globalChordPoster: { chords.append($0) },
                                      systemShortcutStatus: { $0 == .applicationWindows ? .enabled($0.defaultChord) : .disabled })
        for command in SystemCommand.allCases where command != .applicationWindows {
            do {
                try await executor.execute(.system(SystemAction(command: command)),
                                           target: .resolved(makeTargetContext()))
                XCTFail("Expected \(command) to report its disabled system shortcut")
            } catch ActionExecutionError.systemShortcutDisabled(let failed) {
                XCTAssertEqual(failed, command)
            }
            XCTAssertNotNil(executor.lastError)
        }
        XCTAssertTrue(chords.isEmpty)
        let custom = ShortcutChord(modifiers: [.option], keyCode: 126)
        try await executor.execute(.system(SystemAction(command: .missionControl, shortcutOverride: custom)),
                                   target: .unavailable(.windowUnavailable))
        try await executor.execute(.system(SystemAction(command: .applicationWindows)),
                                   target: .resolved(makeTargetContext()))
        XCTAssertEqual(chords, [custom])
        XCTAssertEqual(platform.shortcuts.count, 1)
    }

    func testSymbolicHotKeyParsingAndComparison() {
        func entry(enabled: Bool = true, key: Int, mask: Int) -> [String: Any] {
            ["enabled": NSNumber(value: enabled),
             "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: key), NSNumber(value: mask)],
                       "type": "standard"]]
        }
        let up = UInt16(126)
        // macOS stores Control + Up with the arrow's intrinsic Fn bit.
        XCTAssertEqual(SystemCommand.shortcutStatus(from: entry(key: 126, mask: 0x840000)),
                       .enabled(ShortcutChord(modifiers: [.control], keyCode: up)))
        XCTAssertEqual(SystemCommand.shortcutStatus(from: entry(key: 0, mask: 0x900000)),
                       .enabled(ShortcutChord(modifiers: [.function, .command], keyCode: 0)))
        XCTAssertEqual(SystemCommand.shortcutStatus(from: entry(enabled: false, key: 126, mask: 0x840000)), .disabled)
        XCTAssertEqual(SystemCommand.shortcutStatus(from: entry(key: 65535, mask: 0)), .disabled)
        XCTAssertEqual(SystemCommand.shortcutStatus(from: nil), .unknown)
        XCTAssertEqual(SystemCommand.shortcutStatus(from: ["enabled": NSNumber(value: true)]), .unknown)
        XCTAssertEqual(SystemCommand.missionControl.symbolicHotKeyID, 32)
        XCTAssertEqual(SystemCommand.applicationWindows.symbolicHotKeyID, 33)
        XCTAssertEqual(SystemCommand.spaceLeft.symbolicHotKeyID, 79)
        XCTAssertEqual(SystemCommand.spaceRight.symbolicHotKeyID, 81)

        let recorded = ShortcutChord(modifiers: [.function, .shift, .control], keyCode: up)
        XCTAssertTrue(SystemCommand.chordsMatch(recorded, ShortcutChord(modifiers: [.control, .shift], keyCode: up)))
        XCTAssertFalse(SystemCommand.chordsMatch(recorded, ShortcutChord(modifiers: [.control], keyCode: up)))
        XCTAssertFalse(SystemCommand.chordsMatch(ShortcutChord(modifiers: [.function, .command], keyCode: 0),
                                                 ShortcutChord(modifiers: [.command], keyCode: 0)))
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
    var onPostShortcut: (() -> Void)?
    private(set) var shortcuts: [ShortcutCall] = []
    private(set) var windows: [WindowCall] = []

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext,
        beforePosting: (() -> Void)?
    ) async throws {
        shortcuts.append(ShortcutCall(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord,
            target: target
        ))
        if let error { throw error }
        beforePosting?()
        onPostShortcut?()
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
