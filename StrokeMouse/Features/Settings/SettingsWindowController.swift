import AppKit
import SwiftUI

/// AppKit-owned settings window so opening settings does not require a mounted
/// `MenuBarExtra` / SwiftUI `openWindow` host (avoids menu-bar icon flash when hidden).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(tab: SettingsTab) {
        guard let appState else { return }
        appState.settingsTab = tab
        let window = ensureWindow(appState: appState)
        window.title = L10n.string("settings.windowTitle")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringToFront() {
        guard let window else { return }
        window.title = L10n.string("settings.windowTitle")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateTitleForLocale() {
        window?.title = L10n.string("settings.windowTitle")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Window is kept (`isReleasedWhenClosed = false`) for fast re-open without flash.
        // Dock restoration is handled by AppState close / resign-active observers.
    }

    // MARK: - Private

    private func ensureWindow(appState: AppState) -> NSWindow {
        if let window {
            return window
        }

        let root = SettingsRootView()
            .environment(appState)
            .environment(\.locale, appState.resolvedLocale)
            .frame(minWidth: 820, minHeight: 520)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(AppState.settingsWindowID)
        window.title = L10n.string("settings.windowTitle")
        window.contentViewController = hosting
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 560))
        window.center()
        self.window = window
        return window
    }
}
