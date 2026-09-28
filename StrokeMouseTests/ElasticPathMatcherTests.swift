import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class ElasticPathMatcherTests: XCTestCase {
    func testIdenticalPathHasZeroDistanceAndFullScore() throws {
        let profile = try XCTUnwrap(ElasticPathProfile(spiral))

        XCTAssertEqual(ElasticPathMatcher.distance(profile, profile), 0, accuracy: 1e-12)
        XCTAssertEqual(ElasticPathMatcher.score(distance: 0), 1)
    }

    func testProfileIgnoresTranslationScaleAndInputDensity() throws {
        let reference = try XCTUnwrap(ElasticPathProfile(spiral))
        let moved = spiral.map { CGPoint(x: $0.x * 3.5 + 400, y: $0.y * 3.5 - 250) }
        let denser = try XCTUnwrap(UnistrokeGeometry.resampledPath(spiral, count: 301))

        for variant in [moved, denser] {
            let profile = try XCTUnwrap(ElasticPathProfile(variant))
            XCTAssertLessThan(ElasticPathMatcher.distance(profile, reference), 0.002)
        }
    }

    func testReversedDirectionIsFarAway() throws {
        let forward = try XCTUnwrap(ElasticPathProfile(spiral))
        let reversed = try XCTUnwrap(ElasticPathProfile(Array(spiral.reversed())))

        XCTAssertLessThan(
            ElasticPathMatcher.score(distance: ElasticPathMatcher.distance(reversed, forward)),
            0.2
        )
    }

    func testLocalProportionChangeCostsLessThanOrderedComparison() throws {
        // The same shape drawn with a slower first half: arc length is
        // unchanged, but the warp lets matching features line up again.
        let template = try XCTUnwrap(ElasticPathProfile(spiral))
        let warped = try XCTUnwrap(ElasticPathProfile(spiralPoints { pow($0, 1.25) }))
        let proportioned = try XCTUnwrap(ElasticPathProfile(
            spiralPoints { $0 < 0.5 ? $0 * 0.8 : 0.4 + ($0 - 0.5) * 1.2 }
        ))

        XCTAssertLessThan(ElasticPathMatcher.distance(warped, template), 0.01)
        XCTAssertGreaterThan(
            ElasticPathMatcher.score(
                distance: ElasticPathMatcher.distance(proportioned, template)
            ),
            0.85
        )
    }

    func testAbandonedComparisonNeverHidesADistanceWithinTheLimit() throws {
        let template = try XCTUnwrap(ElasticPathProfile(spiral))
        let strokes = [
            spiral,
            Array(spiral.reversed()),
            spiralPoints { pow($0, 1.4) },
            (0..<30).map { CGPoint(x: $0.isMultiple(of: 2) ? -100 : 100, y: CGFloat($0) * 15) },
        ]
        for points in strokes {
            let stroke = try XCTUnwrap(ElasticPathProfile(points))
            let exact = ElasticPathMatcher.meanDistance(stroke, template)
            XCTAssertLessThanOrEqual(exact, ElasticPathMatcher.distance(stroke, template))
            for limit in [0.02, 0.08, 0.2, 0.6] {
                let bounded = ElasticPathMatcher.meanDistance(
                    stroke,
                    template,
                    abandonAbove: limit
                )
                if exact <= limit {
                    XCTAssertEqual(bounded, exact, accuracy: 1e-12)
                } else {
                    XCTAssertGreaterThan(bounded, limit)
                }
            }
        }
    }

    func testScoreDistanceConversionRoundTrips() {
        for score in [0.45, 0.6, 0.7, 0.85] {
            let distance = ElasticPathMatcher.maximumDistance(forScore: score)
            XCTAssertEqual(ElasticPathMatcher.score(distance: distance), score, accuracy: 1e-12)
        }
        XCTAssertEqual(ElasticPathMatcher.score(distance: .infinity), 0)
    }

    func testAspectNormalizationHasNoCliffAtTheRatioBoundary() throws {
        let template = try XCTUnwrap(ElasticPathProfile(arc(height: 100)))
        var previous: Double?
        for height in stride(from: CGFloat(10), through: 60, by: 1) {
            let stroke = try XCTUnwrap(ElasticPathProfile(arc(height: height)))
            let score = ElasticPathMatcher.score(
                distance: ElasticPathMatcher.distance(stroke, template)
            )
            if let previous {
                XCTAssertLessThan(abs(score - previous), 0.05, "height=\(height)")
            }
            previous = score
        }
    }

    func testDegenerateInputHasNoProfile() {
        XCTAssertNil(ElasticPathProfile([]))
        XCTAssertNil(ElasticPathProfile([.zero, .zero]))
        XCTAssertNil(ElasticPathProfile([.zero, CGPoint(x: CGFloat.nan, y: 1)]))
    }

    private var spiral: [CGPoint] { spiralPoints { $0 } }

    private func spiralPoints(_ progress: (CGFloat) -> CGFloat) -> [CGPoint] {
        (0..<120).map { index in
            let t = progress(CGFloat(index) / 119) * 3 * .pi
            let radius = 40 + t * 12
            return CGPoint(x: cos(t) * radius, y: sin(t) * radius)
        }
    }

    private func arc(height: CGFloat) -> [CGPoint] {
        (0..<80).map { index in
            let t = CGFloat(index) / 79 * .pi
            return CGPoint(x: -cos(t) * 100, y: sin(t) * height)
        }
    }
}
