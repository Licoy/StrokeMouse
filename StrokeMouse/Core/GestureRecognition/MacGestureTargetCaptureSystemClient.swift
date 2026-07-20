import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol GestureTargetCaptureSystemClient: AnyObject {
    var frontmostApplication: NSRunningApplication? { get }

    func runningApplication(processIdentifier: pid_t) -> NSRunningApplication?
    func element(at quartzLocation: CGPoint) throws -> AXUIElement
    func copyElement(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> AXUIElement
    func copyString(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> String
    func processIdentifier(
        of element: AXUIElement,
        operation: GestureTargetAXOperation
    ) throws -> pid_t
}

@MainActor
final class MacGestureTargetCaptureSystemClient: GestureTargetCaptureSystemClient {
    var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    func runningApplication(processIdentifier: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }

    func element(at quartzLocation: CGPoint) throws -> AXUIElement {
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(quartzLocation.x),
            Float(quartzLocation.y),
            &hit
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .hitTest, code: result)
        }
        guard let hit else { throw GestureTargetError.noElementAtPointer }
        return hit
    }

    func copyElement(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> AXUIElement {
        try GestureTargetAXAccessor.copyElement(from: element, attribute: attribute)
    }

    func copyString(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> String {
        try GestureTargetAXAccessor.copyString(from: element, attribute: attribute)
    }

    func processIdentifier(
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
