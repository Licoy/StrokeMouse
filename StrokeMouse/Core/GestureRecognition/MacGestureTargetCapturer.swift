import AppKit
import ApplicationServices
import Foundation
import OSLog

final class MacGestureTargetCapturer: GestureTargetCapturing,
    GestureTargetIdentifying,
    @unchecked Sendable
{
    private enum PointerHit {
        case accessibility(element: AXUIElement, processIdentifier: pid_t)
        case window(GestureTargetWindowDescriptor)

        var processIdentifier: pid_t {
            switch self {
            case .accessibility(_, let processIdentifier): processIdentifier
            case .window(let descriptor): descriptor.processIdentifier
            }
        }
    }

    private static let logger = Logger(
        subsystem: Constants.bundleID,
        category: "GestureTargetCapture"
    )
    private let system: any GestureTargetCaptureSystemClient

    init(system: (any GestureTargetCaptureSystemClient)? = nil) {
        self.system = system ?? MacGestureTargetCaptureSystemClient()
    }

    func capture(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        GestureTargetSnapshot(
            frontmostWindow: resolution(
                for: .frontmostWindow,
                whenRequestedBy: policies,
                at: quartzLocation
            ),
            windowUnderPointer: resolution(
                for: .windowUnderPointer,
                whenRequestedBy: policies,
                at: quartzLocation
            )
        )
    }

    func captureIdentity(
        policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetSnapshot {
        GestureTargetSnapshot(
            frontmostWindow: identity(
                for: .frontmostWindow,
                whenRequestedBy: policies,
                at: quartzLocation
            ),
            windowUnderPointer: identity(
                for: .windowUnderPointer,
                whenRequestedBy: policies,
                at: quartzLocation
            )
        )
    }

    private func resolution(
        for policy: GestureTargetPolicy,
        whenRequestedBy policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetResolution {
        resolve(policy, whenRequestedBy: policies) {
            switch policy {
            case .frontmostWindow:
                return try captureFrontmostTarget()
            case .windowUnderPointer:
                return try captureTargetUnderPointer(at: quartzLocation)
            }
        }
    }

    /// Frontmost identity is `NSWorkspace` only. The pointer policy still
    /// hit-tests, but neither path copies an AX window.
    private func identity(
        for policy: GestureTargetPolicy,
        whenRequestedBy policies: Set<GestureTargetPolicy>,
        at quartzLocation: CGPoint
    ) -> GestureTargetResolution {
        resolve(policy, whenRequestedBy: policies) {
            switch policy {
            case .frontmostWindow:
                guard let application = system.frontmostApplication else {
                    throw GestureTargetError.noFrontmostApplication
                }
                return makeContext(
                    policy: .frontmostWindow,
                    application: application,
                    window: nil
                )
            case .windowUnderPointer:
                let pointerHit = try pointerHit(at: quartzLocation)
                let processIdentifier = pointerHit.processIdentifier
                guard let application = system.runningApplication(
                    processIdentifier: processIdentifier
                ) else {
                    throw GestureTargetError.applicationUnavailable(processIdentifier)
                }
                return makeContext(
                    policy: .windowUnderPointer,
                    application: application,
                    window: nil
                )
            }
        }
    }

    private func resolve(
        _ policy: GestureTargetPolicy,
        whenRequestedBy policies: Set<GestureTargetPolicy>,
        _ body: () throws -> GestureTargetContext
    ) -> GestureTargetResolution {
        guard policies.contains(policy) else {
            return .unavailable(.targetNotCaptured(policy))
        }
        do {
            return .resolved(try body())
        } catch let error as GestureTargetError {
            return .unavailable(error)
        } catch {
            return .unavailable(.unexpectedCaptureFailure(String(describing: error)))
        }
    }

    private func captureFrontmostTarget() throws -> GestureTargetContext {
        guard let application = system.frontmostApplication else {
            throw GestureTargetError.noFrontmostApplication
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let window = try optionalFrontmostWindow(
            of: appElement,
            expectedProcessIdentifier: application.processIdentifier
        )
        return makeContext(
            policy: .frontmostWindow,
            application: application,
            window: window
        )
    }

    private func captureTargetUnderPointer(at location: CGPoint) throws -> GestureTargetContext {
        let pointerHit = try pointerHit(at: location)
        let processIdentifier = pointerHit.processIdentifier
        guard let application = system.runningApplication(processIdentifier: processIdentifier) else {
            throw GestureTargetError.applicationUnavailable(processIdentifier)
        }
        let window: AXUIElement?
        switch pointerHit {
        case .accessibility(let hit, _):
            window = try optionalContainingWindow(
                of: hit,
                expectedProcessIdentifier: processIdentifier
            )
        case .window(let descriptor):
            window = try matchingWindow(for: descriptor)
        }
        return makeContext(
            policy: .windowUnderPointer,
            application: application,
            window: window
        )
    }

    private func pointerHit(at location: CGPoint) throws -> PointerHit {
        do {
            let hit = try system.element(at: location)
            let processIdentifier = try system.processIdentifier(
                of: hit,
                operation: .getProcessIdentifier
            )
            return .accessibility(element: hit, processIdentifier: processIdentifier)
        } catch GestureTargetError.axOperationFailed(let operation, let code)
            where operation == .hitTest && code == .notImplemented
        {
            do {
                let descriptor = try system.windowUnderPointer(at: location)
                Self.logger.notice(
                    "operation=hitTest code=\(code.rawValue) result=located pid=\(descriptor.processIdentifier) window=\(descriptor.windowNumber) layer=\(descriptor.layer)"
                )
                return .window(descriptor)
            } catch {
                Self.logger.error(
                    "operation=hitTest code=\(code.rawValue) result=unavailable pid=0"
                )
                throw error
            }
        }
    }

    private func matchingWindow(
        for descriptor: GestureTargetWindowDescriptor
    ) throws -> AXUIElement {
        let windows = try system.windows(processIdentifier: descriptor.processIdentifier)
        var matches: [AXUIElement] = []
        for window in windows {
            try validatePID(of: window, expected: descriptor.processIdentifier)
            try validateWindowRole(window)
            if try system.frame(of: window).standardized == descriptor.bounds {
                matches.append(window)
            }
        }
        guard matches.count == 1, let match = matches.first else {
            Self.logger.error(
                "operation=hitTest code=\(AXError.notImplemented.rawValue) result=windowMatchCount-\(matches.count) pid=\(descriptor.processIdentifier) window=\(descriptor.windowNumber) layer=\(descriptor.layer)"
            )
            throw GestureTargetError.windowUnavailable
        }
        try system.validateWindow(descriptor)
        Self.logger.notice(
            "operation=hitTest code=\(AXError.notImplemented.rawValue) result=windowMatched pid=\(descriptor.processIdentifier) window=\(descriptor.windowNumber) layer=\(descriptor.layer)"
        )
        return match
    }

    private func makeContext(
        policy: GestureTargetPolicy,
        application: NSRunningApplication,
        window: AXUIElement?
    ) -> GestureTargetContext {
        GestureTargetContext(
            policy: policy,
            identity: GestureTargetIdentity(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                bundlePath: (application.bundleURL ?? application.executableURL)?.path
            ),
            application: application,
            window: window.map(GestureWindowTarget.init)
        )
    }

    private func optionalFrontmostWindow(
        of application: AXUIElement,
        expectedProcessIdentifier: pid_t
    ) throws -> AXUIElement? {
        do {
            let window = try system.copyElement(
                from: application,
                attribute: GestureTargetAXAttribute(
                    name: kAXFocusedWindowAttribute as CFString,
                    operation: .copyFocusedWindow
                )
            )
            try validatePID(of: window, expected: expectedProcessIdentifier)
            return try windowIfOperable(window)
        } catch GestureTargetError.axOperationFailed(let operation, let code)
            where operation == .copyFocusedWindow
                && (code == .noValue || code == .attributeUnsupported)
        {
            return nil
        }
    }

    private func optionalContainingWindow(
        of hit: AXUIElement,
        expectedProcessIdentifier: pid_t
    ) throws -> AXUIElement? {
        do {
            let window = try system.copyElement(
                from: hit,
                attribute: GestureTargetAXAttribute(
                    name: kAXWindowAttribute as CFString,
                    operation: .copyContainingWindow
                )
            )
            try validatePID(of: window, expected: expectedProcessIdentifier)
            return try windowIfOperable(window)
        } catch GestureTargetError.axOperationFailed(let operation, let code)
            where operation == .copyContainingWindow
                && (code == .noValue || code == .attributeUnsupported)
        {
            let window = try parentWindow(of: hit, expectedProcessIdentifier: expectedProcessIdentifier)
            Self.logger.notice(
                "operation=copyContainingWindow code=\(code.rawValue) result=parentTraversal windowFound=\(window != nil) pid=\(expectedProcessIdentifier)"
            )
            return window
        }
    }

    /// Some apps (including HBuilderX) omit AXWindow but expose its parent chain.
    /// Traverse only the hit's own ancestry, never a focused or arbitrary app window.
    private func parentWindow(
        of hit: AXUIElement,
        expectedProcessIdentifier: pid_t
    ) throws -> AXUIElement? {
        var element = hit
        var visited: [AXUIElement] = []
        for _ in 0..<32 {
            guard !visited.contains(where: { CFEqual($0, element) }) else {
                throw GestureTargetError.unexpectedCaptureFailure("Cyclic AX parent chain")
            }
            visited.append(element)
            try validatePID(of: element, expected: expectedProcessIdentifier)
            let role = try system.copyString(
                from: element,
                attribute: GestureTargetAXAttribute(name: kAXRoleAttribute as CFString, operation: .copyRole)
            )
            if role == kAXWindowRole as String { return element }
            if role == kAXApplicationRole as String { return nil }
            do {
                element = try system.copyElement(
                    from: element,
                    attribute: GestureTargetAXAttribute(name: kAXParentAttribute as CFString, operation: .copyParent)
                )
            } catch GestureTargetError.axOperationFailed(let operation, let code)
                where operation == .copyParent && (code == .noValue || code == .attributeUnsupported)
            {
                return nil
            }
        }
        throw GestureTargetError.unexpectedCaptureFailure("AX parent chain exceeds 32 elements")
    }

    private func windowIfOperable(_ element: AXUIElement) throws -> AXUIElement? {
        do {
            try validateWindowRole(element)
            return element
        } catch GestureTargetError.windowRoleMismatch {
            return nil
        }
    }

    private func validateWindowRole(_ window: AXUIElement) throws {
        let role = try system.copyString(
            from: window,
            attribute: GestureTargetAXAttribute(
                name: kAXRoleAttribute as CFString,
                operation: .copyRole
            )
        )
        guard role == kAXWindowRole as String else {
            throw GestureTargetError.windowRoleMismatch
        }
    }

    private func validatePID(of window: AXUIElement, expected: pid_t) throws {
        let actual = try system.processIdentifier(
            of: window,
            operation: .getProcessIdentifier
        )
        guard actual == expected else {
            throw GestureTargetError.processMismatch(expected: expected, actual: actual)
        }
    }
}
