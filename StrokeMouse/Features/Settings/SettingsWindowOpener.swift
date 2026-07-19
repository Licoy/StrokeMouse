import AppKit
import SwiftUI

/// Always-mounted helper so `openWindow` works from menu bar, settings, or the
/// temporary menu-bar bridge used when the status item is hidden.
struct SettingsWindowOpener: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: appState.settingsOpenToken) { _, _ in
                present()
            }
            .onAppear {
                // Bridge remounted MenuBarExtra after hide — open if still pending.
                if appState.forceMenuBarExtraForSettingsBridge {
                    present()
                }
            }
    }

    private func present() {
        // Temporary .regular if Dock is hidden (so window can key); restored on close.
        appState.elevateForSettingsWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppState.settingsWindowID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            AppState.bringSettingsWindowToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AppState.bringSettingsWindowToFront()
            // After openWindow, drop temporary menu bar insertion if user prefers hide.
            appState.clearMenuBarSettingsBridgeIfNeeded()
        }
    }
}
