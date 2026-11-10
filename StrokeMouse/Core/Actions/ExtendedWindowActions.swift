import AppKit
import ApplicationServices

extension MacGestureTargetSystemClient {
    func rememberFrame(_ window: AXUIElement, frame: CGRect) {
        previousFrames.removeAll { CFEqual($0.window, window) }
        previousFrames.append((window, frame))
        // Bound retained AX references, including windows that have since closed.
        if previousFrames.count > 100 { previousFrames.removeFirst() }
    }

    func applyWindowLayout(_ layout: WindowLayout, target: GestureTargetContext) async throws {
        guard layout.isValid else { throw WindowLayoutError.invalidLayout }
        let window = try target.requireWindow().element
        let current = try WindowFrameAXClient().readFrame(window)
        let destination = try layout.frame(in: screenGeometry(for: current).usable)
        try await applyFrame(destination, window: window, previous: current)
    }

    func performExtendedWindow(_ command: WindowCommand, target: GestureTargetContext) async throws {
        if [.restoreMinimized, .minimizeAll, .restoreAllMinimized].contains(command) {
            try performMinimization(command, target: target)
            return
        }
        let window = try target.requireWindow().element
        if command == .restoreFrame {
            try await restoreWindowFrame(window)
            return
        }
        let current = try WindowFrameAXClient().readFrame(window)
        let geometry = try screenGeometry(for: current)
        var destination = current
        switch command {
        case .maximizeHeight:
            destination.origin.y = geometry.usable.minY
            destination.size.height = geometry.usable.height
        case .maximizeWidth:
            destination.origin.x = geometry.usable.minX
            destination.size.width = geometry.usable.width
        case .nextScreen:
            guard geometry.screens.count > 1 else { throw WindowLayoutError.noOtherScreen }
            let next = geometry.screens[(geometry.index + 1) % geometry.screens.count]
            let nextFrame = GestureTargetScreenGeometry.maximizedAXFrame(
                visibleFrame: next.visibleFrame, zeroScreenFrame: geometry.screens[0].frame
            )
            // Preserve relative placement and size across displays with different resolutions.
            destination = CGRect(
                x: nextFrame.minX + (current.minX - geometry.usable.minX) / geometry.usable.width * nextFrame.width,
                y: nextFrame.minY + (current.minY - geometry.usable.minY) / geometry.usable.height * nextFrame.height,
                width: min(current.width / geometry.usable.width * nextFrame.width, nextFrame.width),
                height: min(current.height / geometry.usable.height * nextFrame.height, nextFrame.height)
            )
            destination.origin.x = min(max(destination.minX, nextFrame.minX), nextFrame.maxX - destination.width)
            destination.origin.y = min(max(destination.minY, nextFrame.minY), nextFrame.maxY - destination.height)
        default:
            throw GestureTargetError.windowControlUnavailable(command)
        }
        try await applyFrame(destination, window: window, previous: current)
    }

    func restoreWindowFrame(_ window: AXUIElement, using resizer: WindowMaximizer? = nil) async throws {
        guard let saved = previousFrames.last(where: { CFEqual($0.window, window) }) else {
            throw WindowLayoutError.noPreviousFrame
        }
        let current = try (resizer?.ax ?? WindowFrameAXClient()).readFrame(window)
        // The last two layouts can be toggled repeatedly.
        try await applyFrame(saved.frame, window: window, previous: current, using: resizer)
    }

    private func applyFrame(_ destination: CGRect, window: AXUIElement, previous: CGRect, using suppliedResizer: WindowMaximizer? = nil) async throws {
        let knownSize = acceptedLayoutSizes.last {
            CFEqual($0.window, window) && $0.requested == destination.size
        }?.accepted
        let expected = CGRect(origin: destination.origin, size: knownSize ?? destination.size)
        guard !WindowMaximizer.framesMatch(previous, expected) else { return }
        // Record before writing so partially applied operations can also be undone.
        rememberFrame(window, frame: previous)
        do {
            var resizer = suppliedResizer ?? WindowMaximizer()
            if suppliedResizer == nil { resizer.completionTimeout = .milliseconds(1500) }
            let applied = try await resizer.applyLayout(window, to: destination, knownAcceptedSize: knownSize)
            acceptedLayoutSizes.removeAll { CFEqual($0.window, window) }
            acceptedLayoutSizes.append((window, destination.size, applied.size))
            if acceptedLayoutSizes.count > 100 { acceptedLayoutSizes.removeFirst() }
        } catch GestureTargetError.windowMaximizeFailed {
            throw WindowLayoutError.frameNotApplied
        }
    }

    private func screenGeometry(for frame: CGRect) throws -> (screens: [NSScreen], index: Int, usable: CGRect) {
        let screens = NSScreen.screens
        guard let first = screens.first else { throw GestureTargetError.noScreens }
        let appKitFrame = GestureTargetScreenGeometry.appKitWindowFrame(
            axOrigin: frame.origin, windowSize: frame.size, zeroScreenFrame: first.frame
        )
        guard let index = GestureTargetScreenGeometry.targetScreenIndex(for: appKitFrame, screenFrames: screens.map(\.frame)) else {
            throw GestureTargetError.noScreens
        }
        return (screens, index, GestureTargetScreenGeometry.maximizedAXFrame(
            visibleFrame: screens[index].visibleFrame, zeroScreenFrame: first.frame
        ))
    }

    private func performMinimization(_ command: WindowCommand, target: GestureTargetContext) throws {
        guard let app = target.application, !app.isTerminated,
              app.processIdentifier == target.processIdentifier else {
            throw GestureTargetError.applicationUnavailable(target.processIdentifier)
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(target.processIdentifier), kAXWindowsAttribute as CFString, &value
        )
        guard result == .success else {
            throw GestureTargetError.axOperationFailed(operation: .copyWindows, code: result)
        }
        guard let windows = value as? [AXUIElement] else {
            throw GestureTargetError.unexpectedAXValue(operation: .copyWindows)
        }
        var changed = 0
        var firstError: AXError?
        for window in windows {
            var minimized: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            guard read == .success, let isMinimized = minimized as? Bool else {
                if firstError == nil { firstError = read == .success ? .failure : read }
                continue
            }
            let shouldMinimize = command == .minimizeAll
            guard isMinimized != shouldMinimize else { continue }
            let write = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                                     shouldMinimize ? kCFBooleanTrue : kCFBooleanFalse)
            if write != .success {
                if firstError == nil { firstError = write }
                continue
            }
            changed += 1
            if command == .restoreMinimized {
                firstError = nil
                let restored = GestureTargetContext(policy: target.policy, identity: target.identity,
                                                    application: app, window: GestureWindowTarget(element: window))
                try raiseWindow(restored)
                guard activateApplication(restored) else {
                    throw GestureTargetError.activationFailed(target.processIdentifier)
                }
                break
            }
        }
        // A partial batch is reported, rather than claiming every window succeeded.
        if let firstError {
            throw GestureTargetError.axOperationFailed(operation: .setMinimized, code: firstError)
        }
        if changed == 0 && command == .restoreMinimized { throw WindowLayoutError.noMinimizedWindow }
    }
}
