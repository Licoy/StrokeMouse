import ApplicationServices
import XCTest
@testable import StrokeMouse

final class GestureTargetWindowLocatorTests: XCTestCase {
    private let display = CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080)

    func testSelectsFrontmostNormalWindowWithNegativeQuartzCoordinates() throws {
        let front = window(id: 2, pid: 22, bounds: CGRect(x: -900, y: -100, width: 600, height: 500))
        let back = window(id: 1, pid: 11, bounds: CGRect(x: -1_000, y: -120, width: 800, height: 600))

        let selected = try GestureTargetWindowLocator.locate(
            at: CGPoint(x: -500, y: 100),
            windows: [front, back],
            displayBounds: [display],
            dockWindowLevel: 20,
            dockCarrierDoesNotHit: { _ in XCTFail("Normal windows need no Dock probe"); return false }
        )

        XCTAssertEqual(selected, front.descriptor)
    }

    func testUnknownNonzeroLayerBlocksNormalWindowBehindIt() {
        let overlay = window(id: 3, pid: 33, layer: 8, bounds: display, bundle: "com.example.overlay")
        let normal = window(id: 2, pid: 22, bounds: display)

        XCTAssertThrowsError(
            try GestureTargetWindowLocator.locate(
                at: CGPoint(x: -500, y: 100),
                windows: [overlay, normal],
                displayBounds: [display],
                dockWindowLevel: 20,
                dockCarrierDoesNotHit: { _ in true }
            )
        ) { error in
            guard case GestureTargetError.windowUnavailable = error
            else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testSkipsOnlyVerifiedFullDisplayDockCarrier() throws {
        let dock = window(
            id: 3,
            pid: 33,
            layer: 20,
            bounds: display,
            bundle: "com.apple.dock"
        )
        let normal = window(id: 2, pid: 22, bounds: display)
        var probed: [GestureTargetVisibleWindow] = []

        let selected = try GestureTargetWindowLocator.locate(
            at: CGPoint(x: -500, y: 100),
            windows: [dock, normal],
            displayBounds: [display],
            dockWindowLevel: 20
        ) { window in
            probed.append(window)
            return true
        }

        XCTAssertEqual(selected, normal.descriptor)
        XCTAssertEqual(probed, [dock])
    }

    func testRejectsEveryIncompleteDockCarrierConditionWithoutProbing() {
        let normal = window(id: 2, pid: 22, bounds: display)
        let invalidCarriers = [
            window(id: 3, pid: 33, layer: 20, bounds: display, bundle: nil),
            window(id: 3, pid: 33, layer: 20, bounds: display, bundle: "com.example.overlay"),
            window(id: 3, pid: 33, layer: 21, bounds: display, bundle: "com.apple.dock"),
            window(
                id: 3,
                pid: 33,
                layer: 20,
                bounds: display.insetBy(dx: 10, dy: 10),
                bundle: "com.apple.dock"
            ),
        ]

        for carrier in invalidCarriers {
            var probed = false
            XCTAssertThrowsError(
                try GestureTargetWindowLocator.locate(
                    at: CGPoint(x: -500, y: 100),
                    windows: [carrier, normal],
                    displayBounds: [display],
                    dockWindowLevel: 20,
                    dockCarrierDoesNotHit: { _ in probed = true; return true }
                )
            )
            XCTAssertFalse(probed)
        }
    }

    func testDockCarrierThatHitsOrCannotCompleteDoesNotExposeWindowBehindIt() {
        let dock = window(id: 3, pid: 33, layer: 20, bounds: display, bundle: "com.apple.dock")
        let normal = window(id: 2, pid: 22, bounds: display)

        XCTAssertThrowsError(
            try GestureTargetWindowLocator.locate(
                at: CGPoint(x: -500, y: 100),
                windows: [dock, normal],
                displayBounds: [display],
                dockWindowLevel: 20,
                dockCarrierDoesNotHit: { _ in false }
            )
        )
        XCTAssertThrowsError(
            try GestureTargetWindowLocator.locate(
                at: CGPoint(x: -500, y: 100),
                windows: [dock, normal],
                displayBounds: [display],
                dockWindowLevel: 20,
                dockCarrierDoesNotHit: { _ in
                    throw GestureTargetError.axOperationFailed(
                        operation: .hitTest,
                        code: .cannotComplete
                    )
                }
            )
        ) { error in
            guard case GestureTargetError.axOperationFailed(.hitTest, .cannotComplete) = error
            else { return XCTFail("Expected Dock AX error propagation") }
        }
    }

    func testFullyTransparentUnknownLayerStillBlocksNormalWindow() {
        let transparent = window(
            id: 3,
            pid: 33,
            layer: 8,
            bounds: display,
            alpha: 0,
            bundle: "com.example.overlay"
        )
        let normal = window(id: 2, pid: 22, bounds: display)

        XCTAssertThrowsError(
            try GestureTargetWindowLocator.locate(
                at: CGPoint(x: -500, y: 100),
                windows: [transparent, normal],
                displayBounds: [display],
                dockWindowLevel: 20,
                dockCarrierDoesNotHit: { _ in false }
            )
        )
    }

    func testStrictlyParsesRequiredCGWindowFields() throws {
        let valid: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: UInt32(42)),
            kCGWindowOwnerPID as String: NSNumber(value: Int32(123)),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowAlpha as String: NSNumber(value: 1.0),
            kCGWindowBounds as String: display.dictionaryRepresentation,
        ]
        let parsed = try GestureTargetWindowLocator.parse([valid]) { pid in
            pid == 123 ? "com.example.app" : nil
        }
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].descriptor.windowNumber, 42)
        XCTAssertEqual(parsed[0].descriptor.processIdentifier, 123)
        XCTAssertEqual(parsed[0].descriptor.bounds, display)
        XCTAssertEqual(parsed[0].ownerBundleIdentifier, "com.example.app")

        for key in [kCGWindowNumber, kCGWindowOwnerPID, kCGWindowLayer,
                    kCGWindowAlpha, kCGWindowBounds]
        {
            var invalid = valid
            invalid.removeValue(forKey: key as String)
            XCTAssertThrowsError(try GestureTargetWindowLocator.parse([invalid]) { _ in nil })
        }

        for invalidValue: Any in [NSNumber(value: 0), NSNumber(value: 1.5), "42"] {
            var invalid = valid
            invalid[kCGWindowNumber as String] = invalidValue
            XCTAssertThrowsError(try GestureTargetWindowLocator.parse([invalid]) { _ in nil })
        }
        var invalidPID = valid
        invalidPID[kCGWindowOwnerPID as String] = NSNumber(value: -1)
        XCTAssertThrowsError(try GestureTargetWindowLocator.parse([invalidPID]) { _ in nil })

        var zeroSize = valid
        zeroSize[kCGWindowBounds as String] = CGRect.zero.dictionaryRepresentation
        XCTAssertNoThrow(try GestureTargetWindowLocator.parse([zeroSize]) { _ in nil })
    }

    private func window(
        id: CGWindowID,
        pid: pid_t,
        layer: Int = 0,
        bounds: CGRect,
        alpha: CGFloat = 1,
        bundle: String? = "com.example.app"
    ) -> GestureTargetVisibleWindow {
        GestureTargetVisibleWindow(
            descriptor: GestureTargetWindowDescriptor(
                windowNumber: id,
                processIdentifier: pid,
                layer: layer,
                bounds: bounds
            ),
            alpha: alpha,
            ownerBundleIdentifier: bundle
        )
    }
}
