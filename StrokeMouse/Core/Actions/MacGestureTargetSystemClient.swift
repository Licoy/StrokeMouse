import AppKit
import ApplicationServices
import Foundation

@MainActor
final class MacGestureTargetSystemClient: GestureTargetSystemClient {
    // Kept for this executor's lifetime; AX identity avoids confusing windows with the same title.
    var maximizingWindows: [AXUIElement] = []
    var previousFrames: [(window: AXUIElement, frame: CGRect)] = []
    var acceptedLayoutSizes: [(window: AXUIElement, requested: CGSize, accepted: CGSize)] = []

    func validateWindow(_ target: GestureTargetContext) throws {
        _ = try validateApplication(target)
        let window = try target.requireWindow().element
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
        let role = try GestureTargetAXAccessor.copyString(
            from: window,
            attribute: GestureTargetAXAttribute(
                name: kAXRoleAttribute as CFString,
                operation: .validateWindow
            )
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
        let window = try target.requireWindow().element
        let control: AXUIElement
        do {
            control = try GestureTargetAXAccessor.copyElement(
                from: window,
                attribute: GestureTargetAXAttribute(
                    name: attribute,
                    operation: .copyWindowControl
                )
            )
        } catch GestureTargetError.axOperationFailed(_, let code)
            where code == .noValue || code == .attributeUnsupported
        {
            return false
        }

        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        if result == .actionUnsupported { return false }
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: .pressWindowControl,
                code: result
            )
        }
        return true
    }

    func setWindowMinimized(_ target: GestureTargetContext) throws {
        let window = try target.requireWindow().element
        let attribute = kAXMinimizedAttribute as CFString
        var writable = DarwinBoolean(false)
        let check = AXUIElementIsAttributeSettable(window, attribute, &writable)
        if check == .attributeUnsupported || check == .noValue || (check == .success && !writable.boolValue) {
            throw GestureTargetError.windowControlUnavailable(.minimize)
        }
        guard check == .success else {
            throw GestureTargetError.axOperationFailed(operation: .checkMinimizedWritable, code: check)
        }

        let result = AXUIElementSetAttributeValue(window, attribute, kCFBooleanTrue)
        if result == .attributeUnsupported {
            throw GestureTargetError.windowControlUnavailable(.minimize)
        }
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .setMinimized, code: result)
        }
    }

    func hideApplication(_ target: GestureTargetContext) throws {
        let application = try validateApplication(target)
        guard application.hide() else {
            throw GestureTargetError.applicationHideFailed(target.processIdentifier)
        }
    }

    func centerWindow(_ target: GestureTargetContext) throws {
        let window = try target.requireWindow().element
        let origin = try GestureTargetAXAccessor.copyPoint(
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
        let screens = NSScreen.screens
        guard let zeroScreen = screens.first else {
            throw GestureTargetError.noScreens
        }
        let appKitFrame = GestureTargetScreenGeometry.appKitWindowFrame(
            axOrigin: origin,
            windowSize: size,
            zeroScreenFrame: zeroScreen.frame
        )
        guard let screenIndex = GestureTargetScreenGeometry.targetScreenIndex(
            for: appKitFrame,
            screenFrames: screens.map(\.frame)
        ) else {
            throw GestureTargetError.noScreens
        }
        var newAXOrigin = GestureTargetScreenGeometry.centeredAXOrigin(
            windowSize: size,
            visibleFrame: screens[screenIndex].visibleFrame,
            zeroScreenFrame: zeroScreen.frame
        )
        guard let value = AXValueCreate(.cgPoint, &newAXOrigin) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        let previous = CGRect(origin: origin, size: size)
        guard !WindowMaximizer.framesMatch(previous, CGRect(origin: newAXOrigin, size: size)) else { return }
        rememberFrame(window, frame: previous)
        let result = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            value
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .setPosition, code: result)
        }
    }

    func setMainWindow(_ target: GestureTargetContext) throws {
        let window = try target.requireWindow().element
        let result = AXUIElementSetAttributeValue(
            window,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .setMainWindow, code: result)
        }
    }

    func raiseWindow(_ target: GestureTargetContext) throws {
        let window = try target.requireWindow().element
        let result = AXUIElementPerformAction(
            window,
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

    func isWindowFocused(_ target: GestureTargetContext) throws -> Bool {
        let window = try target.requireWindow().element
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let focused = try GestureTargetAXAccessor.copyElement(
            from: appElement,
            attribute: GestureTargetAXAttribute(
                name: kAXFocusedWindowAttribute as CFString,
                operation: .copyFocusedWindowForVerification
            )
        )
        return CFEqual(focused, window)
    }

    func verifyFocusedWindow(_ target: GestureTargetContext) throws {
        guard try isWindowFocused(target) else {
            throw GestureTargetError.focusedWindowMismatch(target.processIdentifier)
        }
    }

    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target _: GestureTargetContext
    ) throws {
        try ShortcutAction.post(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord
        )
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
        default:
            throw GestureTargetError.windowControlUnavailable(command)
        }
    }
}
