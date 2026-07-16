import CoreGraphics
import XCTest
@testable import StrokeMouse

final class PathSimplifierTests: XCTestCase {
    func testPathLengthStraightLine() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 40)]
        XCTAssertEqual(PathSimplifier.pathLength(points), 50, accuracy: 0.001)
    }

    func testNormalizeFitsUnitSquare() {
        let points = [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 70)]
        let normalized = PathSimplifier.normalize(points)
        XCTAssertEqual(normalized.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(normalized.first?.y ?? -1, 0, accuracy: 0.001)
        let maxCoord = normalized.map { max($0.x, $0.y) }.max() ?? 0
        XCTAssertEqual(maxCoord, 1, accuracy: 0.001)
    }

    func testResampleCount() {
        let points = (0..<10).map { CGPoint(x: CGFloat($0), y: 0) }
        let resampled = PathSimplifier.resample(points, count: 32)
        XCTAssertEqual(resampled.count, 32)
    }

    func testSimplifyRemovesColinearMiddlePoints() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 3, y: 0),
        ]
        let simplified = PathSimplifier.simplify(points, epsilon: 0.1)
        XCTAssertEqual(simplified.count, 2)
    }
}
