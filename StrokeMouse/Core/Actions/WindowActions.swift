import AppKit
import ApplicationServices
import Foundation

enum WindowActions {
    static func perform(_ command: WindowCommand) throws {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        switch command {
        case .hide:
            app.hide()
            return
        case .close, .minimize, .zoom, .fullscreen, .center:
            break
        }

        guard let window = focusedWindow(of: appElement) else { return }

        switch command {
        case .close:
            pressButton(window, attribute: kAXCloseButtonAttribute as CFString)
        case .minimize:
            pressButton(window, attribute: kAXMinimizeButtonAttribute as CFString)
        case .zoom:
            pressButton(window, attribute: kAXZoomButtonAttribute as CFString)
        case .fullscreen:
            // Toggle fullscreen via green button menu is unreliable; use zoom as best-effort.
            pressButton(window, attribute: kAXFullScreenButtonAttribute as CFString)
            // Fallback: standard macOS shortcut Control+Command+F
            if !buttonExists(window, attribute: kAXFullScreenButtonAttribute as CFString) {
                try ShortcutAction.post(
                    keyCode: 3, // F
                    modifiers: UInt(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.command.rawValue)
                )
            }
        case .center:
            center(window)
        case .hide:
            break
        }
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref)
        guard result == .success, let ref else { return nil }
        return (ref as! AXUIElement)
    }

    private static func pressButton(_ window: AXUIElement, attribute: CFString) {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &ref) == .success,
              let ref
        else { return }
        let button = ref as! AXUIElement
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    private static func buttonExists(_ window: AXUIElement, attribute: CFString) -> Bool {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, attribute, &ref) == .success
    }

    private static func center(_ window: AXUIElement) {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var newOrigin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )

        // AX uses top-left global coordinates with flipped Y relative to AppKit in some contexts;
        // convert AppKit bottom-left to AX.
        let axY = screen.frame.maxY - newOrigin.y - size.height
        newOrigin = CGPoint(x: newOrigin.x, y: axY)

        if let posValue = AXValueCreate(.cgPoint, &newOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
}
