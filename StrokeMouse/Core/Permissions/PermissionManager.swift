import ApplicationServices
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PermissionManager {
    private(set) var isAccessibilityTrusted = false
    /// Fired when accessibility trust flips from false → true (e.g. user enabled it in System Settings).
    var onBecameTrusted: (() -> Void)?
    nonisolated(unsafe) private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let wasTrusted = isAccessibilityTrusted
        isAccessibilityTrusted = AXIsProcessTrusted()
        if isAccessibilityTrusted, !wasTrusted {
            onBecameTrusted?()
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let wasTrusted = isAccessibilityTrusted
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if isAccessibilityTrusted, !wasTrusted {
            onBecameTrusted?()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
