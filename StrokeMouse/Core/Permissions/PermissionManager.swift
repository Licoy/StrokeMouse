import ApplicationServices
import AppKit
import Foundation
import Observation
import PermissionFlow

@MainActor
@Observable
final class PermissionManager {
    private(set) var isAccessibilityTrusted = false
    /// Fired when accessibility trust flips from false → true (e.g. user enabled it in System Settings).
    var onBecameTrusted: (() -> Void)?
    /// Fired whenever accessibility trust changes (true→false or false→true).
    var onTrustChanged: ((Bool) -> Void)?
    /// True while the guided authorize UI / System Settings handoff is active.
    private(set) var isAuthorizationFlowActive = false

    /// Shared controller for System Settings deeplink + floating drag-to-authorize panel.
    private let permissionFlow: PermissionFlowController
    nonisolated(unsafe) private var timer: Timer?

    init() {
        permissionFlow = PermissionFlow.makeController(
            configuration: .init(
                requiredAppURLs: [Bundle.main.bundleURL],
                promptForAccessibilityTrust: false
            )
        )
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        // Slightly relax timer coalescing so authorize animations aren't fighting polls.
        timer?.tolerance = 0.4
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        applyTrust(AXIsProcessTrusted())
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        applyTrust(AXIsProcessTrustedWithOptions(options))
    }

    /// Opens Privacy → Accessibility and shows PermissionFlow's drag-to-authorize panel.
    /// - Parameter sourceFrameInScreen: Optional click origin for the fly-in animation.
    func authorizeAccessibility(sourceFrameInScreen: CGRect? = nil) {
        isAuthorizationFlowActive = true

        // Keep the click-to-authorize path free of extra AX work and state churn.
        // TCC registration (without prompt) is deferred so it doesn't compete with
        // System Settings launch + panel animation on the same main-thread turn.
        let frame = sourceFrameInScreen ?? Self.defaultSourceFrame()
        permissionFlow.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: frame
        )

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isAccessibilityTrusted else { return }
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        // Only need to throttle onboarding Canvas during the launch handoff.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isAuthorizationFlowActive = false
        }
    }

    /// Legacy entry: prefer guided authorize flow over a bare settings URL.
    func openAccessibilitySettings() {
        authorizeAccessibility()
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    func closeAuthorizationPanel() {
        permissionFlow.closePanel()
        isAuthorizationFlowActive = false
    }

    private func applyTrust(_ trusted: Bool) {
        let wasTrusted = isAccessibilityTrusted
        guard trusted != wasTrusted else { return }
        isAccessibilityTrusted = trusted
        onTrustChanged?(trusted)
        if trusted {
            isAuthorizationFlowActive = false
            permissionFlow.closePanel(returnToPreviousApp: true)
            onBecameTrusted?()
        }
    }

    private static func defaultSourceFrame() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
    }
}
