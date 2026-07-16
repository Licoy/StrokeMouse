import CoreGraphics
import XCTest
@testable import StrokeMouse

final class GesturePreviewGeometryTests: XCTestCase {
    func testAspectFitPreservesPathRatioAndCentersInCanvas() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 1)]
        let fitted = GesturePreviewGeometry.aspectFit(
            points: points,
            in: CGSize(width: 400, height: 240),
            padding: 16
        )

        XCTAssertEqual(fitted[0].x, 148, accuracy: 0.001)
        XCTAssertEqual(fitted[0].y, 224, accuracy: 0.001)
        XCTAssertEqual(fitted[1].x, 252, accuracy: 0.001)
        XCTAssertEqual(fitted[1].y, 16, accuracy: 0.001)
    }
}
