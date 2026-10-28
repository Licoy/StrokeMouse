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

    /// Whether the SwiftUI settings tree is mounted. It exists only while the
    /// window is open.
    var hasContent: Bool {
        window?.contentViewController != nil
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
        guard let appState, let window else { return }
        installContentIfNeeded(in: window, appState: appState)
        window.title = L10n.string("settings.windowTitle")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateTitleForLocale() {
        window?.title = L10n.string("settings.windowTitle")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The window is kept (`isReleasedWhenClosed = false`) for a fast re-open
        // without flash, but its SwiftUI tree is not: an ordered-out hosting view
        // still re-runs bodies on every observed change, competing with gesture
        // sampling and HUD drawing on the main thread. Releasing it also frees
        // sheet sessions such as editor suppression and diagnostics.
        // Dock restoration is handled by AppState close / resign-active observers.
        guard let window = notification.object as? NSWindow,
              window === self.window
        else { return }
        let frame = window.frame
        window.contentViewController = nil
        // Clearing the controller alone may leave its hosting view installed.
        window.contentView = NSView()
        window.setFrame(frame, display: false)
    }

    // MARK: - Private

    private func ensureWindow(appState: AppState) -> NSWindow {
        if let window {
            installContentIfNeeded(in: window, appState: appState)
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(AppState.settingsWindowID)
        window.title = L10n.string("settings.windowTitle")
        installContentIfNeeded(in: window, appState: appState)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 560))
        window.center()
        self.window = window
        return window
    }

    private func installContentIfNeeded(in window: NSWindow, appState: AppState) {
        guard window.contentViewController == nil else { return }
        // Apps may have been installed, moved or removed while settings were closed.
        AppInfoLookup.invalidateCache()

        let root = SettingsRootView()
            .environment(appState)
            .environment(\.locale, appState.resolvedLocale)
            .frame(minWidth: 820, minHeight: 520)

        // Setting a content view controller resizes the window to the new
        // content; keep the frame the user left it at.
        let frame = window.frame
        window.contentViewController = NSHostingController(rootView: root)
        window.setFrame(frame, display: false)
    }
}
