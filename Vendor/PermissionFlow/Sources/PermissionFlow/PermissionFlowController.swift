#if os(macOS)
import AppKit
import Combine
import SystemSettingsKit
import SwiftUI

@available(macOS 13.0, *)
@MainActor
public final class PermissionFlowController: ObservableObject {
    /// The package exposes a single active floating panel at a time so opening
    /// a second permission flow closes the previous panel automatically.
    private static var activeController: PermissionFlowController?
    private let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    /// Apps currently represented in the floating panel.
    @Published public private(set) var droppedApps: [URL]

    /// The permission pane currently being guided.
    @Published public private(set) var currentPane: PermissionFlowPane?

    /// Drives the visibility of the "reopen settings" action.
    @Published var isSettingsFrontmost = false

    /// Drives the header icon animation while the app card is being dragged.
    @Published var isDraggingApp = false

    /// Drives the locale environment used by the floating SwiftUI panel.
    @Published public private(set) var localeIdentifier: String?

    public var onDrop: ((URL) -> Void)?

    private let configuration: PermissionFlowConfiguration
    private let tracker = SettingsWindowTracker()

    private var panel: FloatingDropPanel?
    private var pendingLaunchSourceFrame: CGRect?
    private var previousFrontmostApplicationPID: pid_t?
    private var previousFrontmostApplicationBundleIdentifier: String?
    private var cancellables = Set<AnyCancellable>()

    public init(configuration: PermissionFlowConfiguration = .init()) {
        self.configuration = configuration
        self.droppedApps = configuration.requiredAppURLs.uniqueAppURLs()
        self.localeIdentifier = configuration.localeIdentifier

        updateFrontmostAppState()
        bindTrackerCallbacks()
        observeFrontmostApplication()
    }

    /// Opens the requested privacy pane and starts the floating guidance flow.
    ///
    /// - Parameters:
    ///   - pane: The permission pane to open inside System Settings.
    ///   - suggestedAppURLs: Optional `.app` bundle URLs that should appear in
    ///     the floating panel as drag candidates. This parameter defaults to an
    ///     empty array, which means no explicit app list is injected here.
    ///     When this value is empty and no previously registered app is
    ///     available, the floating panel falls back to `Bundle.main.bundleURL`
    ///     if the current host bundle is itself an `.app`.
    ///   - sourceFrameInScreen: Optional source rect in screen coordinates used
    ///     as the launch point for the fly-to-settings animation. If omitted,
    ///     the panel still appears, but it skips the source-origin animation.
    public func authorize(
        pane: PermissionFlowPane,
        suggestedAppURLs: [URL] = [],
        sourceFrameInScreen: CGRect? = nil
    ) {
        closeOtherActivePanelIfNeeded()

        rememberPreviousFrontmostApplication()
        currentPane = pane
        pendingLaunchSourceFrame = sourceFrameInScreen
        mergeDroppedApps(with: suggestedAppURLs)
        SystemSettings.open(url: pane.settingsURL)

        guard pane.supportsFloatingAuthorizationPanel else { return }

        Self.activeController = self
        // Do NOT show the floating panel yet — wait until System Settings has a
        // tracked window frame. Showing at the click source first was the old
        // behavior and left the helper floating over the host app alone.
        ensurePanelPrepared()
        tracker.startTracking(promptIfNeeded: configuration.promptForAccessibilityTrust)
        // If Settings was already open, the tracker may already know the frame.
        if let settingsFrame = tracker.currentFrame {
            presentPanel(panel, for: settingsFrame)
        }
    }

    /// Shows the panel once System Settings geometry is known. If the target
    /// window is not tracked yet, this is a no-op until the next frame update.
    public func showPanel() {
        ensurePanelPrepared()
        guard let panel else { return }

        if let settingsFrame = tracker.currentFrame {
            presentPanel(panel, for: settingsFrame)
        }
        // No early orderFront at click source / screen center.
    }

    /// Creates the panel without ordering it front.
    private func ensurePanelPrepared() {
        if panel == nil {
            panel = FloatingDropPanel(controller: self)
        }
    }

    public func closePanel(returnToPreviousApp: Bool = false) {
        tracker.stopTracking()
        panel?.close()
        panel = nil
        pendingLaunchSourceFrame = nil

        if Self.activeController === self {
            Self.activeController = nil
        }

        if returnToPreviousApp {
            reactivatePreviousFrontmostApplication()
        }
    }

    public func resetDroppedApps() {
        droppedApps = configuration.requiredAppURLs.uniqueAppURLs()
    }

