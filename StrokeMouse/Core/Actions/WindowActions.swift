import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
protocol GestureTargetSystemClient: AnyObject {
    func performExtendedWindow(_ command: WindowCommand, target: GestureTargetContext) async throws
    func applyWindowLayout(_ layout: WindowLayout, target: GestureTargetContext) async throws
    func validateWindow(_ target: GestureTargetContext) throws
    func pressWindowControl(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) throws -> Bool
    func hideApplication(_ target: GestureTargetContext) throws
    func setWindowMinimized(_ target: GestureTargetContext) throws
    func maximizeWindow(_ target: GestureTargetContext) async throws
    func centerWindow(_ target: GestureTargetContext) async throws
    func setMainWindow(_ target: GestureTargetContext) throws
    func raiseWindow(_ target: GestureTargetContext) throws
    func activateApplication(_ target: GestureTargetContext) -> Bool
    func isApplicationActive(_ target: GestureTargetContext) throws -> Bool
    func isWindowFocused(_ target: GestureTargetContext) throws -> Bool
    func verifyFocusedWindow(_ target: GestureTargetContext) throws
    func postShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext
    ) throws
}

extension GestureTargetSystemClient {
    func performExtendedWindow(_ command: WindowCommand, target: GestureTargetContext) async throws {
        throw GestureTargetError.windowControlUnavailable(command)
    }
    func applyWindowLayout(_ layout: WindowLayout, target: GestureTargetContext) async throws {
        throw GestureTargetError.windowResizeUnavailable
    }
}

@MainActor
struct WindowActions: GestureTargetActionPlatform {
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

    func performWindow(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {
        if ![.hide, .restoreMinimized, .minimizeAll, .restoreAllMinimized].contains(command) {
            _ = try target.requireWindow()
            try system.validateWindow(target)
        }

        switch command {
        case .hide:
            try system.hideApplication(target)
        case .maximize:
            try await system.maximizeWindow(target)
        case .center:
            try await system.centerWindow(target)
        case .restoreFrame, .restoreMinimized, .minimizeAll, .restoreAllMinimized,
             .maximizeHeight, .maximizeWidth, .nextScreen:
            try await system.performExtendedWindow(command, target: target)
        case .close, .minimize, .zoom, .fullscreen:
            if try !system.pressWindowControl(command, target: target) {
                try await performWindowControlFallback(command, target: target)
            }
        }
    }

    func performCustomWindow(_ layout: WindowLayout, target: GestureTargetContext) async throws {
        try system.validateWindow(target)
        try await system.applyWindowLayout(layout, target: target)
    }

    func performShortcut(
        keyCode: UInt16,
        modifiers: UInt,
        orderedChord: ShortcutChord?,
        target: GestureTargetContext,
        beforePosting: (() -> Void)?
    ) async throws {
        if target.window != nil {
            try system.validateWindow(target)
            if try system.isWindowFocused(target) {
                if try !system.isApplicationActive(target) {
                    guard system.activateApplication(target) else {
                        throw GestureTargetError.activationFailed(target.processIdentifier)
                    }
                    try await waitUntilActive(target)
                }
            } else {
                try system.setMainWindow(target)
                try system.raiseWindow(target)
                guard system.activateApplication(target) else {
                    throw GestureTargetError.activationFailed(target.processIdentifier)
                }
                try await waitUntilActive(target)
            }
            try system.verifyFocusedWindow(target)
        } else if try !system.isApplicationActive(target) {
            guard system.activateApplication(target) else {
                throw GestureTargetError.activationFailed(target.processIdentifier)
            }
            try await waitUntilActive(target)
        }
        beforePosting?()
        try system.postShortcut(
            keyCode: keyCode,
            modifiers: modifiers,
            orderedChord: orderedChord,
            target: target
        )
    }

    private func performWindowControlFallback(
        _ command: WindowCommand,
        target: GestureTargetContext
    ) async throws {
        let chord: ShortcutChord
        switch command {
        case .minimize:
            do {
                try system.setWindowMinimized(target)
                return
            } catch GestureTargetError.windowControlUnavailable(.minimize) {
                // ⌘M is the standard Window › Minimize item. Close has no such
                // fallback: ⌘W often closes only a tab.
                chord = ShortcutChord(modifiers: [.command], keyCode: UInt16(kVK_ANSI_M))
            }
        case .fullscreen:
            chord = ShortcutChord(modifiers: [.control, .command], keyCode: UInt16(kVK_ANSI_F))
        default:
            throw GestureTargetError.windowControlUnavailable(command)
        }
        try await performShortcut(
            keyCode: chord.legacyKeyCode,
            modifiers: chord.legacyModifiers,
            orderedChord: chord,
            target: target
        )
    }

    private func waitUntilActive(_ target: GestureTargetContext) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: activationTimeout)
        while true {
            if try system.isApplicationActive(target) { return }
            let now = clock.now
            guard now < deadline else {
                throw GestureTargetError.activationTimedOut(target.processIdentifier)
            }
            try await Task.sleep(for: min(pollInterval, now.duration(to: deadline)))
            guard clock.now < deadline else {
                throw GestureTargetError.activationTimedOut(target.processIdentifier)
            }
        }
    }
}
