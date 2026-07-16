import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class RecordedGestureRegressionTests: XCTestCase {
    func testAllNineteenRecordedRedrawsUseCanonicalMatchingAboveNinetyPercent() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.strokes.count, 19)

        var scores: [Double] = []
        var rawScores: [Double] = []
        for (index, stroke) in fixture.strokes.enumerated() {
            let evaluation = TemplateMatcher.evaluate(stroke.cgPoints, fixture.template.cgPoints)
            scores.append(evaluation.score)
            rawScores.append(evaluation.shapeScore)
            XCTAssertNil(evaluation.structuralMismatch, "stroke=\(index + 1)")
            XCTAssertEqual(
                evaluation.diagnostics?.mode?.rawValue,
                TemplateMatcher.MatchingMode.simpleSegmentCanonical.rawValue,
                "stroke=\(index + 1)"
            )
            XCTAssertGreaterThanOrEqual(
                evaluation.score,
                0.90,
                "stroke=\(index + 1), raw=\(evaluation.shapeScore)"
            )
            XCTAssertEqual(
                TemplateMatcher.bestScore(stroke.cgPoints, fixture.template.cgPoints),
                evaluation.score,
                accuracy: 1e-12
            )
        }

        let minimumScore = scores.min() ?? 0
        let maximumScore = scores.max() ?? 0
        print("Recorded canonical score range: \(minimumScore)...\(maximumScore)")
        XCTAssertGreaterThanOrEqual(minimumScore, 0.90)
        XCTAssertLessThan(rawScores.min() ?? 1, Constants.freePathMatchThreshold)
    }

    func testWorstThreePointReproductionClearsFormalThreshold() throws {
        let fixture = try loadFixture()
        let reproduction = [
            CGPoint(x: 172.621, y: 164.223),
            CGPoint(x: 197.477, y: 249.500),
            CGPoint(x: 217.586, y: 188.938),
        ]

        let evaluation = TemplateMatcher.evaluate(reproduction, fixture.template.cgPoints)

        XCTAssertNil(evaluation.structuralMismatch)
        XCTAssertGreaterThanOrEqual(evaluation.score, Constants.freePathMatchThreshold)
    }

    func testEveryRecordedRedrawRejectsFifteenThirtyAndSeventyPercentTails() throws {
        let fixture = try loadFixture()
        for (index, stroke) in fixture.strokes.enumerated() {
            for fraction in [CGFloat(0.15), 0.30, 0.70] {
                let tailed = appendingTail(to: stroke.cgPoints, fraction: fraction)
                let evaluation = TemplateMatcher.evaluate(tailed, fixture.template.cgPoints)
                XCTAssertEqual(
                    evaluation.score,
                    0,
                    "stroke=\(index + 1), tail=\(fraction), mismatch="
                        + "\(String(describing: evaluation.structuralMismatch))"
                )
            }
        }
    }

    func testUnsafeSegmentLengthRatioIsASeparateStructuralRejection() {
        let template = polyline([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.4, y: 1),
            CGPoint(x: 1, y: 0),
        ])
        let truncated = polyline([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.4, y: 1),
            CGPoint(x: 0.52, y: 0.8),
        ])

        let evaluation = TemplateMatcher.evaluate(truncated, template)

        XCTAssertEqual(evaluation.structuralMismatch, .segmentProportion)
        XCTAssertEqual(evaluation.score, 0)
        XCTAssertGreaterThan(evaluation.shapeScore, 0)
    }

    func testSafeSegmentProportionSweepStaysContinuousAtBothEnds() {
        let start = CGPoint(x: 0, y: 0)
        let apex = CGPoint(x: 0.5, y: 1)
        let leg = CGPoint(x: 0.5, y: -1)
        let template = polyline([start, apex, CGPoint(x: 1, y: 0)])
        var previousScore: Double?

        for factor in stride(from: CGFloat(0.4), through: 2.8, by: 0.1) {
            let endpoint = CGPoint(x: apex.x + leg.x * factor, y: apex.y + leg.y * factor)
            let evaluation = TemplateMatcher.evaluate(
                polyline([start, apex, endpoint]),
                template
            )
            XCTAssertNil(evaluation.structuralMismatch, "factor=\(factor)")
            XCTAssertGreaterThanOrEqual(
                evaluation.score,
                Constants.freePathMatchThreshold,
                "factor=\(factor)"
            )
            if let previousScore {
                XCTAssertLessThan(abs(evaluation.score - previousScore), 0.08, "factor=\(factor)")
            }
            previousScore = evaluation.score
        }

        for factor in [CGFloat(0.2), 4.0] {
            let endpoint = CGPoint(x: apex.x + leg.x * factor, y: apex.y + leg.y * factor)
            XCTAssertEqual(
                TemplateMatcher.evaluate(polyline([start, apex, endpoint]), template)
                    .structuralMismatch,
                .segmentProportion,
                "factor=\(factor)"
            )
        }
    }

    private func loadFixture() throws -> RecordedGestureFixture {
        let url = try XCTUnwrap(
            Bundle(for: RecordedGestureRegressionTests.self).url(
                forResource: "RecordedPeakGestureFixture",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            RecordedGestureFixture.self,
            from: Data(contentsOf: url)
        )
    }

    private func appendingTail(to points: [CGPoint], fraction: CGFloat) -> [CGPoint] {
        guard let endpoint = points.last else { return points }
        let length = PathSimplifier.pathLength(points) * fraction
        let tail = (1...12).map { index in
            CGPoint(
                x: endpoint.x + length * CGFloat(index) / 12,
                y: endpoint.y
            )
        }
        return points + tail
    }

    private func polyline(_ vertices: [CGPoint], samplesPerSegment: Int = 20) -> [CGPoint] {
        guard let first = vertices.first else { return [] }
        return [first] + zip(vertices, vertices.dropFirst()).flatMap { start, end in
            (1...samplesPerSegment).map { index in
                let progress = CGFloat(index) / CGFloat(samplesPerSegment)
                return CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
            }
        }
    }
}

private struct RecordedGestureFixture: Decodable {
    let template: [RecordedGesturePoint]
    let strokes: [[RecordedGesturePoint]]
}

private struct RecordedGesturePoint: Decodable {
    let x: CGFloat
    let y: CGFloat
}

private extension Array where Element == RecordedGesturePoint {
    var cgPoints: [CGPoint] { map { CGPoint(x: $0.x, y: $0.y) } }
}
