import AppKit

@MainActor
enum BrandIconProvider {
    static let menuBarPointSize = NSSize(width: 18, height: 18)

    static func menuBarIcon(for style: MenuBarIconStyle) -> NSImage {
        let image = image(named: style.assetName)
        image.size = menuBarPointSize
        image.isTemplate = style == .monochrome
        return image
    }

    static func applicationIcon() -> NSImage {
        let image = image(named: "BrandAppIcon")
        image.isTemplate = false
        return image
    }

    private static func image(named name: String) -> NSImage {
        guard let source = NSImage(named: NSImage.Name(name)),
              let image = source.copy() as? NSImage
        else {
            preconditionFailure("Missing required image asset: \(name)")
        }
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyApplicationIcon(to: NSApp)

        // Default to regular so the settings window can appear; user can hide Dock in General.
        if UserDefaults.standard.bool(forKey: PreferenceKey.hideDockIcon) {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        // First launch: ask AppState (once wired) to open settings for onboarding.
        // MenuBarView listens to settingsOpenToken; we also try after a short delay.
        if !UserDefaults.standard.bool(forKey: PreferenceKey.hasCompletedOnboarding) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .strokeMouseOpenSettings, object: SettingsTab.gestures)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .strokeMouseOpenSettings, object: SettingsTab.gestures)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Do not force Dock visible here — settings presentation handles elevation.
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Restore preferred Dock policy when user leaves the app (settings closed).
        let hide = UserDefaults.standard.bool(forKey: PreferenceKey.hideDockIcon)
        if hide, NSApp.activationPolicy() != .accessory {
            // Only restore if no app-owned visible window (settings may still be open).
            let hasVisibleAppWindow = NSApp.windows.contains { window in
                window.isVisible
                    && window.styleMask.contains(.titled)
                    && !(window is NSPanel)
            }
            if !hasVisibleAppWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @MainActor
    static func applyApplicationIcon(to application: NSApplication) {
        application.applicationIconImage = BrandIconProvider.applicationIcon()
    }
}

extension Notification.Name {
    static let strokeMouseOpenSettings = Notification.Name("com.strokemouse.app.openSettings")
}
