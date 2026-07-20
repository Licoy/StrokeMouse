import AppKit
import ApplicationServices
import XCTest
@testable import StrokeMouse

@MainActor
final class MacGestureTargetCapturerTests: XCTestCase {
    func testPointerCaptureUsesExactContainingWindowAndRawQuartzLocation() throws {
        let system = try makeSystem()
        let capturer = MacGestureTargetCapturer(system: system)
        let location = CGPoint(x: 321, y: 654)

        let snapshot = capturer.capture(
            policies: [.windowUnderPointer],
            at: location
        )
        let context = try snapshot.windowUnderPointer.requireContext()

        XCTAssertEqual(system.hitTestLocations, [location])
        XCTAssertEqual(context.policy, .windowUnderPointer)
        XCTAssertEqual(context.processIdentifier, system.application.processIdentifier)
        XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.windowElement))
        XCTAssertEqual(system.attributeReads, [.copyContainingWindow, .copyRole])
        guard case .unavailable(.targetNotCaptured(.frontmostWindow)) = snapshot.frontmostWindow
        else { return XCTFail("Frontmost target should not be captured") }
    }

    func testWindowElementFallbackIsAllowedOnlyForAXWindowRole() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow,
            code: .attributeUnsupported
        )
        let capturer = MacGestureTargetCapturer(system: system)

        let snapshot = capturer.capture(
            policies: [.windowUnderPointer],
            at: .zero
        )
        let context = try snapshot.windowUnderPointer.requireContext()

        XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.hitElement))
        XCTAssertEqual(system.attributeReads, [.copyContainingWindow, .copyRole])
    }

    func testDesktopElementCapturesItsApplicationWithoutAWindow() throws {
        for errorCode in [AXError.noValue, .attributeUnsupported] {
            let system = try makeSystem()
            system.containingWindowError = GestureTargetError.axOperationFailed(
                operation: .copyContainingWindow,
                code: errorCode
            )
            system.role = "AXScrollArea"
            let snapshot = MacGestureTargetCapturer(system: system).capture(
                policies: [.windowUnderPointer],
                at: .zero
            )
            let context = try snapshot.windowUnderPointer.requireContext()

            XCTAssertTrue(context.application === system.application)
            XCTAssertNil(context.window)
            XCTAssertEqual(context.bundleIdentifier, system.application.bundleIdentifier)
            XCTAssertEqual(system.applicationLookups, [system.application.processIdentifier])
        }
    }

    func testPointerNonWindowContainingElementStaysResolvedAtApplicationLevel() throws {
        let system = try makeSystem()
        system.role = "AXScrollArea"
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: .zero
        )
        let context = try snapshot.windowUnderPointer.requireContext()

        XCTAssertTrue(context.application === system.application)
        XCTAssertNil(context.window)
        XCTAssertEqual(context.processIdentifier, system.application.processIdentifier)
    }

    func testCannotCompleteIsReportedWithoutWindowFallback() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow,
            code: .cannotComplete
        )
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: .zero
        )

        guard case .unavailable(.axOperationFailed(let operation, let code)) =
            snapshot.windowUnderPointer
        else { return XCTFail("Expected the original AX failure") }
        XCTAssertEqual(operation, .copyContainingWindow)
        XCTAssertEqual(code, .cannotComplete)
        XCTAssertEqual(system.attributeReads, [.copyContainingWindow])
    }

    func testPointerWindowPIDMismatchDoesNotDowngradeToApplicationTarget() throws {
        let system = try makeSystem()
        let mismatchedPID = system.application.processIdentifier + 1
        system.windowProcessIdentifier = mismatchedPID
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: .zero
        )

        guard case .unavailable(.processMismatch(let expected, let actual)) =
            snapshot.windowUnderPointer
        else { return XCTFail("Expected the mismatched window PID to remain unavailable") }
        XCTAssertEqual(expected, system.application.processIdentifier)
        XCTAssertEqual(actual, mismatchedPID)
    }

    func testUnexpectedPointerWindowValueDoesNotBecomeApplicationTarget() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.unexpectedAXValue(
            operation: .copyContainingWindow
        )
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: .zero
        )

        guard case .unavailable(.unexpectedAXValue(.copyContainingWindow)) =
            snapshot.windowUnderPointer
        else { return XCTFail("Expected the invalid AX value to remain unavailable") }
    }

    func testFrontmostCaptureFreezesFocusedWindowAndApplicationIdentity() throws {
        let system = try makeSystem()
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.frontmostWindow],
            at: CGPoint(x: 999, y: 999)
        )
        let context = try snapshot.frontmostWindow.requireContext()

        XCTAssertEqual(context.policy, .frontmostWindow)
        XCTAssertTrue(context.application === system.application)
        XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.windowElement))
        XCTAssertEqual(system.attributeReads, [.copyFocusedWindow, .copyRole])
        XCTAssertTrue(system.hitTestLocations.isEmpty)
    }

    func testFrontmostApplicationWithoutFocusedWindowStaysResolved() throws {
        for errorCode in [AXError.noValue, .attributeUnsupported] {
            let system = try makeSystem()
            system.focusedWindowError = GestureTargetError.axOperationFailed(
                operation: .copyFocusedWindow,
                code: errorCode
            )
            let snapshot = MacGestureTargetCapturer(system: system).capture(
                policies: [.frontmostWindow],
                at: .zero
            )
            let context = try snapshot.frontmostWindow.requireContext()

            XCTAssertTrue(context.application === system.application)
            XCTAssertNil(context.window)
            XCTAssertEqual(context.processIdentifier, system.application.processIdentifier)
            XCTAssertEqual(system.attributeReads, [.copyFocusedWindow])
        }
    }

    func testFrontmostNonWindowFocusedElementStaysResolvedAtApplicationLevel() throws {
        let system = try makeSystem()
        system.role = "AXScrollArea"
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.frontmostWindow],
            at: .zero
        )
        let context = try snapshot.frontmostWindow.requireContext()

        XCTAssertTrue(context.application === system.application)
        XCTAssertNil(context.window)
        XCTAssertEqual(context.processIdentifier, system.application.processIdentifier)
    }

    func testFrontmostCannotCompleteRemainsUnavailable() throws {
        let system = try makeSystem()
        system.focusedWindowError = GestureTargetError.axOperationFailed(
            operation: .copyFocusedWindow,
            code: .cannotComplete
        )
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.frontmostWindow],
            at: .zero
        )

        guard case .unavailable(.axOperationFailed(let operation, let code)) =
            snapshot.frontmostWindow
        else { return XCTFail("Expected the original focused-window AX failure") }
        XCTAssertEqual(operation, .copyFocusedWindow)
        XCTAssertEqual(code, .cannotComplete)
    }

    func testFrontmostWindowPIDMismatchDoesNotDowngradeToApplicationTarget() throws {
        let system = try makeSystem()
        let mismatchedPID = system.application.processIdentifier + 1
        system.windowProcessIdentifier = mismatchedPID
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.frontmostWindow],
            at: .zero
        )

        guard case .unavailable(.processMismatch(let expected, let actual)) =
            snapshot.frontmostWindow
        else { return XCTFail("Expected the mismatched window PID to remain unavailable") }
        XCTAssertEqual(expected, system.application.processIdentifier)
        XCTAssertEqual(actual, mismatchedPID)
    }

    func testUnexpectedFrontmostWindowValueDoesNotBecomeApplicationTarget() throws {
        let system = try makeSystem()
        system.focusedWindowError = GestureTargetError.unexpectedAXValue(
            operation: .copyFocusedWindow
        )
        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.frontmostWindow],
            at: .zero
        )

        guard case .unavailable(.unexpectedAXValue(.copyFocusedWindow)) =
            snapshot.frontmostWindow
        else { return XCTFail("Expected the invalid AX value to remain unavailable") }
    }

    private func makeSystem() throws -> RecordingGestureTargetCaptureSystemClient {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let application = try XCTUnwrap(
            NSRunningApplication(processIdentifier: processIdentifier)
        )
        return RecordingGestureTargetCaptureSystemClient(application: application)
    }
}

