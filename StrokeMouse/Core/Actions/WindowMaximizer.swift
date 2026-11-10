import AppKit
import ApplicationServices
import OSLog

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

    func maximize(_ window: AXUIElement, to frame: CGRect, correctPositionAfterResize: Bool = false) async throws {
        try ax.requireWritable(window, attribute: kAXPositionAttribute as CFString)
        try ax.requireWritable(window, attribute: kAXSizeAttribute as CFString)
        if Self.framesMatch(try ax.readFrame(window), frame) { return }
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        try ax.write(window, attribute: kAXPositionAttribute as CFString, value: position)
        try ax.write(window, attribute: kAXSizeAttribute as CFString, value: dimensions)
        if correctPositionAfterResize {
            try ax.write(window, attribute: kAXPositionAttribute as CFString, value: position)
        }
        try await waitForFrame(window, expected: frame)
    }

    /// Layouts accept an application's size constraints, but still verify that
    /// resizing took effect and that the final position was applied. Keep the
    /// maximize path strict: filling the display is a different promise.
    @discardableResult
    func applyLayout(_ window: AXUIElement, to requested: CGRect, knownAcceptedSize: CGSize? = nil) async throws -> CGRect {
        try ax.requireWritable(window, attribute: kAXPositionAttribute as CFString)
        try ax.requireWritable(window, attribute: kAXSizeAttribute as CFString)
        let original = try ax.readFrame(window)
        if Self.framesMatch(original, requested) { return original }
        var size = requested.size
        guard let dimensions = AXValueCreate(.cgSize, &size) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setSize)
        }
        try ax.write(window, attribute: kAXSizeAttribute as CFString, value: dimensions)
        let resized = try await waitForLayoutSize(window, original: original, requested: requested, knownAcceptedSize: knownAcceptedSize)

        // Position must be sent after the asynchronous resize has settled;
        // otherwise AppKit may clamp it against the window's old dimensions.
        var origin = requested.origin
        guard let position = AXValueCreate(.cgPoint, &origin) else {
            throw GestureTargetError.unexpectedAXValue(operation: .setPosition)
        }
        try ax.write(window, attribute: kAXPositionAttribute as CFString, value: position)
        let accepted = CGRect(origin: requested.origin, size: resized.size)
        do {
            try await waitForFrame(window, expected: accepted)
        } catch GestureTargetError.windowMaximizeFailed {
            let actual = try ax.readFrame(window)
            Self.layoutLogger.error("Window layout verification failed: requested=\(NSStringFromRect(requested), privacy: .public), accepted=\(NSStringFromRect(accepted), privacy: .public), actual=\(NSStringFromRect(actual), privacy: .public)")
            throw WindowLayoutError.frameNotApplied
        }
        return try ax.readFrame(window)
    }

    private static let layoutLogger = Logger(subsystem: "com.strokemouse.app", category: "WindowLayout")

    private func waitForLayoutSize(
        _ window: AXUIElement, original: CGRect, requested: CGRect, knownAcceptedSize: CGSize?
    ) async throws -> CGRect {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: completionTimeout)
        var last = original
        var stableSince = clock.now
        while true {
            let actual = try ax.readFrame(window)
            if sizeMatches(actual.size, requested.size) { return actual }
            if let knownAcceptedSize, sizeMatches(actual.size, knownAcceptedSize) { return actual }
            let now = clock.now
            if !sizeMatches(actual.size, last.size) {
                stableSince = now
                last = actual
            }
            // A constrained resize is successful once its new size settles.
            // An unchanged size must not turn ignored AX writes into success.
            let changed = !sizeMatches(actual.size, original.size)
            if changed && stableSince.duration(to: now) >= .milliseconds(150) { return actual }
            if now >= deadline {
                if changed { return actual }
                Self.layoutLogger.error("Window resize had no effect: requested=\(NSStringFromRect(requested), privacy: .public), actual=\(NSStringFromRect(actual), privacy: .public)")
                throw WindowLayoutError.frameNotApplied
            }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
        }
    }

    private func sizeMatches(_ actual: CGSize, _ expected: CGSize) -> Bool {
        abs(actual.width - expected.width) <= 2 && abs(actual.height - expected.height) <= 2
    }

    private func waitForFrame(_ window: AXUIElement, expected: CGRect) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: completionTimeout)
        while true {
            if Self.framesMatch(try ax.readFrame(window), expected) { return }
            let now = clock.now
            guard now < deadline else { throw GestureTargetError.windowMaximizeFailed }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
        }
    }

    static func framesMatch(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 2
            && abs(actual.minY - expected.minY) <= 2
            && abs(actual.width - expected.width) <= 2
            && abs(actual.height - expected.height) <= 2
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
        try await maximizeWindow(window, to: destination, using: maximizer)
    }

    /// Compare with the same tolerance as AX readback verification. A rounded
    /// maximized frame must never replace the user's pre-maximize restore point.
    func maximizeWindow(_ window: AXUIElement, to destination: CGRect, using maximizer: WindowMaximizer) async throws {
        guard !maximizingWindows.contains(where: { CFEqual($0, window) }) else { return }
        let current = try maximizer.ax.readFrame(window)
        guard !WindowMaximizer.framesMatch(current, destination) else { return }
        maximizingWindows.append(window)
        defer { maximizingWindows.removeAll { CFEqual($0, window) } }
        rememberFrame(window, frame: current)
        try await maximizer.maximize(window, to: destination)
    }
}
