import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ActionExecutor {
    private(set) var lastError: String?
    private(set) var lastActionSummary: String?

    func execute(_ action: GestureAction) {
        lastError = nil
        lastActionSummary = action.detail

        switch action {
        case .none:
            break

        case .shortcut(let keyCode, let modifiers, _):
            captureError {
                try ShortcutAction.post(keyCode: keyCode, modifiers: modifiers)
            }

        case .openApp(let bundleId, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                lastError = "App not found: \(bundleId)"
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                    }
                }
            }

        case .openURL(let string):
            guard let url = URL(string: string) else {
                lastError = "Invalid URL"
                return
            }
            NSWorkspace.shared.open(url)

        case .shell(let command):
            runShell(command)

        case .media(let command):
            MediaActions.perform(command)

        case .window(let command):
            captureError {
                try WindowActions.perform(command)
            }

        case .appleScript(let source):
            runAppleScript(source)
        }
    }

    private func runShell(_ command: String) {
        Task {
            do {
                try await ScriptActions.runShell(command)
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func runAppleScript(_ source: String) {
        Task {
            do {
                try await ScriptActions.runAppleScript(source)
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func captureError(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
