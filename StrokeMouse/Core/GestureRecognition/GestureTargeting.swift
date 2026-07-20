import AppKit
import ApplicationServices
import Foundation

struct GestureTargetIdentity: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

final class GestureWindowTarget {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }
}

struct GestureTargetContext {
    let policy: GestureTargetPolicy
    let identity: GestureTargetIdentity
    /// Production captures and retains this object so PID reuse cannot retarget an action.
    let application: NSRunningApplication?
    let window: GestureWindowTarget?

    var processIdentifier: pid_t { identity.processIdentifier }
    var bundleIdentifier: String? { identity.bundleIdentifier }

    func requireWindow() throws -> GestureWindowTarget {
        guard let window else {
            throw GestureTargetError.targetHasNoOperableWindow
        }
        return window
    }
}

enum GestureTargetAXOperation: String, Equatable, Sendable {
    case hitTest
    case copyContainingWindow
    case copyFocusedWindow
    case copyRole
    case getProcessIdentifier
    case validateWindow
    case copyWindowControl
    case pressWindowControl
    case setMainWindow
    case raiseWindow
    case copyPosition
    case copySize
    case setPosition
    case copyFocusedWindowForVerification
}

enum GestureTargetError: LocalizedError {
    case noFrontmostApplication
    case noElementAtPointer
    case targetNotCaptured(GestureTargetPolicy)
    case applicationUnavailable(pid_t)
    case applicationTerminated(pid_t)
    case windowUnavailable
    case targetHasNoOperableWindow
    case axOperationFailed(operation: GestureTargetAXOperation, code: AXError)
    case unexpectedAXValue(operation: GestureTargetAXOperation)
    case processMismatch(expected: pid_t, actual: pid_t)
    case windowRoleMismatch
    case windowControlUnavailable(WindowCommand)
    case applicationHideFailed(pid_t)
    case activationFailed(pid_t)
    case activationTimedOut(pid_t)
    case focusedWindowMismatch(pid_t)
    case noScreens
    case unexpectedCaptureFailure(String)

    var errorDescription: String? {
        switch self {
        case .noFrontmostApplication, .noElementAtPointer, .targetNotCaptured,
             .applicationUnavailable, .applicationTerminated, .windowUnavailable:
            return L10n.string("action.targetUnavailable")
        case .targetHasNoOperableWindow:
            return L10n.string("action.targetHasNoOperableWindow")
        case .activationFailed:
            return L10n.string("action.targetActivationFailed")
        case .activationTimedOut:
            return L10n.string("action.targetActivationTimedOut")
        case .focusedWindowMismatch:
            return L10n.string("action.targetFocusChanged")
        case .windowControlUnavailable:
            return L10n.string("action.targetWindowControlUnavailable")
        case .axOperationFailed, .unexpectedAXValue, .processMismatch,
             .windowRoleMismatch, .applicationHideFailed, .noScreens,
             .unexpectedCaptureFailure:
            return L10n.string("action.targetOperationFailed")
        }
    }
}

enum GestureTargetResolution {
    case resolved(GestureTargetContext)
    case unavailable(GestureTargetError)

    var context: GestureTargetContext? {
        guard case .resolved(let context) = self else { return nil }
        return context
    }

    var bundleIdentifier: String? { context?.bundleIdentifier }
    var processIdentifier: pid_t? { context?.processIdentifier }

    func requireContext() throws -> GestureTargetContext {
        switch self {
        case .resolved(let context):
            return context
        case .unavailable(let error):
            throw error
        }
    }
}

struct GestureTargetSnapshot {
    let frontmostWindow: GestureTargetResolution
    let windowUnderPointer: GestureTargetResolution

    func resolution(for policy: GestureTargetPolicy) -> GestureTargetResolution {
        switch policy {
        case .frontmostWindow:
            return frontmostWindow
        case .windowUnderPointer:
            return windowUnderPointer
        }
    }
}

struct TargetedGesture {
    let profile: GestureProfile
    let target: GestureTargetResolution
}

enum GestureCandidateSelector {
    static func prepare(
        profiles: [GestureProfile],
        snapshot: GestureTargetSnapshot
    ) -> [TargetedGesture] {
        profiles.compactMap { profile in
            let target = snapshot.resolution(for: profile.targetPolicy)
            switch profile.scope {
            case .global:
                return TargetedGesture(profile: profile, target: target)
            case .apps(let bundleIdentifiers):
                guard let bundleIdentifier = target.bundleIdentifier,
                      bundleIdentifiers.contains(bundleIdentifier)
                else { return nil }
                return TargetedGesture(profile: profile, target: target)
            }
        }
    }
}

@MainActor
protocol GestureTargetCapturing: AnyObject {
    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot
}

@MainActor
final class GestureStrokeTargetSession {
    private let capturer: any GestureTargetCapturing
    private var snapshot: GestureTargetSnapshot?

    init(capturer: any GestureTargetCapturing) {
        self.capturer = capturer
    }

    func handleButtonDown(profiles: [GestureProfile], at quartzLocation: CGPoint) {
        let policies = Set(profiles.map(\.targetPolicy))
        snapshot = capturer.capture(policies: policies, at: quartzLocation)
    }

    func takeAtButtonUp() -> GestureTargetSnapshot? {
        defer { snapshot = nil }
        return snapshot
    }

    func cancel() {
        snapshot = nil
    }
}
