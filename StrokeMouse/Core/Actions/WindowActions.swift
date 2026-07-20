import AppKit
import Foundation

@MainActor
protocol GestureTargetSystemClient: AnyObject {
    func validateWindow(_ target: GestureTargetContext) throws
    func pressWindowControl(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) throws -> Bool
    func hideApplication(_ target: GestureTargetContext) throws
    func centerWindow(_ target: GestureTargetContext) throws
    func setMainWindow(_ target: GestureTargetContext) throws
    func raiseWindow(_ target: GestureTargetContext) throws
    func activateApplication(_ target: GestureTargetContext) -> Bool
    func isApplicationActive(_ target: GestureTargetContext) throws -> Bool
    func verifyFocusedWindow(_ target: GestureTargetContext) throws
    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) throws
}

@MainActor
final class MacGestureTargetActionPlatform: GestureTargetActionPlatform {
    private let windowActions: WindowActions

    init(windowActions: WindowActions? = nil) {
        self.windowActions = windowActions ?? WindowActions()
    }

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) async throws {
        try await windowActions.performShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            target: target
        )
    }

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {
        try await windowActions.perform(command, target: target)
    }
}

@MainActor
struct WindowActions {
    private let system: any GestureTargetSystemClient
    private let activationTimeout: Duration
    private let pollInterval: Duration

    init(
        system: (any GestureTargetSystemClient)? = nil,
        activationTimeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(25)
    ) {
        self.system = system ?? MacGestureTargetSystemClient()
        self.activationTimeout = activationTimeout
        self.pollInterval = pollInterval
    }

    func perform(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {
        switch command {
        case .hide:
            try system.hideApplication(target)
        case .center:
            try system.validateWindow(target)
            try system.centerWindow(target)
        case .close, .minimize, .zoom:
            try system.validateWindow(target)
            guard try system.pressWindowControl(command, target: target) else {
                throw GestureTargetError.windowControlUnavailable(command)
            }
        case .fullscreen:
            try system.validateWindow(target)
            if try !system.pressWindowControl(.fullscreen, target: target) {
                try await performFullscreenShortcut(target: target)
            }
        }
    }

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        target: GestureTargetContext
    ) async throws {
        try system.validateWindow(target)
        try system.setMainWindow(target)
        try system.raiseWindow(target)
        guard system.activateApplication(target) else {
            throw GestureTargetError.activationFailed(target.processIdentifier)
        }
        try await waitUntilActive(target)
        try system.verifyFocusedWindow(target)
        try system.postShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            target: target
        )
    }

    private func performFullscreenShortcut(
        target: GestureTargetContext
    ) async throws {
        let modifiers = UInt(
            NSEvent.ModifierFlags.control.rawValue
                | NSEvent.ModifierFlags.command.rawValue
        )
        try await performShortcut(keyCode: 3, modifiers: modifiers, target: target)
    }

    private func waitUntilActive(_ target: GestureTargetContext) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: activationTimeout)
        while try !system.isApplicationActive(target) {
            guard clock.now < deadline else {
                throw GestureTargetError.activationTimedOut(target.processIdentifier)
            }
            try await Task.sleep(for: pollInterval)
        }
    }
}
