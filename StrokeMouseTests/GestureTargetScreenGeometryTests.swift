import XCTest
@testable import StrokeMouse

final class GestureTargetScreenGeometryTests: XCTestCase {
    func testSelectsSecondaryScreenAndCentersUsingQuartzCoordinates() throws {
        let primary = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let secondary = CGRect(x: 1_440, y: -180, width: 1_920, height: 1_080)
        let secondaryVisible = CGRect(x: 1_440, y: -180, width: 1_920, height: 1_040)
        let size = CGSize(width: 800, height: 500)
        let frame = GestureTargetScreenGeometry.appKitWindowFrame(
            axOrigin: CGPoint(x: 1_800, y: 200),
            windowSize: size,
            zeroScreenFrame: primary
        )

        XCTAssertEqual(frame, CGRect(x: 1_800, y: 200, width: 800, height: 500))
        let index = try XCTUnwrap(
            GestureTargetScreenGeometry.targetScreenIndex(
                for: frame,
                screenFrames: [primary, secondary]
            )
        )
        XCTAssertEqual(index, 1)

        let centered = GestureTargetScreenGeometry.centeredAXOrigin(
            windowSize: size,
            visibleFrame: secondaryVisible,
            zeroScreenFrame: primary
        )
        XCTAssertEqual(centered.x, 2_000, accuracy: 0.001)
        XCTAssertEqual(centered.y, 310, accuracy: 0.001)
    }

    func testChoosesGreatestOverlapThenNearestScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let secondary = CGRect(x: 1_000, y: 0, width: 1_000, height: 800)

        XCTAssertEqual(
            GestureTargetScreenGeometry.targetScreenIndex(
                for: CGRect(x: 850, y: 100, width: 400, height: 400),
                screenFrames: [primary, secondary]
            ),
            1
        )
        XCTAssertEqual(
            GestureTargetScreenGeometry.targetScreenIndex(
                for: CGRect(x: 2_200, y: 100, width: 100, height: 100),
                screenFrames: [primary, secondary]
            ),
            1
        )
        XCTAssertNil(
            GestureTargetScreenGeometry.targetScreenIndex(
                for: .zero,
                screenFrames: []
            )
        )
    }
}