    /// Updates the locale injected into the floating panel.
    public func setLocaleIdentifier(_ localeIdentifier: String?) {
        guard self.localeIdentifier != localeIdentifier else { return }
        self.localeIdentifier = localeIdentifier
        panel?.updateLocaleIdentifier(localeIdentifier)
    }

    /// Registers a unique `.app` bundle URL and notifies the host if needed.
    public func registerDroppedApp(_ url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return }
        let normalizedURL = url.standardizedFileURL
        guard droppedApps.contains(normalizedURL) == false else { return }
        droppedApps.append(normalizedURL)
        onDrop?(normalizedURL)
    }

    /// The panel always renders a single primary app card. If the host has not
    /// supplied one yet, the host application's bundle becomes the fallback.
    var preferredAppURL: URL? {
        if let first = droppedApps.first {
            return first
        }
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        return bundleURL.pathExtension.lowercased() == "app" ? bundleURL : nil
    }

    /// The panel becomes mouse-transparent while dragging so System Settings
    /// underneath can receive the drop.
    func setPanelDragging(_ isDragging: Bool) {
        isDraggingApp = isDragging
        panel?.setDraggingPassthrough(isDragging)
    }

    /// Keeps System Settings visually present whenever the floating panel is
    /// clicked or momentarily considered for focus.
    func keepSettingsVisible() {
        SystemSettings.activate()
        panel?.orderFrontRegardless()
    }

    func reopenCurrentSettingsPane() {
        guard let currentPane else { return }
        SystemSettings.open(url: currentPane.settingsURL)
        panel?.orderFrontRegardless()
    }

    /// Merges unique app bundle URLs into the current panel list.
    func mergeDroppedApps(with urls: [URL]) {
        for url in urls.uniqueAppURLs() {
            registerDroppedApp(url)
        }
    }

    private func bindTrackerCallbacks() {
        tracker.onFrameChange = { [weak self] frame in
            // Prefer a direct main-queue hop over unstructured Task allocation;
            // this path fires frequently while System Settings is settling.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.presentPanel(self.panel, for: frame)
            }
        }
        tracker.onTrackingEnded = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.closePanel()
            }
        }
    }

    private func observeFrontmostApplication() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFrontmostAppState()
            }
            .store(in: &cancellables)
    }

    private func closeOtherActivePanelIfNeeded() {
        if let activeController = Self.activeController, activeController !== self {
            activeController.closePanel()
        }
    }

    private func rememberPreviousFrontmostApplication() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        guard frontmostApplication?.bundleIdentifier != systemSettingsBundleIdentifier else { return }
        previousFrontmostApplicationPID = frontmostApplication?.processIdentifier
        previousFrontmostApplicationBundleIdentifier = frontmostApplication?.bundleIdentifier
    }

    private func reactivatePreviousFrontmostApplication() {
        defer {
            previousFrontmostApplicationPID = nil
            previousFrontmostApplicationBundleIdentifier = nil
        }

        if let previousFrontmostApplicationPID,
           let application = NSRunningApplication(processIdentifier: previousFrontmostApplicationPID) {
            application.activate(options: [.activateIgnoringOtherApps])
            return
        }

        guard let previousFrontmostApplicationBundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: previousFrontmostApplicationBundleIdentifier)
            .first?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private func presentPanel(_ panel: FloatingDropPanel?, for settingsFrame: CGRect) {
        guard let panel else { return }
        // Ignore zero/empty frames while System Settings is still creating its window.
        guard settingsFrame.width > 80, settingsFrame.height > 80 else { return }

        if let sourceFrame = pendingLaunchSourceFrame {
            // Settings is already tracked — fly from the click origin to the window.
            panel.present(from: sourceFrame, to: settingsFrame)
            pendingLaunchSourceFrame = nil
        } else {
            panel.snap(to: settingsFrame)
        }
    }

    private func updateFrontmostAppState() {
        isSettingsFrontmost =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == systemSettingsBundleIdentifier
    }
}

@available(macOS 13.0, *)
private extension Array where Element == URL {
    /// Normalizes and de-duplicates `.app` bundle URLs.
    func uniqueAppURLs() -> [URL] {
        var seen = Set<String>()
        return compactMap { url in
            let normalized = url.standardizedFileURL
            guard normalized.pathExtension.lowercased() == "app" else { return nil }
            return seen.insert(normalized.path).inserted ? normalized : nil
        }
    }

    /// Uses normalized file paths for containment because equivalent file URLs
    /// can differ in their string representation.
    func contains(_ url: URL) -> Bool {
        contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path })
    }
}
#endif
