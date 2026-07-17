import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = appState.languageEpoch

        Button {
            appState.setGesturesEnabled(!appState.gestureEngine.isEnabled)
        } label: {
            Text(appState.gestureEngine.isEnabled
                 ? L10n.string("menu.pauseGestures")
                 : L10n.string("menu.resumeGestures"))
        }

        Button(L10n.string("menu.openSettings")) {
            // Defer: MenuBarExtra tears down its content as the menu closes.
            let open = appState.openSettings
            DispatchQueue.main.async {
                open(.gestures)
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Text(statusText)
            .foregroundStyle(.secondary)

        if !appState.permissionManager.isAccessibilityTrusted {
            Button(L10n.string("menu.grantAccessibility")) {
                appState.permissionManager.authorizeAccessibility()
            }
        }

        Divider()

        Button(L10n.string("menu.about")) {
            let open = appState.openSettings
            DispatchQueue.main.async {
                open(.about)
            }
        }

        Button {
            // Defer: MenuBarExtra tears down its content as the menu closes.
            let check = appState.updaterService.checkForUpdates
            DispatchQueue.main.async {
                check()
            }
        } label: {
            Text(
                appState.updaterService.isCheckingForUpdates
                    ? L10n.string("update.checking")
                    : L10n.string("update.checkNow")
            )
        }
        .disabled(appState.updaterService.isCheckingForUpdates)

        Button(L10n.string("menu.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        let key = appState.gestureEngine.statusMessageKey
        return L10n.string(key)
    }
}
