import AppKit
import Foundation
import Observation

enum ActionExecutionError: LocalizedError {
    case appNotFound(String)
    case invalidURL(String)
    case openFailed
    case targetRequiredForTest

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
        }
    }
}

@MainActor
protocol GestureTargetActionPlatform {
    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) async throws

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws
}

@MainActor
@Observable
final class ActionExecutor {
    private(set) var lastError: String?
    private(set) var lastActionSummary: String?

    private let targetPlatform: any GestureTargetActionPlatform

    init(targetPlatform: (any GestureTargetActionPlatform)? = nil) {
        self.targetPlatform = targetPlatform ?? WindowActions()
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
        case .shortcut(let keyCode, let modifiers, _):
            try await targetPlatform.performShortcut(
                keyCode: keyCode,
                modifiers: modifiers,
                target: try target.requireContext()
            )
        case .openApp(let bundleIdentifier, _):
            try await openApplication(bundleIdentifier: bundleIdentifier)
        case .openURL(let string):
            try openURL(string)
        case .shell(let command):
            try await ScriptActions.runShell(command)
        case .media(let command):
            MediaActions.perform(command)
        case .window(let command):
            try await targetPlatform.performWindow(
                command,
                target: try target.requireContext()
            )
        case .appleScript(let source):
            try await ScriptActions.runAppleScript(source)
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

    private func openURL(_ string: String) throws {
        guard let url = URL(string: string) else {
            throw ActionExecutionError.invalidURL(string)
        }
        guard NSWorkspace.shared.open(url) else {
            throw ActionExecutionError.openFailed
        }
    }
}

extension GestureAction {
    var requiresCapturedTarget: Bool {
        switch self {
        case .shortcut, .window:
            return true
        case .none, .openApp, .openURL, .shell, .media, .appleScript:
            return false
        }
    }
}
