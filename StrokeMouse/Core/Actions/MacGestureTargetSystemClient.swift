import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MacGestureTargetSystemClient: GestureTargetSystemClient {
    func validateWindow(_ target: GestureTargetContext) throws {
        _ = try validateApplication(target)
        let window = target.window.element
        var actualPID: pid_t = 0
        let pidResult = AXUIElementGetPid(window, &actualPID)
        guard pidResult == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: .validateWindow,
                code: pidResult
            )
        }
        guard actualPID == target.processIdentifier else {
            throw GestureTargetError.processMismatch(
                expected: target.processIdentifier,
                actual: actualPID
            )
        }
        let role = try copyString(
            from: window,
            attribute: kAXRoleAttribute as CFString,
            operation: .validateWindow
        )
        guard role == kAXWindowRole as String else {
            throw GestureTargetError.windowRoleMismatch
        }
    }

    func pressWindowControl(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) throws -> Bool {
        let attribute = try controlAttribute(for: command)
        let control: AXUIElement
        do {
            control = try copyElement(
                from: target.window.element,
                attribute: attribute,
                operation: .copyWindowControl
            )
        } catch GestureTargetError.axOperationFailed(_, let code)
            where code == .noValue || code == .attributeUnsupported
        {
            if command == .fullscreen { return false }
            throw GestureTargetError.windowControlUnavailable(command)
        }

        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: .pressWindowControl,
                code: result
            )
        }
        return true
    }

    func hideApplication(_ target: GestureTargetContext) throws {
        let application = try validateApplication(target)
        guard application.hide() else {
            throw GestureTargetError.applicationHideFailed(target.processIdentifier)
        }
    }

    func centerWindow(_ target: GestureTargetContext) throws {
        let origin = try copyPoint(
            from: target.window.element,
            attribute: kAXPositionAttribute as CFString,
            operation: .copyPosition
        )
        let size = try copySize(
            from: target.window.element,
            attribute: kAXSizeAttribute as CFString,
            operation: .copySize
        )
        let screens = NSScreen.screens
        guard let zeroScreen = screens.first else {
            throw GestureTargetError.noScreens
        }
        let zeroTop = zeroScreen.frame.maxY
        let appKitFrame = CGRect(
            x: origin.x,
            y: zeroTop - origin.y - size.height,
            width: size.width,
            height: size.height
        )
        let screen = targetScreen(for: appKitFrame, screens: screens)
        let visible = screen.visibleFrame
        let newAppKitOrigin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        var newAXOrigin = CGPoint(
            x: newAppKitOrigin.x,
            y: zeroTop - newAppKitOrigin.y - size.height
        )
        guard let value = AXValueCreate(.cgPoint, &newAXOrigin) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        let result = AXUIElementSetAttributeValue(
            target.window.element,
            kAXPositionAttribute as CFString,
            value
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .setPosition, code: result)
        }
    }

    func setMainWindow(_ target: GestureTargetContext) throws {
        let result = AXUIElementSetAttributeValue(
            target.window.element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .setMainWindow, code: result)
        }
    }

    func raiseWindow(_ target: GestureTargetContext) throws {
        let result = AXUIElementPerformAction(
            target.window.element,
            kAXRaiseAction as CFString
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .raiseWindow, code: result)
        }
    }

    func activateApplication(_ target: GestureTargetContext) -> Bool {
        target.application?.activate(options: []) ?? false
    }

    func isApplicationActive(_ target: GestureTargetContext) throws -> Bool {
        try validateApplication(target).isActive
    }

    func verifyFocusedWindow(_ target: GestureTargetContext) throws {
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let focused = try copyElement(
            from: appElement,
            attribute: kAXFocusedWindowAttribute as CFString,
            operation: .copyFocusedWindowForVerification
        )
        guard CFEqual(focused, target.window.element) else {
            throw GestureTargetError.focusedWindowMismatch(target.processIdentifier)
        }
    }

    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target _: GestureTargetContext
    ) throws {
        try ShortcutAction.post(keyCode: keyCode, modifiers: modifiers)
    }

    private func validateApplication(
        _ target: GestureTargetContext
    ) throws -> NSRunningApplication {
        guard let application = target.application else {
            throw GestureTargetError.applicationUnavailable(target.processIdentifier)
        }
        guard !application.isTerminated else {
            throw GestureTargetError.applicationTerminated(target.processIdentifier)
        }
        guard application.processIdentifier == target.processIdentifier else {
            throw GestureTargetError.processMismatch(
                expected: target.processIdentifier,
                actual: application.processIdentifier
            )
        }
        return application
    }

    private func controlAttribute(for command: WindowCommand) throws -> CFString {
        switch command {
        case .close:
            return kAXCloseButtonAttribute as CFString
        case .minimize:
            return kAXMinimizeButtonAttribute as CFString
        case .zoom:
            return kAXZoomButtonAttribute as CFString
        case .fullscreen:
            return kAXFullScreenButtonAttribute as CFString
        case .hide, .center:
            throw GestureTargetError.windowControlUnavailable(command)
        }
    }

    private func copyElement(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> AXUIElement {
        let value = try copyValue(from: element, attribute: attribute, operation: operation)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return value as! AXUIElement
    }

    private func copyString(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> String {
        let value = try copyValue(from: element, attribute: attribute, operation: operation)
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return value as! String
    }

    private func copyPoint(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> CGPoint {
        let axValue = try copyAXValue(
            from: element,
            attribute: attribute,
            expectedType: .cgPoint,
            operation: operation
        )
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return point
    }

    private func copySize(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> CGSize {
        let axValue = try copyAXValue(
            from: element,
            attribute: attribute,
            expectedType: .cgSize,
            operation: operation
        )
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return size
    }

    private func copyAXValue(
        from element: AXUIElement,
        attribute: CFString,
        expectedType: AXValueType,
        operation: GestureTargetAXOperation
    ) throws -> AXValue {
        let value = try copyValue(from: element, attribute: attribute, operation: operation)
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == expectedType else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return axValue
    }

    private func copyValue(
        from element: AXUIElement,
        attribute: CFString,
        operation: GestureTargetAXOperation
    ) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: operation, code: result)
        }
        guard let value else {
            throw GestureTargetError.unexpectedAXValue(operation: operation)
        }
        return value
    }

    private func targetScreen(
        for windowFrame: CGRect,
        screens: [NSScreen]
    ) -> NSScreen {
        let byArea = screens.map { screen in
            let intersection = windowFrame.intersection(screen.frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen, area)
        }
        if let overlapping = byArea.max(by: { $0.1 < $1.1 }), overlapping.1 > 0 {
            return overlapping.0
        }
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.min { lhs, rhs in
            squaredDistance(center, to: lhs.frame) < squaredDistance(center, to: rhs.frame)
        } ?? screens[0]
    }

    private func squaredDistance(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        return dx * dx + dy * dy
    }
}
