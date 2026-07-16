import AppKit
import SwiftUI

/// Always-mounted helper (inside MenuBarExtra label) so `openWindow` works
/// even when the menu is closed.
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
            .onReceive(NotificationCenter.default.publisher(for: .strokeMouseOpenSettings)) { note in
                if let tab = note.object as? SettingsTab {
                    appState.settingsTab = tab
                }
                present()
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
        }
    }
}
