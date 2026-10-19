import AppKit
import ApplicationServices
import Foundation
import OSLog

protocol GestureTargetCaptureSystemClient: AnyObject, Sendable {
    var frontmostApplication: NSRunningApplication? { get }

    func runningApplication(processIdentifier: pid_t) -> NSRunningApplication?
    func element(at quartzLocation: CGPoint) throws -> AXUIElement
    func windowUnderPointer(at quartzLocation: CGPoint) throws -> GestureTargetWindowDescriptor
    func validateWindow(_ descriptor: GestureTargetWindowDescriptor) throws
    func windows(processIdentifier: pid_t) throws -> [AXUIElement]
    func frame(of window: AXUIElement) throws -> CGRect
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

final class MacGestureTargetCaptureSystemClient:
    GestureTargetCaptureSystemClient,
    @unchecked Sendable
{
    private static let logger = Logger(
        subsystem: Constants.bundleID,
        category: "GestureTargetCapture"
    )

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

    func windowUnderPointer(at quartzLocation: CGPoint) throws -> GestureTargetWindowDescriptor {
        let windows = try visibleWindows(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            relativeTo: kCGNullWindowID
        )
        return try GestureTargetWindowLocator.locate(
            at: quartzLocation,
            windows: windows,
            displayBounds: try activeDisplayBounds(),
            dockWindowLevel: Int(CGWindowLevelForKey(.dockWindow))
        ) { [self] window in
            try dockCarrierDoesNotHit(window, at: quartzLocation)
        }
    }

    func validateWindow(_ descriptor: GestureTargetWindowDescriptor) throws {
        let windows = try visibleWindows(
            options: .optionIncludingWindow,
            relativeTo: descriptor.windowNumber
        )
        guard windows.count == 1, windows[0].descriptor == descriptor else {
            throw GestureTargetError.windowUnavailable
        }
    }

    func windows(processIdentifier: pid_t) throws -> [AXUIElement] {
        try GestureTargetAXAccessor.copyElements(
            from: AXUIElementCreateApplication(processIdentifier),
            attribute: GestureTargetAXAttribute(
                name: kAXWindowsAttribute as CFString,
                operation: .copyWindows
            )
        )
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        let position = try GestureTargetAXAccessor.copyPoint(
            from: window,
            attribute: GestureTargetAXAttribute(
                name: kAXPositionAttribute as CFString,
                operation: .copyPosition
            )
        )
        let size = try GestureTargetAXAccessor.copySize(
            from: window,
            attribute: GestureTargetAXAttribute(
                name: kAXSizeAttribute as CFString,
                operation: .copySize
            )
        )
        return CGRect(origin: position, size: size)
    }

    private func visibleWindows(
        options: CGWindowListOption,
        relativeTo windowNumber: CGWindowID
    ) throws -> [GestureTargetVisibleWindow] {
        guard let records = CGWindowListCopyWindowInfo(options, windowNumber)
            as? [[String: Any]]
        else { throw GestureTargetError.windowUnavailable }
        return try GestureTargetWindowLocator.parse(records) { processIdentifier in
            runningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
        }
    }

    private func activeDisplayBounds() throws -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            throw GestureTargetError.noScreens
        }
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &identifiers, &count) == .success else {
            throw GestureTargetError.noScreens
        }
        return identifiers.prefix(Int(count)).map(CGDisplayBounds)
    }

    private func dockCarrierDoesNotHit(
        _ window: GestureTargetVisibleWindow,
        at point: CGPoint
    ) throws -> Bool {
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateApplication(window.descriptor.processIdentifier),
            Float(point.x),
            Float(point.y),
            &hit
        )
        if result == .noValue, hit == nil {
            Self.logger.notice(
                "operation=dockHitTest code=\(result.rawValue) result=nonHittingCarrier pid=\(window.descriptor.processIdentifier) window=\(window.descriptor.windowNumber) layer=\(window.descriptor.layer)"
            )
            return true
        }
        if result == .success {
            Self.logger.error(
                "operation=dockHitTest code=\(result.rawValue) result=occluding pid=\(window.descriptor.processIdentifier) window=\(window.descriptor.windowNumber) layer=\(window.descriptor.layer)"
            )
            return false
        }
        Self.logger.error(
            "operation=dockHitTest code=\(result.rawValue) result=failed pid=\(window.descriptor.processIdentifier) window=\(window.descriptor.windowNumber) layer=\(window.descriptor.layer)"
        )
        throw GestureTargetError.axOperationFailed(operation: .hitTest, code: result)
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
