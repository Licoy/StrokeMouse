import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class CurveAlignmentTests: XCTestCase {
    func testIdenticalPathHasZeroAlignedDistance() {
        let path = samplePath

        XCTAssertEqual(CurvePathSignature.alignedDistance(path, path), 0, accuracy: 1e-12)
    }

    func testUniformTranslationCostsExactlyItsDisplacement() {
        let offset = CGPoint(x: 0.012, y: -0.009)
        let translated = samplePath.map {
            CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)
        }

        XCTAssertEqual(
            CurvePathSignature.alignedDistance(samplePath, translated),
            hypot(Double(offset.x), Double(offset.y)),
            accuracy: 1e-12
        )
    }

    func testEndpointDifferencesCannotBeSkippedByOpenEndedAlignment() {
        var changedStart = samplePath
        changedStart[0].y += 0.2
        var changedEnd = samplePath
        changedEnd[changedEnd.count - 1].y -= 0.2

        XCTAssertGreaterThan(
            CurvePathSignature.alignedDistance(samplePath, changedStart),
            0
        )
        XCTAssertGreaterThan(
            CurvePathSignature.alignedDistance(samplePath, changedEnd),
            0
        )
    }

    func testAlignmentRejectsTooShortOrUnequalInputs() {
        XCTAssertTrue(
            CurvePathSignature.alignedDistance(
                Array(samplePath.prefix(8)),
                Array(samplePath.prefix(8))
            ).isInfinite
        )
        XCTAssertTrue(
            CurvePathSignature.alignedDistance(samplePath, Array(samplePath.dropLast()))
                .isInfinite
        )
    }

    private var samplePath: [CGPoint] {
        (0..<17).map { index in
            let x = CGFloat(index) * 0.08
            return CGPoint(x: x, y: sin(x * 2.1) * 0.3 + x * 0.17)
        }
    }
}
