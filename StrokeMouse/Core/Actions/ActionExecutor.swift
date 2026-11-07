import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

enum ActionExecutionError: LocalizedError {
    case appNotFound(String)
    case invalidURL(String)
    case openFailed
    case targetRequiredForTest
    case selectionCopyInProgress
    case selectionCopyTimedOut
    case selectionCopyHasNoText
    case systemShortcutDisabled(SystemCommand)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return L10n.string("action.appNotFound")
        case .invalidURL:
            return L10n.string("action.invalidURL")
        case .openFailed:
            return L10n.string("action.openFailed")
        case .targetRequiredForTest:
            return L10n.string("editor.testActionNeedsTarget")
        case .selectionCopyInProgress:
            return L10n.string("action.selectionURL.copyInProgress")
        case .selectionCopyTimedOut:
            return L10n.string("action.selectionURL.copyTimedOut")
        case .selectionCopyHasNoText:
            return L10n.string("action.selectionURL.copyHasNoText")
        case .systemShortcutDisabled(let command):
            return String(
                format: L10n.string("system.error.shortcutDisabled"),
                locale: L10n.locale,
                L10n.string(command.displayKey)
            )
        }
    }
}

@MainActor
protocol GestureTargetActionPlatform {
    /// Runs the callback after the target is ready and immediately before posting the shortcut.
    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext,
        beforePosting: (() -> Void)?
    ) async throws

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws
}

extension GestureTargetActionPlatform {
    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord? = nil,
        target: GestureTargetContext
    ) async throws {
        try await performShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord,
            target: target,
            beforePosting: nil
        )
    }
}

@MainActor
protocol ApplicationSwitching {
    func perform(_ command: ApplicationSwitchCommand) throws
}

@MainActor
struct MacApplicationSwitcher: ApplicationSwitching {
    func perform(_ command: ApplicationSwitchCommand) throws {
        let chord = command.shortcutChord
        try ShortcutAction.post(
            keyCode: chord.legacyKeyCode,
            modifiers: chord.legacyModifiers,
            orderedChord: chord
        )
    }
}

