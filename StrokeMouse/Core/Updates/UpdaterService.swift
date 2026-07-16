import AppKit
import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    static let defaultAutomaticallyChecksForUpdates = true

    private static let automaticCheckInterval: TimeInterval = 3_600
    private var updater: SPUUpdater?
    private var userDriver: StrokeMouseSparkleUserDriver?
    private var configurationErrorMessage: String?

    /// True while a user-initiated update check is in progress (for button loading UI).
    private(set) var isCheckingForUpdates = false

    override init() {
        super.init()
        configureSparkle()
        applyPreferences()
        checkForUpdatesOnLaunchIfNeeded()
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.automaticallyChecksForUpdates) == nil {
                return Self.defaultAutomaticallyChecksForUpdates
            }
            return UserDefaults.standard.bool(forKey: PreferenceKey.automaticallyChecksForUpdates)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: PreferenceKey.automaticallyChecksForUpdates)
            applyPreferences()
        }
    }

    var currentVersionDisplay: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        switch installEnvironment.readiness {
        case .ready:
            guard let updater else { return }
            // Re-focus existing update UI without toggling the check-button loading state.
            if updater.sessionInProgress {
                updater.checkForUpdates()
                return
            }
            guard !isCheckingForUpdates else { return }
            isCheckingForUpdates = true
            updater.checkForUpdates()
        case .developmentMode:
            showAlert(
                title: L10n.string("update.checkFailed"),
                message: L10n.string("update.unavailableInDevelopment")
            )
        case .signingKeyMissing:
            showAlert(
                title: L10n.string("update.checkFailed"),
                message: L10n.string("update.signingKeyMissing")
            )
        case .updaterUnavailable:
            var message = L10n.string("update.updaterUnavailable")
            if let configurationErrorMessage {
                message += "\n\n\(configurationErrorMessage)"
            }
            showAlert(title: L10n.string("update.checkFailed"), message: message)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        isCheckingForUpdates = false
    }

    private func applyPreferences() {
        guard let updater else { return }
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        updater.updateCheckInterval = Self.automaticCheckInterval
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        "\(Constants.githubReleasesLatestDownloadBase)/appcast-\(Self.architecture).xml"
    }

    private func configureSparkle() {
        guard isAppBundle, UpdateInstallEnvironment.hasValidSparklePublicKey(sparklePublicKey) else {
            return
        }

        let userDriver = StrokeMouseSparkleUserDriver(
            automaticallyChecksForUpdates: automaticallyChecksForUpdates
        )
        userDriver.onUserInitiatedCheckStateChanged = { [weak self] isChecking in
            self?.isCheckingForUpdates = isChecking
        }
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            configurationErrorMessage = error.localizedDescription
            return
        }
        self.userDriver = userDriver
        self.updater = updater
    }

    private func checkForUpdatesOnLaunchIfNeeded() {
        guard installEnvironment.shouldCheckForUpdatesOnLaunch(
            automaticallyChecksForUpdates: automaticallyChecksForUpdates
        ) else { return }
        updater?.checkForUpdatesInBackground()
    }

    private var installEnvironment: UpdateInstallEnvironment {
        UpdateInstallEnvironment(
            bundlePathExtension: Bundle.main.bundleURL.pathExtension,
            sparklePublicKey: sparklePublicKey,
            hasUpdater: updater != nil
        )
    }

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private var sparklePublicKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("common.ok"))
        alert.runModal()
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
