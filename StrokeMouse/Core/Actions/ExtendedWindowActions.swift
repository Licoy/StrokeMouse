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
        try await performFrameChange(window) { current in
            try layout.frame(in: self.screenGeometry(for: current).usable)
        }
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
        try await performFrameChange(window) { current in
            let geometry = try self.screenGeometry(for: current)
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
            return destination
        }
    }

    func restoreWindowFrame(_ window: AXUIElement, using resizer: WindowMaximizer? = nil) async throws {
        try await performFrameChange(window, using: resizer) { _ in
            guard let saved = self.previousFrames.last(where: { CFEqual($0.window, window) }) else {
                throw WindowLayoutError.noPreviousFrame
            }
            return saved.frame
        }
    }

    func applyFrame(_ destination: CGRect, window: AXUIElement, using resizer: WindowMaximizer? = nil) async throws {
        try await performFrameChange(window, using: resizer) { _ in destination }
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
