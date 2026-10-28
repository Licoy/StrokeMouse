import AppKit
import ApplicationServices

/// A narrow AX seam keeps the write ordering and result checks testable.
@MainActor
struct WindowFrameAXClient {
    var readFrame: (AXUIElement) throws -> CGRect = { window in
        let origin = try GestureTargetAXAccessor.copyPoint(
            from: window,
            attribute: .init(name: kAXPositionAttribute as CFString, operation: .copyPosition)
        )
        let size = try GestureTargetAXAccessor.copySize(
            from: window,
            attribute: .init(name: kAXSizeAttribute as CFString, operation: .copySize)
        )
        guard origin.x.isFinite, origin.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            throw GestureTargetError.windowResizeUnavailable
        }
        return CGRect(origin: origin, size: size)
    }
    var isSettable: (AXUIElement, CFString) -> (AXError, Bool) = { window, attribute in
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, attribute, &settable)
        return (result, settable.boolValue)
    }
    var setValue: (AXUIElement, CFString, AXValue) -> AXError = {
        AXUIElementSetAttributeValue($0, $1, $2)
    }

    func requireWritable(_ window: AXUIElement, attribute: CFString) throws {
        let (result, writable) = isSettable(window, attribute)
        if result == .attributeUnsupported || (result == .success && !writable) {
            throw GestureTargetError.windowResizeUnavailable
        }
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: attribute as String == kAXPositionAttribute as String
                    ? .checkPositionWritable : .checkSizeWritable,
                code: result
            )
        }
    }

    func write(_ window: AXUIElement, attribute: CFString, value: AXValue) throws {
        let result = setValue(window, attribute, value)
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(
                operation: attribute as String == kAXPositionAttribute as String
                    ? .setPosition : .setSize,
                code: result
            )
        }
    }
}

@MainActor
struct WindowMaximizer {
    var ax = WindowFrameAXClient()
    var completionTimeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(25)

    func maximize(_ window: AXUIElement, to frame: CGRect) async throws {
        try ax.requireWritable(window, attribute: kAXPositionAttribute as CFString)
        try ax.requireWritable(window, attribute: kAXSizeAttribute as CFString)
        if matches(try ax.readFrame(window), frame) { return }
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        try ax.write(window, attribute: kAXPositionAttribute as CFString, value: position)
        try ax.write(window, attribute: kAXSizeAttribute as CFString, value: dimensions)
        try await waitForFrame(window, expected: frame)
    }

    private func waitForFrame(_ window: AXUIElement, expected: CGRect) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: completionTimeout)
        while true {
            if matches(try ax.readFrame(window), expected) { return }
            let now = clock.now
            guard now < deadline else { throw GestureTargetError.windowMaximizeFailed }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
            guard clock.now < deadline else { throw GestureTargetError.windowMaximizeFailed }
        }
    }

    private func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 1
            && abs(actual.minY - expected.minY) <= 1
            && abs(actual.width - expected.width) <= 1
            && abs(actual.height - expected.height) <= 1
    }
}

extension MacGestureTargetSystemClient {
    func maximizeWindow(_ target: GestureTargetContext) async throws {
        let window = try target.requireWindow().element
        let maximizer = WindowMaximizer()
        let frame = try maximizer.ax.readFrame(window)
        let screens = NSScreen.screens
        guard let zeroScreen = screens.first else { throw GestureTargetError.noScreens }
        let appKitFrame = GestureTargetScreenGeometry.appKitWindowFrame(
            axOrigin: frame.origin,
            windowSize: frame.size,
            zeroScreenFrame: zeroScreen.frame
        )
        guard let index = GestureTargetScreenGeometry.targetScreenIndex(
            for: appKitFrame,
            screenFrames: screens.map(\.frame)
        ) else { throw GestureTargetError.noScreens }
        let destination = GestureTargetScreenGeometry.maximizedAXFrame(
            visibleFrame: screens[index].visibleFrame,
            zeroScreenFrame: zeroScreen.frame
        )
        try await maximizer.maximize(window, to: destination)
    }
}
