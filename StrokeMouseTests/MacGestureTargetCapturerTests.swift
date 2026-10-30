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
        XCTAssertTrue(system.pointerWindowLocations.isEmpty)
        XCTAssertTrue(system.applicationWindowLookups.isEmpty)
        guard case .unavailable(.targetNotCaptured(.frontmostWindow)) = snapshot.frontmostWindow
        else { return XCTFail("Frontmost target should not be captured") }
    }

    func testHitTestNotImplementedUsesPointerWindowForIdentityWithoutReadingAXWindows() throws {
        let system = try makeSystem()
        let location = CGPoint(x: -480, y: 220)
        system.hitTestError = GestureTargetError.axOperationFailed(
            operation: .hitTest,
            code: .notImplemented
        )
        system.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: system.application.processIdentifier,
            bounds: CGRect(x: -700, y: 100, width: 640, height: 480)
        )

        let snapshot = MacGestureTargetCapturer(system: system).captureIdentity(
            policies: [.windowUnderPointer],
            at: location
        )
        let context = try snapshot.windowUnderPointer.requireContext()

        XCTAssertEqual(context.bundleIdentifier, system.application.bundleIdentifier)
        XCTAssertEqual(context.processIdentifier, system.application.processIdentifier)
        XCTAssertNil(context.window)
        XCTAssertEqual(system.hitTestLocations, [location])
        XCTAssertEqual(system.pointerWindowLocations, [location])
        XCTAssertTrue(system.applicationWindowLookups.isEmpty)
    }

    func testHitTestNotImplementedFreezesUniqueMatchingAXWindow() throws {
        let system = try makeSystem()
        let location = CGPoint(x: 250, y: 180)
        let bounds = CGRect(x: 100, y: 80, width: 500, height: 360)
        system.hitTestError = GestureTargetError.axOperationFailed(
            operation: .hitTest,
            code: .notImplemented
        )
        system.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: system.application.processIdentifier,
            bounds: bounds
        )
        system.applicationWindows = [system.windowElement]
        system.windowFrames = [bounds]

        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: location
        )
        let context = try snapshot.windowUnderPointer.requireContext()

        XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.windowElement))
        XCTAssertEqual(system.pointerWindowLocations, [location])
        XCTAssertEqual(system.applicationWindowLookups, [system.application.processIdentifier])
        XCTAssertEqual(system.attributeReads, [.copyRole, .copyPosition, .copySize])
        XCTAssertEqual(system.validatedWindows, [try XCTUnwrap(system.pointerWindow)])
    }

    func testHitTestFallbackRejectsDuplicateAXWindowGeometry() throws {
        let system = try makeSystem()
        let duplicate = AXUIElementCreateApplication(system.application.processIdentifier)
        let bounds = CGRect(x: 100, y: 80, width: 500, height: 360)
        system.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        system.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: system.application.processIdentifier,
            bounds: bounds
        )
        system.applicationWindows = [system.windowElement, duplicate]
        system.windowFrames = [bounds, bounds]

        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: 200, y: 200)
        )

        guard case .unavailable(.windowUnavailable) = snapshot.windowUnderPointer
        else { return XCTFail("Duplicate geometry must not choose an arbitrary AX window") }
    }

    func testHitTestFallbackReportsWindowUnavailableWhenWindowDisappears() throws {
        let system = try makeSystem()
        system.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        system.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: system.application.processIdentifier,
            bounds: CGRect(x: 100, y: 80, width: 500, height: 360)
        )

        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: 200, y: 200)
        )

        guard case .unavailable(.windowUnavailable) = snapshot.windowUnderPointer
        else { return XCTFail("A vanished window must remain unavailable") }
    }

    func testHitTestFallbackRequiresMatchingPIDAndWindowRole() throws {
        let bounds = CGRect(x: 100, y: 80, width: 500, height: 360)
        let wrongPIDSystem = try makeSystem()
        wrongPIDSystem.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        wrongPIDSystem.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: wrongPIDSystem.application.processIdentifier,
            bounds: bounds
        )
        wrongPIDSystem.applicationWindows = [wrongPIDSystem.windowElement]
        wrongPIDSystem.windowFrames = [bounds]
        wrongPIDSystem.windowProcessIdentifier = wrongPIDSystem.application.processIdentifier + 1

        let wrongPID = MacGestureTargetCapturer(system: wrongPIDSystem).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: 200, y: 200)
        )
        guard case .unavailable(.processMismatch) = wrongPID.windowUnderPointer
        else { return XCTFail("A mismatched AX window PID must fail") }

        let wrongRoleSystem = try makeSystem()
        wrongRoleSystem.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        wrongRoleSystem.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: wrongRoleSystem.application.processIdentifier,
            bounds: bounds
        )
        wrongRoleSystem.applicationWindows = [wrongRoleSystem.windowElement]
        wrongRoleSystem.windowFrames = [bounds]
        wrongRoleSystem.role = "AXScrollArea"

        let wrongRole = MacGestureTargetCapturer(system: wrongRoleSystem).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: 200, y: 200)
        )
        guard case .unavailable(.windowRoleMismatch) = wrongRole.windowUnderPointer
        else { return XCTFail("A non-window AX role must fail") }
    }

    func testHitTestFallbackRequiresExactStandardizedGeometry() throws {
        let bounds = CGRect(x: -640, y: -120, width: 500, height: 360)
        let exact = try makeSystem()
        exact.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        exact.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: exact.application.processIdentifier,
            bounds: bounds
        )
        exact.applicationWindows = [exact.windowElement]
        exact.windowFrames = [CGRect(x: -140, y: 240, width: -500, height: -360)]
        let matched = MacGestureTargetCapturer(system: exact).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: -500, y: 0)
        )
        XCTAssertNotNil(try matched.windowUnderPointer.requireContext().window)

        let shifted = try makeSystem()
        shifted.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        shifted.pointerWindow = GestureTargetWindowDescriptor(
            processIdentifier: shifted.application.processIdentifier,
            bounds: bounds
        )
        shifted.applicationWindows = [shifted.windowElement]
        shifted.windowFrames = [bounds.offsetBy(dx: 0.01, dy: 0)]
        let rejected = MacGestureTargetCapturer(system: shifted).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: -500, y: 0)
        )
        guard case .unavailable(.windowUnavailable) = rejected.windowUnderPointer
        else { return XCTFail("Any geometry difference must fail") }
    }

    func testHitTestFallbackRevalidatesCGWindowAfterMatchingAXWindow() throws {
        let system = try makeSystem()
        let descriptor = GestureTargetWindowDescriptor(
            windowNumber: 42,
            processIdentifier: system.application.processIdentifier,
            bounds: CGRect(x: 100, y: 80, width: 500, height: 360)
        )
        system.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: .notImplemented)
        system.pointerWindow = descriptor
        system.applicationWindows = [system.windowElement]
        system.windowFrames = [descriptor.bounds]
        system.validationError = GestureTargetError.windowUnavailable

        let snapshot = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer],
            at: CGPoint(x: 200, y: 200)
        )

        guard case .unavailable(.windowUnavailable) = snapshot.windowUnderPointer
        else { return XCTFail("A changed or vanished CG window must fail") }
        XCTAssertEqual(system.validatedWindows, [descriptor])
    }

    func testOnlyHitTestNotImplementedUsesPointerWindowFallback() throws {
        for errorCode in [AXError.cannotComplete, .apiDisabled] {
            let system = try makeSystem()
            system.hitTestError = GestureTargetError.axOperationFailed(operation: .hitTest, code: errorCode)
            system.pointerWindow = GestureTargetWindowDescriptor(
                processIdentifier: system.application.processIdentifier,
                bounds: CGRect(x: 0, y: 0, width: 500, height: 360)
            )

            let snapshot = MacGestureTargetCapturer(system: system).capture(
                policies: [.windowUnderPointer],
                at: CGPoint(x: 200, y: 200)
            )

            guard case .unavailable(.axOperationFailed(.hitTest, let actualCode)) =
                snapshot.windowUnderPointer
            else { return XCTFail("Expected the original hit-test failure") }
            XCTAssertEqual(actualCode, errorCode)
            XCTAssertTrue(system.pointerWindowLocations.isEmpty)
            XCTAssertTrue(system.applicationWindowLookups.isEmpty)
        }
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

    func testMissingContainingWindowUsesSamePIDParentWindow() throws {
        for code in [AXError.noValue, .attributeUnsupported] {
            let system = try makeSystem()
            system.containingWindowError = GestureTargetError.axOperationFailed(
                operation: .copyContainingWindow, code: code
            )
            system.hitRole = "AXButton"
            system.parentChain = [system.hitElement, system.windowElement]
            let context = try MacGestureTargetCapturer(system: system).capture(
                policies: [.windowUnderPointer], at: .zero
            ).windowUnderPointer.requireContext()
            XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.windowElement))
            XCTAssertTrue(system.applicationWindowLookups.isEmpty)
            XCTAssertTrue(system.pointerWindowLocations.isEmpty)
        }
    }

    func testMissingContainingWindowTraversesDeepEditorHierarchy() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow, code: .attributeUnsupported
        )
        let groups = (0..<6).map { AXUIElementCreateApplication(Int32($0) + 10) }
        system.parentChain = [system.hitElement] + groups + [system.windowElement]
        system.parentRoles = ["AXSplitGroup"] + Array(repeating: "AXGroup", count: 6) + ["AXWindow"]
        let context = try MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer], at: .zero
        ).windowUnderPointer.requireContext()
        XCTAssertTrue(CFEqual(try XCTUnwrap(context.window).element, system.windowElement))
        XCTAssertEqual(system.attributeReads.filter { $0 == .copyParent }.count, 7)
    }

    func testApplicationAncestorKeepsDesktopWindowless() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow, code: .attributeUnsupported
        )
        system.parentChain = [system.hitElement, system.windowElement]
        system.parentRoles = ["AXScrollArea", "AXApplication"]
        let context = try MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer], at: .zero
        ).windowUnderPointer.requireContext()
        XCTAssertNil(context.window)
        XCTAssertEqual(system.attributeReads.filter { $0 == .copyParent }.count, 1)
    }

    func testExcessiveParentDepthFailsExplicitly() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow, code: .attributeUnsupported
        )
        system.parentChain = [system.hitElement] + (0..<33).map { AXUIElementCreateApplication(Int32($0) + 10) }
        system.parentRoles = Array(repeating: "AXGroup", count: system.parentChain.count)
        let result = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer], at: .zero
        ).windowUnderPointer
        guard case .unavailable(.unexpectedCaptureFailure) = result
        else { return XCTFail("Excessive parent depth is not a windowless target") }
    }

    func testParentTraversalPropagatesAXFailures() throws {
        for code in [AXError.cannotComplete, .apiDisabled, .invalidUIElement] {
            let system = try makeSystem()
            system.containingWindowError = GestureTargetError.axOperationFailed(
                operation: .copyContainingWindow, code: .attributeUnsupported
            )
            system.hitRole = "AXButton"
            system.parentError = GestureTargetError.axOperationFailed(operation: .copyParent, code: code)
            let result = MacGestureTargetCapturer(system: system).capture(
                policies: [.windowUnderPointer], at: .zero
            ).windowUnderPointer
            guard case .unavailable(.axOperationFailed(.copyParent, let actual)) = result
            else { return XCTFail("Parent failures must remain observable") }
            XCTAssertEqual(actual, code)
        }
    }

    func testParentWindowPIDMismatchIsRejected() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow, code: .attributeUnsupported
        )
        system.hitRole = "AXButton"
        system.parentChain = [system.hitElement, system.windowElement]
        system.windowProcessIdentifier = system.application.processIdentifier + 1
        let result = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer], at: .zero
        ).windowUnderPointer
        guard case .unavailable(.processMismatch) = result
        else { return XCTFail("Cross-process parent must not retarget") }
    }

    func testParentCycleFailsExplicitly() throws {
        let system = try makeSystem()
        system.containingWindowError = GestureTargetError.axOperationFailed(
            operation: .copyContainingWindow, code: .attributeUnsupported
        )
        system.hitRole = "AXButton"
        system.parentChain = [system.hitElement, system.hitElement]
        let result = MacGestureTargetCapturer(system: system).capture(
            policies: [.windowUnderPointer], at: .zero
        ).windowUnderPointer
        guard case .unavailable(.unexpectedCaptureFailure) = result
        else { return XCTFail("A cyclic parent chain is not a windowless target") }
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

    func testIdentityCaptureDoesNotCopyAnAXWindow() throws {
        let system = try makeSystem()
        let capturer = MacGestureTargetCapturer(system: system)
        let location = CGPoint(x: 12, y: 34)

        let frontmost = capturer.captureIdentity(
            policies: [.frontmostWindow],
            at: location
        )
        let frontmostContext = try frontmost.frontmostWindow.requireContext()
        XCTAssertEqual(frontmostContext.bundleIdentifier, system.application.bundleIdentifier)
        XCTAssertNil(frontmostContext.window)
        XCTAssertTrue(system.hitTestLocations.isEmpty)
        XCTAssertTrue(system.attributeReads.isEmpty)
        guard case .unavailable(.targetNotCaptured(.windowUnderPointer)) = frontmost.windowUnderPointer
        else { return XCTFail("Unrequested pointer target should stay uncaptured") }

        let pointer = capturer.captureIdentity(
            policies: [.windowUnderPointer],
            at: location
        )
        let pointerContext = try pointer.windowUnderPointer.requireContext()
        XCTAssertEqual(system.hitTestLocations, [location])
        XCTAssertNil(pointerContext.window)
        XCTAssertEqual(pointerContext.processIdentifier, system.application.processIdentifier)
        XCTAssertTrue(system.attributeReads.isEmpty)
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

private final class RecordingGestureTargetCaptureSystemClient:
    GestureTargetCaptureSystemClient,
    @unchecked Sendable
{
    let application: NSRunningApplication
    let hitElement: AXUIElement
    let windowElement: AXUIElement

    var role = kAXWindowRole as String
    var hitRole: String?
    var parentChain: [AXUIElement] = []
    var parentRoles: [String] = []
    var parentError: Error?
    var hitTestError: Error?
    var focusedWindowError: Error?
    var containingWindowError: Error?
    var pointerWindow: GestureTargetWindowDescriptor?
    var applicationWindows: [AXUIElement] = []
    var windowFrames: [CGRect] = []
    var validationError: Error?
    var windowProcessIdentifier: pid_t?
    private(set) var hitTestLocations: [CGPoint] = []
    private(set) var pointerWindowLocations: [CGPoint] = []
    private(set) var applicationWindowLookups: [pid_t] = []
    private(set) var validatedWindows: [GestureTargetWindowDescriptor] = []
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
        if let hitTestError { throw hitTestError }
        return hitElement
    }

    func windowUnderPointer(at quartzLocation: CGPoint) throws -> GestureTargetWindowDescriptor {
        pointerWindowLocations.append(quartzLocation)
        guard let pointerWindow else { throw GestureTargetError.noElementAtPointer }
        return pointerWindow
    }

    func validateWindow(_ descriptor: GestureTargetWindowDescriptor) throws {
        validatedWindows.append(descriptor)
        if let validationError { throw validationError }
    }

    func windows(processIdentifier: pid_t) throws -> [AXUIElement] {
        applicationWindowLookups.append(processIdentifier)
        return applicationWindows
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        guard let index = applicationWindows.firstIndex(where: { CFEqual($0, window) }),
              windowFrames.indices.contains(index)
        else { throw GestureTargetError.windowUnavailable }
        attributeReads.append(.copyPosition)
        attributeReads.append(.copySize)
        return windowFrames[index]
    }

    func copyElement(
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> AXUIElement {
        attributeReads.append(attribute.operation)
        switch attribute.operation {
        case .copyFocusedWindow:
            if let focusedWindowError { throw focusedWindowError }
            return windowElement
        case .copyParent:
            if let parentError { throw parentError }
            guard let index = parentChain.firstIndex(where: { CFEqual($0, element) }),
                  parentChain.indices.contains(index + 1)
            else { throw GestureTargetError.axOperationFailed(operation: .copyParent, code: .attributeUnsupported) }
            return parentChain[index + 1]
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
        from element: AXUIElement,
        attribute: GestureTargetAXAttribute
    ) throws -> String {
        attributeReads.append(attribute.operation)
        if let index = parentChain.firstIndex(where: { CFEqual($0, element) }),
           parentRoles.indices.contains(index) { return parentRoles[index] }
        return CFEqual(element, hitElement) ? (hitRole ?? role) : role
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
