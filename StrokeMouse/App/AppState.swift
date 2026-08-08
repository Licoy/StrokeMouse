import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    static let settingsWindowID = "settings"

    let configStore: ConfigStore
    let permissionManager: PermissionManager
    let actionExecutor: ActionExecutor
    let gestureRuntime: GestureRuntime
    let updaterService: UpdaterService
    private var gestureConfigurationRevision: UInt64 = 0

    var showOnboarding: Bool
    var settingsTab: SettingsTab = .gestures
    /// Bumped when language changes so SwiftUI rebuilds string-based UI.
    var languageEpoch: UInt = 0
    /// Stored so MenuBarExtra label observes AppState directly (nested Observation is unreliable there).
    private(set) var menuBarIconStatus: MenuBarIconStatus = .normal
    /// Whether `MenuBarExtra` is inserted (user preference to show the menu bar icon).
    var menuBarExtraInserted: Bool = true
    /// AppKit settings window — independent of MenuBarExtra so hide-icon mode never flash-remounts.
    private var settingsWindowController: SettingsWindowController?
    /// Test seam: when set, `openSettings` calls this instead of creating a real window
    /// (avoids AppStorage dual-hide side effects in the unit-test host).
    var presentSettingsWindowHandler: ((SettingsTab) -> Void)?

    var resolvedLocale: Locale { L10n.locale }

    var prefersHideMenuBarIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.hideMenuBarIcon)
    }

    init() {
        Self.preconfigureLocalization()

        let configStore = ConfigStore()
        let permissionManager = PermissionManager()
        let actionExecutor = ActionExecutor()
        let gestureRuntime = GestureRuntime(
            permissionManager: permissionManager,
            actionExecutor: actionExecutor,
            multitouchSourceFactory: {
                MultitouchSupportAdapter()
            }
        )
        let updaterService = UpdaterService()

        self.configStore = configStore
        self.permissionManager = permissionManager
        self.actionExecutor = actionExecutor
        self.gestureRuntime = gestureRuntime
        self.updaterService = updaterService
        self.showOnboarding = !UserDefaults.standard.bool(forKey: PreferenceKey.hasCompletedOnboarding)

        // Permission polling drives both revocation teardown and restoration.
        // Re-applying does not clear an unrelated latched multitouch failure.
        permissionManager.onTrustChanged = { [weak self] isTrusted in
            self?.gestureRuntime.accessibilityTrustDidChange(isTrusted)
            self?.refreshMenuBarIconStatus()
        }

        // ConfigStore notifies only after validation + durable persistence.
        configStore.onGesturesChanged = { [weak self] in
            self?.applyCurrentGestureConfiguration()
        }

        applyLaunchPreferences()
        syncMenuBarExtraInserted()
        installSettingsWindowCloseObserver()
        installOpenSettingsNotificationObserver()

        // Defer the event tap until the main run loop is spinning. Creating a
        // filtering CGEventTap during @State construction (esp. on macOS 14)
        // can leave cursor delivery gated on a not-yet-ready process.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyCurrentGestureConfiguration()
            self.refreshMenuBarIconStatus()
        }
    }

    /// AppDelegate / external code posts this; route through `openSettings`.
    private func installOpenSettingsNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .strokeMouseOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                let tab = note.object as? SettingsTab ?? .gestures
                self?.openSettings(tab: tab)
            }
        }
    }

    /// Recompute menu bar insertion from the user hide preference.
    func syncMenuBarExtraInserted() {
        menuBarExtraInserted = !prefersHideMenuBarIcon
    }

    /// Persist hide-menu-bar preference and refresh insertion.
    func setHideMenuBarIcon(_ hide: Bool) {
        UserDefaults.standard.set(hide, forKey: PreferenceKey.hideMenuBarIcon)
        syncMenuBarExtraInserted()
    }

    /// Called when SwiftUI's `MenuBarExtra(isInserted:)` binding changes (e.g. user removes item).
    func handleMenuBarExtraInsertedChange(_ inserted: Bool) {
        setHideMenuBarIcon(!inserted)
    }

    func refreshMenuBarIconStatus() {
        menuBarIconStatus = MenuBarIconStatus.resolve(
            isAccessibilityTrusted: permissionManager.isAccessibilityTrusted,
            isGesturesEnabled: gestureRuntime.isEnabled
        )
    }

    private static func preconfigureLocalization() {
        let raw = UserDefaults.standard.string(forKey: PreferenceKey.language)
            ?? LanguageOverride.system.rawValue
        L10n.apply(LanguageOverride(rawValue: raw) ?? .system)
    }

    /// When settings closes, restore accessory (hidden Dock) if the user enabled it.
    private func installSettingsWindowCloseObserver() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.isSettingsWindow(window) else { return }
            Task { @MainActor in
                // Defer slightly so SwiftUI finishes teardown first.
                try? await Task.sleep(for: .milliseconds(50))
                self?.applyDockVisibility()
            }
        }

        // Also restore when app resigns active and no settings window remains.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if !Self.isSettingsWindowVisible() {
                    self.applyDockVisibility()
                }
            }
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue ?? ""
        let title = window.title
        return id.contains(settingsWindowID)
            || title.localizedCaseInsensitiveContains("Settings")
            || title.localizedCaseInsensitiveContains("设置")
            || title.localizedCaseInsensitiveContains("StrokeMouse")
    }

    private static func isSettingsWindowVisible() -> Bool {
        NSApp.windows.contains { isSettingsWindow($0) && $0.isVisible }
    }

    func applyLaunchPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PreferenceKey.gesturesEnabled) == nil {
            defaults.set(true, forKey: PreferenceKey.gesturesEnabled)
        }
        if defaults.object(forKey: PreferenceKey.minStrokeDistance) == nil {
            defaults.set(Double(Constants.defaultMinStrokeDistance), forKey: PreferenceKey.minStrokeDistance)
        }
        if defaults.object(forKey: PreferenceKey.matchThreshold) == nil {
            defaults.set(Constants.freePathMatchThreshold, forKey: PreferenceKey.matchThreshold)
        }
        if defaults.object(forKey: PreferenceKey.appearance) == nil {
            defaults.set(AppearanceMode.system.rawValue, forKey: PreferenceKey.appearance)
        }
        if defaults.object(forKey: PreferenceKey.language) == nil {
            defaults.set(LanguageOverride.system.rawValue, forKey: PreferenceKey.language)
        }
        if defaults.object(forKey: PreferenceKey.directTrackpadEnabled) == nil {
            defaults.set(true, forKey: PreferenceKey.directTrackpadEnabled)
        }

        let storedMatchThreshold = defaults.object(
            forKey: PreferenceKey.matchThreshold
        ) as? Double
        let matchThreshold = GestureRecognitionPolicy.normalizedMatchThreshold(
            storedMatchThreshold
        )

        defaults.set(matchThreshold, forKey: PreferenceKey.matchThreshold)
        applyCurrentGestureConfiguration(enabledOverride: false)
        refreshMenuBarIconStatus()

        applyLanguage()
        applyAppearance()
        applyDockVisibility()
    }

    /// - Parameter keepSettingsVisible: When true (user toggled language in UI), re-activate settings without remounting the window.
    func applyLanguage(keepSettingsVisible: Bool = false) {
        let raw = UserDefaults.standard.string(forKey: PreferenceKey.language) ?? LanguageOverride.system.rawValue
        let override = LanguageOverride(rawValue: raw) ?? .system
        L10n.apply(override)
        languageEpoch &+= 1
        settingsWindowController?.updateTitleForLocale()
        guard keepSettingsVisible else { return }
        // Keep settings window open and on top after locale change (do not remount).
        elevateForSettingsWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController?.bringToFront()
        }
    }

    func setGesturesEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.gesturesEnabled)
        applyCurrentGestureConfiguration()
        refreshMenuBarIconStatus()
    }

    func updateMinStrokeDistance(_ value: Double) {
        UserDefaults.standard.set(value, forKey: PreferenceKey.minStrokeDistance)
        applyCurrentGestureConfiguration()
    }

    func updateMatchThreshold(_ value: Double) {
        let normalized = GestureRecognitionPolicy.normalizedMatchThreshold(value)
        UserDefaults.standard.set(
            normalized,
            forKey: PreferenceKey.matchThreshold
        )
        applyCurrentGestureConfiguration()
    }

    func updateShowGestureHUD(_ enabled: Bool) {
        DrawingStyle.showHUD = enabled
        applyCurrentGestureConfiguration()
    }

    func updateShowLiveMismatchFeedback(_ enabled: Bool) {
        DrawingStyle.showLiveMismatchFeedback = enabled
        applyCurrentGestureConfiguration()
    }

    func updateGestureHUDCapture(_ included: Bool) {
        DrawingStyle.includeHUDInCaptures = included
        GestureHUDController.shared.setIncludedInCaptures(included)
    }

    func setDirectTrackpadEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(
            enabled,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        applyCurrentGestureConfiguration()
    }

    func retryGestureInputs() {
        permissionManager.refresh()
        gestureRuntime.retryFailedInputs()
        refreshMenuBarIconStatus()
    }

    func applyCurrentGestureConfiguration(
        enabledOverride: Bool? = nil
    ) {
        gestureConfigurationRevision &+= 1
        let defaults = UserDefaults.standard
        let storedDistance = defaults.double(
            forKey: PreferenceKey.minStrokeDistance
        )
        let configuration = GestureRuntimeConfiguration(
            revision: gestureConfigurationRevision,
            isEnabled: enabledOverride
                ?? defaults.bool(forKey: PreferenceKey.gesturesEnabled),
            profiles: configStore.gestures,
            minimumStrokeDistance: storedDistance > 0
                ? CGFloat(storedDistance)
                : Constants.defaultMinStrokeDistance,
            pathMatchThreshold: GestureRecognitionPolicy
                .normalizedMatchThreshold(
                    defaults.object(
                        forKey: PreferenceKey.matchThreshold
                    ) as? Double
                ),
            showsHUD: DrawingStyle.showHUD,
            showsLiveMismatchFeedback: DrawingStyle.showLiveMismatchFeedback,
            directTrackpadEnabled: defaults.bool(
                forKey: PreferenceKey.directTrackpadEnabled
            )
        )
        do {
            try gestureRuntime.apply(configuration)
        } catch {
            assertionFailure(
                "Persisted gesture configuration was rejected: \(error)"
            )
        }
    }

    func applyAppearance() {
        // NSApp may not be ready during very early launch / test host bootstrap.
        let app = NSApplication.shared
        let raw = UserDefaults.standard.string(forKey: PreferenceKey.appearance) ?? AppearanceMode.system.rawValue
        let mode = AppearanceMode(rawValue: raw) ?? .system
        switch mode {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func preferredActivationPolicy() -> NSApplication.ActivationPolicy {
        UserDefaults.standard.bool(forKey: PreferenceKey.hideDockIcon) ? .accessory : .regular
    }

    /// Apply the user's Dock preference. Safe to call often.
    func applyDockVisibility() {
        let desired = preferredActivationPolicy()
        if desired == .regular {
            AppDelegate.applyApplicationIcon(to: NSApp)
        }
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
        }
    }

    /// Temporarily switch to `.regular` so a settings window can key/activate.
    /// Always pair with `applyDockVisibility()` when the window closes.
    func elevateForSettingsWindowIfNeeded() {
        // NSApp may be unavailable during unit-test host bootstrap.
        let app = NSApplication.shared
        if preferredActivationPolicy() == .accessory {
            AppDelegate.applyApplicationIcon(to: app)
            if app.activationPolicy() != .regular {
                app.setActivationPolicy(.regular)
            }
        } else {
            applyDockVisibility()
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: PreferenceKey.hasCompletedOnboarding)
        showOnboarding = false
        permissionManager.refresh()
        if permissionManager.isAccessibilityTrusted {
            retryGestureInputs()
        }
        // If still untrusted, leave engine idle — menu bar / permissions tab guide the user.
    }

    func openSettings(tab: SettingsTab = .gestures) {
        settingsTab = tab
        // May temporarily show Dock icon so the window can appear; restored on close.
        elevateForSettingsWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)

        if let presentSettingsWindowHandler {
            presentSettingsWindowHandler(tab)
            return
        }

        let controller = settingsWindowController ?? SettingsWindowController(appState: self)
        settingsWindowController = controller
        controller.show(tab: tab)
    }

    /// Show an existing settings window if one was already created.
    static func bringSettingsWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        let candidates = NSApp.windows.filter { isSettingsWindow($0) }
        if let window = candidates.first(where: { ($0.identifier?.rawValue ?? "").contains(settingsWindowID) })
            ?? candidates.first
        {
            window.makeKeyAndOrderFront(nil)
        }
    }

}

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case gestures
    case general
    case permissions
    case about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .gestures: return "tab.gestures"
        case .general: return "tab.general"
        case .permissions: return "tab.permissions"
        case .about: return "tab.about"
        }
    }

    var systemImage: String {
        switch self {
        case .gestures: return "hand.draw"
        case .general: return "gearshape"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}
