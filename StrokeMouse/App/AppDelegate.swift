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

    /// Menu bar status item ignores SwiftUI `foregroundStyle`; bake tints into a non-template bitmap.
    static func menuBarIcon(for style: MenuBarIconStyle, status: MenuBarIconStatus) -> NSImage {
        switch status {
        case .normal:
            return menuBarIcon(for: style)
        case .paused:
            return tintedTemplateMenuBarIcon(with: .systemYellow)
        case .needPermission:
            return tintedTemplateMenuBarIcon(with: .systemRed)
        }
    }

    static func applicationIcon() -> NSImage {
        let image = image(named: "BrandAppIcon")
        image.isTemplate = false
        return image
    }

    private static func tintedTemplateMenuBarIcon(with color: NSColor) -> NSImage {
        let template = image(named: MenuBarIconStyle.monochrome.assetName)
        template.size = menuBarPointSize
        // Draw real alpha/black pixels (not template-substituted) before recoloring.
        template.isTemplate = false

        let pointSize = menuBarPointSize
        let scale: CGFloat = 2
        let pixelWidth = Int(pointSize.width * scale)
        let pixelHeight = Int(pointSize.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return menuBarIcon(for: .monochrome)
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: pointSize)
        template.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.setFill()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
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

/// Visual state for the menu bar icon. Unauthorized outranks paused.
enum MenuBarIconStatus: Equatable, Sendable {
    case normal
    case paused
    case needPermission

    static func resolve(isAccessibilityTrusted: Bool, isGesturesEnabled: Bool) -> Self {
        if !isAccessibilityTrusted { return .needPermission }
        if !isGesturesEnabled { return .paused }
        return .normal
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