@MainActor
private final class RecordingGestureTargetCaptureSystemClient:
    GestureTargetCaptureSystemClient
{
    let application: NSRunningApplication
    let hitElement: AXUIElement
    let windowElement: AXUIElement

    var role = kAXWindowRole as String
    var focusedWindowError: Error?
    var containingWindowError: Error?
    var windowProcessIdentifier: pid_t?
    private(set) var hitTestLocations: [CGPoint] = []
    private(set) var attributeReads: [GestureTargetAXOperation] = []
    private(set) var applicationLookups: [pid_t] = []

    init(application: NSRunningApplication) {
        self.application = application
        hitElement = AXUIElementCreateApplication(application.processIdentifier + 1)
        windowElement = AXUIElementCreateApplication(application.processIdentifier)
    }

    var frontmostApplication: NSRunningApplication? { application }

    func runningApplication(processIdentifier: pid_t) -> NSRunningApplication? {
        applicationLookups.append(processIdentifier)
        return processIdentifier == application.processIdentifier ? application : nil
    }

    func element(at quartzLocation: CGPoint) throws -> AXUIElement {
        hitTestLocations.append(quartzLocation)
        return hitElement
    }

    func copyElement(
        from _: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> AXUIElement {
        attributeReads.append(attribute.operation)
        switch attribute.operation {
        case .copyFocusedWindow:
            if let focusedWindowError { throw focusedWindowError }
            return windowElement
        case .copyContainingWindow:
            if let containingWindowError { throw containingWindowError }
            return windowElement
        default:
            throw GestureTargetError.unexpectedCaptureFailure(
                "Unexpected element read: \(attribute.operation.rawValue)"
            )
        }
    }

    func copyString(
        from _: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> String {
        attributeReads.append(attribute.operation)
        return role
    }

    func processIdentifier(
        of element: AXUIElement,
        operation _: GestureTargetAXOperation
    ) throws -> pid_t {
        if CFEqual(element, windowElement), let windowProcessIdentifier {
            return windowProcessIdentifier
        }
        return application.processIdentifier
    }
}
