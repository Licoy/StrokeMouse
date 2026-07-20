import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MacGestureTargetCapturer: GestureTargetCapturing {
    private let system: any GestureTargetCaptureSystemClient

    init(system: (any GestureTargetCaptureSystemClient)? = nil) {
        self.system = system ?? MacGestureTargetCaptureSystemClient()
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        GestureTargetSnapshot(
            frontmostWindow: resolution(
                for: .frontmostWindow,
                whenRequestedBy: policies,
                at: quartzLocation
            ),
            windowUnderPointer: resolution(
                for: .windowUnderPointer,
                whenRequestedBy: policies,
                at: quartzLocation
            )
        )
    }

    private func resolution(
        for policy: GestureTargetPolicy,
        whenRequestedBy policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetResolution {
        guard policies.contains(policy) else {
            return .unavailable(.targetNotCaptured(policy))
        }
        do {
            switch policy {
            case .frontmostWindow:
                return .resolved(try captureFrontmostTarget())
            case .windowUnderPointer:
                return .resolved(try captureTargetUnderPointer(at: quartzLocation))
            }
        } catch let error as GestureTargetError {
            return .unavailable(error)
        } catch {
            return .unavailable(.unexpectedCaptureFailure(String(describing: error)))
        }
    }

    private func captureFrontmostTarget() throws -> GestureTargetContext {
        guard let application = system.frontmostApplication else {
            throw GestureTargetError.noFrontmostApplication
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let window = try optionalFrontmostWindow(
            of: appElement,
            expectedProcessIdentifier: application.processIdentifier
        )
        return makeContext(
            policy: .frontmostWindow,
            application: application,
            window: window
        )
    }

    private func captureTargetUnderPointer(at location: CGPoint) throws -> GestureTargetContext {
        let hit = try system.element(at: location)
        let processIdentifier = try system.processIdentifier(
            of: hit,
            operation: .getProcessIdentifier
        )
        guard let application = system.runningApplication(processIdentifier: processIdentifier) else {
            throw GestureTargetError.applicationUnavailable(processIdentifier)
        }
        let window = try optionalContainingWindow(
            of: hit,
            expectedProcessIdentifier: processIdentifier
        )
        return makeContext(
            policy: .windowUnderPointer,
            application: application,
            window: window
        )
    }

    private func makeContext(
        policy: GestureTargetPolicy,
        application: NSRunningApplication,
        window: AXUIElement?
    ) -> GestureTargetContext {
        GestureTargetContext(
            policy: policy,
            identity: GestureTargetIdentity(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier
            ),
            application: application,
            window: window.map(GestureWindowTarget.init)
        )
    }

    private func optionalFrontmostWindow(
        of application: AXUIElement,
        expectedProcessIdentifier: pid_t
    ) throws -> AXUIElement? {
        do {
            let window = try system.copyElement(
                from: application,
                attribute: GestureTargetAXAttribute(
                    name: kAXFocusedWindowAttribute as CFString,
                    operation: .copyFocusedWindow
                )
            )
            try validatePID(of: window, expected: expectedProcessIdentifier)
            return try windowIfOperable(window)
        } catch GestureTargetError.axOperationFailed(let operation, let code)
            where operation == .copyFocusedWindow
                && (code == .noValue || code == .attributeUnsupported)
        {
            return nil
        }
    }

    private func optionalContainingWindow(
        of hit: AXUIElement,
        expectedProcessIdentifier: pid_t
    ) throws -> AXUIElement? {
        do {
            let window = try system.copyElement(
                from: hit,
                attribute: GestureTargetAXAttribute(
                    name: kAXWindowAttribute as CFString,
                    operation: .copyContainingWindow
                )
            )
            try validatePID(of: window, expected: expectedProcessIdentifier)
            return try windowIfOperable(window)
        } catch GestureTargetError.axOperationFailed(let operation, let code)
            where operation == .copyContainingWindow
                && (code == .noValue || code == .attributeUnsupported)
        {
            return try windowIfOperable(hit)
        }
    }

    private func windowIfOperable(_ element: AXUIElement) throws -> AXUIElement? {
        do {
            try validateWindowRole(element)
            return element
        } catch GestureTargetError.windowRoleMismatch {
            return nil
        }
    }

    private func validateWindowRole(_ window: AXUIElement) throws {
        let role = try system.copyString(
            from: window,
            attribute: GestureTargetAXAttribute(
                name: kAXRoleAttribute as CFString,
                operation: .copyRole
            )
        )
        guard role == kAXWindowRole as String else {
            throw GestureTargetError.windowRoleMismatch
        }
    }

    private func validatePID(of window: AXUIElement, expected: pid_t) throws {
        let actual = try system.processIdentifier(
            of: window,
            operation: .getProcessIdentifier
        )
        guard actual == expected else {
            throw GestureTargetError.processMismatch(expected: expected, actual: actual)
        }
    }
}
