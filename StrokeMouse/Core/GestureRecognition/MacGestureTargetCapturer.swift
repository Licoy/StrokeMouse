import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MacGestureTargetCapturer: GestureTargetCapturing {
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
                return .resolved(try captureFrontmostWindow())
            case .windowUnderPointer:
                return .resolved(try captureWindowUnderPointer(at: quartzLocation))
            }
        } catch let error as GestureTargetError {
            return .unavailable(error)
        } catch {
            return .unavailable(.unexpectedCaptureFailure(String(describing: error)))
        }
    }

    private func captureFrontmostWindow() throws -> GestureTargetContext {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw GestureTargetError.noFrontmostApplication
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let window = try copyElement(
            from: appElement,
            attribute: kAXFocusedWindowAttribute as CFString,
            operation: .copyFocusedWindow
        )
        try validatePID(of: window, expected: application.processIdentifier)
        return makeContext(
            policy: .frontmostWindow,
            application: application,
            window: window
        )
    }

    private func captureWindowUnderPointer(at location: CGPoint) throws -> GestureTargetContext {
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(location.x),
            Float(location.y),
            &hit
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .hitTest, code: result)
        }
        guard let hit else { throw GestureTargetError.noElementAtPointer }

        let window = try containingWindow(of: hit)
        let processIdentifier = try pid(of: window, operation: .getProcessIdentifier)
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            throw GestureTargetError.applicationUnavailable(processIdentifier)
        }
        return makeContext(
            policy: .windowUnderPointer,
            application: application,
            window: window
        )
    }

    private func makeContext(
        policy: GestureTargetPolicy,
        application: NSRunningApplication,
        window: AXUIElement
    ) -> GestureTargetContext {
        GestureTargetContext(
            policy: policy,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            application: application,
            window: GestureWindowTarget(element: window)
        )
    }

    private func containingWindow(of hit: AXUIElement) throws -> AXUIElement {
        do {
            return try copyElement(
                from: hit,
                attribute: kAXWindowAttribute as CFString,
                operation: .copyContainingWindow
            )
        } catch GestureTargetError.axOperationFailed(_, let code)
            where code == .noValue || code == .attributeUnsupported
        {
            let role = try copyString(
                from: hit,
                attribute: kAXRoleAttribute as CFString,
                operation: .copyRole
            )
            guard role == kAXWindowRole as String else {
                throw GestureTargetError.windowUnavailable
            }
            return hit
        }
    }

    private func copyElement(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> AXUIElement {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: operation, code: result)
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return value as! AXUIElement
    }

    private func copyString(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: operation, code: result)
        }
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return value as! String
    }

    private func validatePID(of window: AXUIElement, expected: pid_t) throws {
        let actual = try pid(of: window, operation: .getProcessIdentifier)
        guard actual == expected else {
            throw GestureTargetError.processMismatch(expected: expected, actual: actual)
        }
    }

    private func pid(
        of element: AXUIElement,
        operation: GestureTargetAXOperation
    ) throws -> pid_t {
        var processIdentifier: pid_t = 0
        let result = AXUIElementGetPid(element, &processIdentifier)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: operation, code: result)
        }
        return processIdentifier
    }
}