@MainActor
@Observable
final class ActionExecutor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.strokemouse.app",
        category: "ActionExecutor"
    )

    private(set) var lastError: String?
    private(set) var lastActionSummary: String?

    private let targetPlatform: any GestureTargetActionPlatform
    private let applicationSwitcher: any ApplicationSwitching
    private let globalChordPoster: (ShortcutChord) throws -> Void
    private let systemShortcutStatus: (SystemCommand) -> SystemShortcutStatus
    private let pasteboard: NSPasteboard?
    private let urlOpener: (URL) -> Bool
    private var isCopyingSelection = false

    init(
        targetPlatform: (any GestureTargetActionPlatform)? = nil,
        applicationSwitcher: (any ApplicationSwitching)? = nil,
        globalChordPoster: ((ShortcutChord) throws -> Void)? = nil,
        systemShortcutStatus: ((SystemCommand) -> SystemShortcutStatus)? = nil,
        pasteboard: NSPasteboard? = nil,
        urlOpener: ((URL) -> Bool)? = nil
    ) {
        self.targetPlatform = targetPlatform ?? WindowActions()
        self.applicationSwitcher = applicationSwitcher ?? MacApplicationSwitcher()
        self.systemShortcutStatus = systemShortcutStatus ?? { $0.currentSystemShortcut() }
        self.pasteboard = pasteboard
        self.urlOpener = urlOpener ?? { NSWorkspace.shared.open($0) }
        self.globalChordPoster = globalChordPoster ?? { chord in
            try ShortcutAction.post(
                keyCode: chord.legacyKeyCode,
                modifiers: chord.legacyModifiers,
                orderedChord: chord
            )
        }
    }

    func execute(
        _ action: GestureAction,
        target: GestureTargetResolution
    ) async throws {
        lastError = nil
        lastActionSummary = action.detail

        do {
            try await perform(action, target: target)
        } catch {
            if let targetError = error as? GestureTargetError,
               case .axOperationFailed(let operation, let code) = targetError
            {
                let context = target.context
                let processIdentifier = context.map {
                    String($0.processIdentifier)
                } ?? "unknown"
                let bundleIdentifier = context?.bundleIdentifier ?? "unknown"
                let policy = context?.policy.rawValue ?? "unknown"
                Self.logger.error(
                    "AX action failed operation=\(operation.rawValue, privacy: .public) code=\(code.rawValue, privacy: .public) pid=\(processIdentifier, privacy: .public) bundleID=\(bundleIdentifier, privacy: .public) policy=\(policy, privacy: .public)"
                )
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    func executeForTesting(_ action: GestureAction) async throws {
        guard !action.requiresCapturedTarget else {
            let error = ActionExecutionError.targetRequiredForTest
            lastError = error.localizedDescription
            throw error
        }
        try await execute(
            action,
            target: .unavailable(.targetNotCaptured(.frontmostWindow))
        )
    }

    private func perform(
        _ action: GestureAction,
        target: GestureTargetResolution
    ) async throws {
        switch action {
        case .none:
            return
        case .shortcut(let keyCode, let modifiers, _, let orderedChord):
            try await targetPlatform.performShortcut(
                keyCode: keyCode,
                modifiers: modifiers,
                orderedChord: orderedChord,
                target: try target.requireContext()
            )
        case .openApp(let bundleIdentifier, _):
            try await openApplication(bundleIdentifier: bundleIdentifier)
        case .openURL(let string):
            guard let url = URL(string: string) else {
                throw ActionExecutionError.invalidURL(string)
            }
            try openURL(url)
        case .openURLWithSelection(let template):
            try await openURLWithSelection(
                SelectionURLTemplate(template),
                target: target.requireContext()
            )
        case .shell(let command):
            try await ScriptActions.runShell(command)
        case .media(let command):
            MediaActions.perform(command)
        case .window(let command):
            try await targetPlatform.performWindow(
                command,
                target: try target.requireContext()
            )
        case .applicationSwitch(let command):
            try applicationSwitcher.perform(command)
        case .system(let system):
            // Posting the default chord while macOS has it switched off does nothing.
            if system.shortcutOverride == nil, systemShortcutStatus(system.command) == .disabled {
                throw ActionExecutionError.systemShortcutDisabled(system.command)
            }
            let chord = system.effectiveChord
            if system.command.requiresCapturedTarget {
                try await targetPlatform.performShortcut(
                    keyCode: chord.legacyKeyCode,
                    modifiers: chord.legacyModifiers,
                    orderedChord: chord,
                    target: try target.requireContext()
                )
            } else {
                try globalChordPoster(chord)
            }
        case .appleScript(let source):
            try await ScriptActions.runAppleScript(source)
        case .shortcutSequence(let chords):
            let context = try target.requireContext()
            for (index, chord) in chords.enumerated() {
                if index > 0 {
                    try await Task.sleep(for: Constants.shortcutSequenceStepDelay)
                }
                try await targetPlatform.performShortcut(
                    keyCode: chord.legacyKeyCode,
                    modifiers: chord.legacyModifiers,
                    orderedChord: chord,
                    target: context
                )
            }
        }
    }

    private func openApplication(bundleIdentifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            throw ActionExecutionError.appNotFound(bundleIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func openURLWithSelection(
        _ template: SelectionURLTemplate,
        target: GestureTargetContext
    ) async throws {
        guard !isCopyingSelection else { throw ActionExecutionError.selectionCopyInProgress }
        isCopyingSelection = true
        defer { isCopyingSelection = false }

        let pasteboard = pasteboard ?? .general
        let copy = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_C))
        var changeCount = 0
        try await targetPlatform.performShortcut(
            keyCode: copy.legacyKeyCode,
            modifiers: copy.legacyModifiers,
            orderedChord: copy,
            target: target,
            beforePosting: { changeCount = pasteboard.changeCount }
        )

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        var clipboardChanged = false
        while clock.now < deadline {
            try Task.checkCancellation()
            if pasteboard.changeCount != changeCount {
                clipboardChanged = true
                // An app may clear the clipboard before writing its copied items.
                if let types = pasteboard.types, !types.isEmpty {
                    guard let text = pasteboard.string(forType: .string),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { throw ActionExecutionError.selectionCopyHasNoText }
                    try openURL(template.url(for: text))
                    return
                }
            }
            try await clock.sleep(until: min(deadline, clock.now + .milliseconds(25)))
        }
        throw clipboardChanged
            ? ActionExecutionError.selectionCopyHasNoText
            : ActionExecutionError.selectionCopyTimedOut
    }

    private func openURL(_ url: URL) throws {
        guard urlOpener(url) else {
            throw ActionExecutionError.openFailed
        }
    }
}

extension GestureAction {
    var requiresCapturedTarget: Bool {
        switch self {
        case .shortcut, .shortcutSequence, .window, .openURLWithSelection:
            return true
        case .system(let system):
            return system.command.requiresCapturedTarget
        case .none, .openApp, .openURL, .shell, .media,
             .applicationSwitch, .appleScript:
            return false
        }
    }
}
