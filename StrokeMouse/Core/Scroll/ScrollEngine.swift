import AppKit
import Foundation
import Observation

enum ScrollEngineFailure: Equatable, Sendable {
    case accessibilityRequired
    case eventTapCreationFailed
}

enum ScrollEngineStatus: Equatable, Sendable {
    case paused
    case notNeeded
    case listening
    case failed(ScrollEngineFailure)

    var messageKey: String {
        switch self {
        case .paused: return "scroll.status.paused"
        case .notNeeded: return "scroll.status.notNeeded"
        case .listening: return "scroll.status.listening"
        case .failed(.accessibilityRequired):
            return "scroll.status.needPermission"
        case .failed(.eventTapCreationFailed):
            return "scroll.status.tapFailed"
        }
    }
}

@MainActor
@Observable
final class ScrollEngine {
    private(set) var configuration: ScrollEnhancementConfiguration
    private(set) var status: ScrollEngineStatus = .notNeeded

    private let permissionManager: any GesturePermissionProviding
    private let eventSource: any ScrollEventSource
    private let driver: any SmoothScrollDriving
    private let frontmostBundleIdentifierProvider: () -> String?
    private var frontmostBundleIdentifier: String?
    private var frontmostExcluded = false
    private var lastWantedTap = false
    private var creationLatched = false
    private var accessibilityTrusted: Bool
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        permissionManager: any GesturePermissionProviding,
        eventSource: any ScrollEventSource = ScrollEventTap(),
        driver: any SmoothScrollDriving = SmoothScrollDriver(
            poster: CGScrollEventPoster()
        ),
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        installsWorkspaceObservers: Bool = true
    ) {
        self.permissionManager = permissionManager
        self.eventSource = eventSource
        self.driver = driver
        self.frontmostBundleIdentifierProvider = frontmostBundleIdentifier
        configuration = .dormant
        accessibilityTrusted = permissionManager.isAccessibilityTrusted
        // The impulse path stays off the main thread. Nothing starts here:
        // unit-test hosts construct several AppState values during init.
        eventSource.onImpulse = { [weak driver] impulse in
            driver?.submit(impulse)
        }
        eventSource.onAnimationCancelRequested = { [weak driver] in
            driver?.cancel()
        }
        publishSnapshot()
        if installsWorkspaceObservers {
            installWorkspaceObservers()
        }
    }

    func apply(_ configuration: ScrollEnhancementConfiguration) {
        accessibilityTrusted = permissionManager.isAccessibilityTrusted
        let normalized = configuration.normalized()
        let wanted = normalized.requiresEventTap
        if wanted != lastWantedTap {
            creationLatched = false
            lastWantedTap = wanted
        }
        self.configuration = normalized
        frontmostApplicationDidChange(frontmostBundleIdentifierProvider())
        reconcile()
    }

    func accessibilityTrustDidChange(_ isTrusted: Bool) {
        accessibilityTrusted = isTrusted
        creationLatched = false
        if !isTrusted {
            stopTapIfNeeded(cancelAnimation: true)
        }
        reconcile()
    }

    func retry() {
        accessibilityTrusted = permissionManager.isAccessibilityTrusted
        creationLatched = false
        stopTapIfNeeded(cancelAnimation: true)
        reconcile()
    }

    func frontmostApplicationDidChange(_ bundleIdentifier: String?) {
        frontmostBundleIdentifier = bundleIdentifier
        frontmostExcluded = bundleIdentifier.map {
            configuration.excludedBundleIds.contains($0)
        } ?? false
        publishSnapshot()
    }

    func handleSleep() {
        driver.cancel()
    }

    func handleWake() {
        accessibilityTrusted = permissionManager.isAccessibilityTrusted
        guard configuration.requiresEventTap, accessibilityTrusted else { return }
        if eventSource.isActive, eventSource.reassertEnabled() {
            return
        }
        stopTapIfNeeded(cancelAnimation: true)
        creationLatched = false
        reconcile()
    }

    deinit {
        MainActor.assumeIsolated {
            let center = NSWorkspace.shared.notificationCenter
            for observer in workspaceObservers {
                center.removeObserver(observer)
            }
            eventSource.onImpulse = nil
            eventSource.onAnimationCancelRequested = nil
            eventSource.stop()
            driver.cancel()
        }
    }

    private func reconcile() {
        guard configuration.requiresEventTap else {
            stopTapIfNeeded(cancelAnimation: true)
            status = configuration.isEnabled ? .notNeeded : .paused
            return
        }
        guard accessibilityTrusted else {
            stopTapIfNeeded(cancelAnimation: true)
            status = .failed(.accessibilityRequired)
            return
        }
        if eventSource.isActive {
            status = .listening
            return
        }
        if creationLatched {
            status = .failed(.eventTapCreationFailed)
            return
        }
        switch eventSource.start() {
        case .success:
            status = .listening
        case .failure(.accessibilityRequired):
            status = .failed(.accessibilityRequired)
        case .failure(.eventTapCreationFailed):
            creationLatched = true
            status = .failed(.eventTapCreationFailed)
        }
    }

    private func stopTapIfNeeded(cancelAnimation: Bool) {
        if eventSource.isActive {
            eventSource.stop()
        }
        if cancelAnimation {
            driver.cancel()
        }
    }

    private func publishSnapshot() {
        eventSource.snapshot = ScrollTapSnapshot(
            configuration: configuration,
            frontmostExcluded: frontmostExcluded
        )
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let bundleId = (
                    note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                )?.bundleIdentifier
                MainActor.assumeIsolated {
                    self?.frontmostApplicationDidChange(bundleId)
                }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleWake() }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSleep() }
            }
        )
    }
}
