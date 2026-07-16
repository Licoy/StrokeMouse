import AppKit
import Foundation
import Sparkle

@MainActor
final class StrokeMouseSparkleUserDriver: NSObject, SPUUserDriver {
    private let automaticallyChecksForUpdates: Bool
    private let statusWindow = UpdateStatusWindowController()
    private var expectedContentLength: UInt64 = 0
    private var downloadedLength: UInt64 = 0

    /// Called when a user-initiated update check starts or ends (result dialog / cancel / error).
    var onUserInitiatedCheckStateChanged: ((Bool) -> Void)?

    init(automaticallyChecksForUpdates: Bool) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: automaticallyChecksForUpdates,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        onUserInitiatedCheckStateChanged?(true)
        showStatus(
            titleKey: "update.checking",
            progress: nil,
            primaryButton: .init(
                title: L10n.string("common.cancel"),
                action: {
                    cancellation()
                    self.statusWindow.close()
                    self.onUserInitiatedCheckStateChanged?(false)
                }
            )
        )
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        statusWindow.close()
        onUserInitiatedCheckStateChanged?(false)
        if appcastItem.isInformationOnlyUpdate {
            showInformationOnlyUpdate(appcastItem, reply: reply)
            return
        }

        let messageKey = state.stage == .notDownloaded
            ? "update.versionAvailable"
            : "update.downloadedReady"
        let primaryKey = state.stage == .notDownloaded
            ? "update.downloadAndInstall"
            : "update.installAndRelaunch"
        let response = alert(
            titleKey: "update.available",
            message: String(format: L10n.string(messageKey), appcastItem.displayVersionString),
            buttonKeys: [primaryKey, "update.installLater", "update.skipVersion"]
        )
        switch response {
        case .alertFirstButtonReturn:
            reply(.install)
        case .alertSecondButtonReturn:
            reply(.dismiss)
        default:
            reply(.skip)
        }
    }

    func showUpdateReleaseNotes(with _: SPUDownloadData) {
        // Release notes are intentionally disabled by SUShowReleaseNotes.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        statusWindow.close()
        onUserInitiatedCheckStateChanged?(false)
        showError(titleKey: "update.checkFailed", error: error)
    }

    func showUpdateNotFoundWithError(_: Error, acknowledgement: @escaping () -> Void) {
        statusWindow.close()
        onUserInitiatedCheckStateChanged?(false)
        _ = alert(
            titleKey: "update.noUpdate",
            message: L10n.string("update.noUpdateMessage"),
            buttonKeys: ["common.ok"]
        )
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        statusWindow.close()
        onUserInitiatedCheckStateChanged?(false)
        showError(titleKey: "update.checkFailed", error: error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedContentLength = 0
        downloadedLength = 0
        showStatus(
            titleKey: "update.downloading",
            progress: 0,
            primaryButton: .init(
                title: L10n.string("common.cancel"),
                action: {
                    cancellation()
                    self.statusWindow.close()
                }
            )
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        updateDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedLength += length
        updateDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        showStatus(titleKey: "update.extracting", progress: nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        statusWindow.update(progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        var didReply = false
        func finish(_ choice: SPUUserUpdateChoice) {
            guard !didReply else { return }
            didReply = true
            statusWindow.close()
            reply(choice)
        }

        statusWindow.show(
            title: L10n.string("update.readyToInstall"),
            progress: 1,
            buttons: .init(
                primary: .init(
                    title: L10n.string("update.installAndRelaunch"),
                    action: { finish(.install) }
                ),
                secondary: .init(
                    title: L10n.string("update.installLater"),
                    action: { finish(.dismiss) }
                )
            )
        )
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        let retryButton: UpdateStatusWindowController.ButtonConfiguration? = applicationTerminated
            ? nil
            : .init(
                title: L10n.string("update.installAndRelaunch"),
                action: retryTerminatingApplication
            )
        showStatus(titleKey: "update.installing", progress: nil, primaryButton: retryButton)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        statusWindow.close()
        _ = alert(
            titleKey: "update.installed",
            message: L10n.string("update.installedMessage"),
            buttonKeys: ["common.ok"]
        )
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        statusWindow.close()
        onUserInitiatedCheckStateChanged?(false)
    }

    func showUpdateInFocus() {
        statusWindow.focus()
    }

    static func errorMessage(for error: Error, proxyHint: String) -> String {
        let rootError = error as NSError
        let message = rootError.localizedRecoverySuggestion ?? rootError.localizedDescription
        var currentError: NSError? = rootError
        while let checkedError = currentError {
            if checkedError.domain == NSURLErrorDomain {
                return "\(message)\n\n\(proxyHint)"
            }
            currentError = checkedError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return message
    }

    private func showInformationOnlyUpdate(
        _ appcastItem: SUAppcastItem,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let response = alert(
            titleKey: "update.available",
            message: String(
                format: L10n.string("update.versionAvailable"),
                appcastItem.displayVersionString
            ),
            buttonKeys: ["update.learnMore", "update.installLater"]
        )
        if response == .alertFirstButtonReturn, let infoURL = appcastItem.infoURL {
            NSWorkspace.shared.open(infoURL)
        }
        reply(.dismiss)
    }

    private func updateDownloadProgress() {
        guard expectedContentLength > 0 else { return }
        statusWindow.update(progress: Double(downloadedLength) / Double(expectedContentLength))
    }

    private func showStatus(
        titleKey: String,
        progress: Double?,
        primaryButton: UpdateStatusWindowController.ButtonConfiguration? = nil
    ) {
        statusWindow.show(
            title: L10n.string(titleKey),
            progress: progress,
            buttons: .init(primary: primaryButton)
        )
    }

    private func showError(titleKey: String, error: Error) {
        let message = Self.errorMessage(
            for: error,
            proxyHint: L10n.string("update.networkProxyHint")
        )
        _ = alert(titleKey: titleKey, message: message, buttonKeys: ["common.ok"])
    }

    private func alert(
        titleKey: String,
        message: String,
        buttonKeys: [String]
    ) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.string(titleKey)
        alert.informativeText = message
        buttonKeys.forEach { alert.addButton(withTitle: L10n.string($0)) }
        return alert.runModal()
    }
}
