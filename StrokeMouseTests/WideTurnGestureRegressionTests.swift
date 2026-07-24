import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class WideTurnGestureRegressionTests: XCTestCase {
    func testRecordedWideTurnRedrawsMeetDefaultRecallTargetWithoutSegmentCountRejections() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.strokes.count, 22)
        XCTAssertEqual(fixture.templateSegments.count, 4)

        let evaluations = fixture.strokes.map {
            TemplateMatcher.evaluate($0.cgPoints, fixture.template.cgPoints)
        }
        let accepted = evaluations.filter {
            $0.score >= Constants.freePathMatchThreshold
        }.count
        let acceptedAtSixtyFivePercent = evaluations.filter {
            $0.score >= 0.65
        }.count
        let segmentCountRejections = evaluations.filter {
            $0.structuralMismatch == .segmentCount
        }.count

        XCTAssertGreaterThanOrEqual(accepted, 21)
        XCTAssertEqual(acceptedAtSixtyFivePercent, 22)
        XCTAssertEqual(segmentCountRejections, 0)
    }

    func testWideTurnScoresStayContinuousAcrossTwoThroughSixSegments() throws {
        let fixture = try loadFixture()
        let startAngle = try XCTUnwrap(fixture.templateSegments.first?.angleDegrees)
        let endAngle = try XCTUnwrap(fixture.templateSegments.last?.angleDegrees)
        let evaluations = (2...6).map { count in
            let angles = (0..<count).map { index in
                startAngle + (endAngle - startAngle)
                    * Double(index) / Double(count - 1)
            }
            return TemplateMatcher.evaluate(
                polyline(angles: angles),
                fixture.template.cgPoints
            )
        }

        XCTAssertEqual(
            evaluations.map { $0.diagnostics?.strokeSegments.count },
            (2...6).map(Optional.some)
        )
        for evaluation in evaluations {
            XCTAssertEqual(evaluation.diagnostics?.mode, .singleTurnCanonical)
            XCTAssertGreaterThanOrEqual(evaluation.score, Constants.freePathMatchThreshold)
        }
        let scores = evaluations.map(\.score)
        let adjacentDifferences = zip(scores, scores.dropFirst()).map {
            abs($0 - $1)
        }
        XCTAssertLessThan(
            adjacentDifferences.max() ?? 1,
            0.04,
            "scores=\(scores)"
        )
    }

    func testLenientPolicyAcceptsTheRecordedDefaultThresholdNearMiss() throws {
        let fixture = try loadFixture()
        let profile = GestureProfile(
            name: "Wide turn",
            pattern: .freePath(fixture.template.cgPoints.map(CodablePoint.init))
        )
        let stroke = try XCTUnwrap(fixture.strokes[safe: 15]?.cgPoints)
        let strict = GestureRecognitionEvaluator.evaluate(
            path: stroke,
            profiles: [profile],
            button: .right,
            policy: policy(threshold: 0.70)
        )
        let lenient = GestureRecognitionEvaluator.evaluate(
            path: stroke,
            profiles: [profile],
            button: .right,
            policy: policy(threshold: 0.65)
        )

        XCTAssertEqual(strict.decision, .belowThreshold)
        XCTAssertEqual(lenient.decision, .accepted)
    }

    func testMinimumThresholdStillRejectsUnsafeWideTurnVariants() throws {
        let fixture = try loadFixture()
        let template = fixture.template.cgPoints
        let start = try XCTUnwrap(template.first)
        let mirrored = template.map {
            CGPoint(x: start.x - ($0.x - start.x), y: $0.y)
        }
        let truncated = Array(template.prefix(max(2, template.count / 3)))
        let prepended = [
            CGPoint(x: start.x + 80, y: start.y),
            start,
        ] + Array(template.dropFirst())
        let multiTurn = polyline(angles: [-80, -20, -65, 55])
        let variants = [
            ("mirrored", mirrored),
            ("reversed", Array(template.reversed())),
            ("truncated", truncated),
            ("prepended", prepended),
            ("multi-turn", multiTurn),
        ] + [CGFloat(0.15), 0.30, 0.70].map { fraction in
            (
                "tail-\(fraction)",
                GestureRecognitionTestSupport.appendingTail(
                    to: template,
                    lengthFraction: fraction,
                    angleDegrees: 90
                )
            )
        }

        for (name, variant) in variants {
            let evaluation = TemplateMatcher.evaluate(variant, template)
            XCTAssertLessThan(
                evaluation.score,
                Constants.freePathMatchThresholdRange.lowerBound,
                "\(name): \(evaluation)"
            )
        }
    }

    func testOverOneHundredFiftyDegreeTurnKeepsStrictSegmentCount() {
        let template = polyline(angles: [-80, 0, 80])
        let redraw = polyline(angles: [-80, -27, 27, 80])
        let evaluation = TemplateMatcher.evaluate(redraw, template)

        XCTAssertEqual(evaluation.structuralMismatch, .segmentCount)
        XCTAssertEqual(evaluation.score, 0)
    }

    func testTwoThousandWideTurnTailsHaveNoMatchesAtMinimumThreshold() throws {
        let fixture = try loadFixture()
        var falseMatches = 0
        for index in 0..<2_000 {
            let stroke = fixture.strokes[index % fixture.strokes.count].cgPoints
            let fraction = CGFloat(15 + (index * 17) % 56) / 100
            let angle = CGFloat(60 + (index * 37) % 91)
            let tailed = GestureRecognitionTestSupport.appendingTail(
                to: stroke,
                lengthFraction: fraction,
                angleDegrees: angle
            )
            if TemplateMatcher.bestScore(tailed, fixture.template.cgPoints)
                >= Constants.freePathMatchThresholdRange.lowerBound {
                falseMatches += 1
            }
        }

        XCTAssertEqual(falseMatches, 0)
    }

    func testSimilarWideTurnCandidatesRemainAmbiguousAtMinimumThreshold() throws {
        let template = try loadFixture().template.cgPoints
        let rotated = GestureRecognitionTestSupport.rotate(template, degrees: 2)
        let profiles = [
            GestureProfile(name: "First", pattern: .freePath(template.map(CodablePoint.init))),
            GestureProfile(name: "Second", pattern: .freePath(rotated.map(CodablePoint.init))),
        ]
        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: profiles,
            button: .right,
            policy: policy(threshold: Constants.freePathMatchThresholdRange.lowerBound)
        )

        XCTAssertEqual(result.decision, .ambiguous)
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertLessThan(
            result.candidates[0].score - result.candidates[1].score,
            Constants.freePathMinLeadOverSecond
        )
    }

    private func policy(threshold: Double) -> GestureRecognitionPolicy {
        GestureRecognitionPolicy(
            minimumPathLength: 0,
            matchThreshold: threshold,
            minimumLeadOverSecond: Constants.freePathMinLeadOverSecond
        )
    }

    private func loadFixture() throws -> WideTurnGestureFixture {
        let url = try XCTUnwrap(
            Bundle(for: WideTurnGestureRegressionTests.self).url(
                forResource: "RecordedWideTurnGestureFixture",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            WideTurnGestureFixture.self,
            from: Data(contentsOf: url)
        )
    }

    private func polyline(angles: [Double], samplesPerSegment: Int = 20) -> [CGPoint] {
        let vertices = angles.reduce(into: [CGPoint.zero]) { points, degrees in
            let radians = degrees * .pi / 180
            let last = points[points.count - 1]
            points.append(CGPoint(
                x: last.x + cos(radians),
                y: last.y + sin(radians)
            ))
        }
        return [vertices[0]] + zip(vertices, vertices.dropFirst()).flatMap { start, end in
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

private struct WideTurnGestureFixture: Decodable {
    let template: [WideTurnGesturePoint]
    let templateSegments: [WideTurnGestureSegment]
    let strokes: [[WideTurnGesturePoint]]
}

private struct WideTurnGestureSegment: Decodable {
    let angleDegrees: Double
    let lengthFraction: Double
}

private struct WideTurnGesturePoint: Decodable {
    let x: CGFloat
    let y: CGFloat
}

private extension Array where Element == WideTurnGesturePoint {
    var cgPoints: [CGPoint] { map { CGPoint(x: $0.x, y: $0.y) } }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
