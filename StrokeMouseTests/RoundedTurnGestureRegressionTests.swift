import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class RoundedTurnGestureRegressionTests: XCTestCase {
    func testAllRecordedRoundedTurnRedrawsMatchRepresentativeTemplate() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.strokes.count, 46)
        XCTAssertEqual(fixture.templateSegments.count, 3)

        let evaluations = fixture.strokes.map {
            TemplateMatcher.evaluate($0.cgPoints, fixture.template.cgPoints)
        }
        let rejected = evaluations.enumerated().compactMap { index, evaluation -> String? in
            guard evaluation.score < Constants.freePathMatchThreshold else { return nil }
            return "stroke=\(index + 1), score=\(evaluation.score), "
                + "raw=\(evaluation.shapeScore), "
                + "mismatch=\(String(describing: evaluation.structuralMismatch))"
        }

        XCTAssertTrue(rejected.isEmpty, "Rejected recorded redraws: \(rejected)")
    }

    func testEquivalentRoundedTurnsStayContinuousAcrossTwoThreeAndFourSegments() throws {
        let fixture = try loadFixture()
        let startAngle = try XCTUnwrap(fixture.templateSegments.first?.angleDegrees)
        let endAngle = try XCTUnwrap(fixture.templateSegments.last?.angleDegrees)
        let evaluations = (2...4).map { count in
            let angles = (0..<count).map { index in
                startAngle + (endAngle - startAngle)
                    * Double(index) / Double(count - 1)
            }
            return TemplateMatcher.evaluate(
                polyline(angles: angles),
                fixture.template.cgPoints
            )
        }
        for evaluation in evaluations {
            XCTAssertGreaterThanOrEqual(evaluation.score, Constants.freePathMatchThreshold)
        }
        let scores = evaluations.map(\.score)
        XCTAssertLessThan((scores.max() ?? 1) - (scores.min() ?? 0), 0.06, "\(scores)")
    }

    func testAnyRecordedRedrawWorksAsTemplateForTheOthers() throws {
        let strokes = try loadFixture().strokes.map(\.cgPoints)
        let prepared = strokes.map(TemplateMatcher.prepare)
        var accepted = 0
        var total = 0
        var lowest = 1.0
        for templateIndex in prepared.indices {
            for strokeIndex in prepared.indices where strokeIndex != templateIndex {
                let score = TemplateMatcher.evaluate(
                    stroke: prepared[strokeIndex],
                    template: prepared[templateIndex]
                ).score
                total += 1
                lowest = min(lowest, score)
                if score >= Constants.freePathMatchThreshold { accepted += 1 }
            }
        }
        print("rounded-turn cross redraw acceptance=\(accepted)/\(total), lowest=\(lowest)")
        XCTAssertGreaterThanOrEqual(Double(accepted) / Double(total), 0.97)
    }

    func testRoundedTurnStillRejectsMirrorReverseTruncationAndExtraTurns() throws {
        let template = try loadFixture().template.cgPoints
        let start = try XCTUnwrap(template.first)
        let mirrored = template.map {
            CGPoint(x: start.x - ($0.x - start.x), y: $0.y)
        }
        let truncated = Array(template.prefix(max(2, template.count / 3)))
        let prepended = [
            CGPoint(x: start.x + 80, y: start.y),
            start,
        ] + Array(template.dropFirst())
        func tail(_ fraction: CGFloat) -> [CGPoint] {
            GestureRecognitionTestSupport.appendingTail(
                to: template,
                lengthFraction: fraction,
                angleDegrees: 90
            )
        }
        let rejectedAtMinimum = [
            ("mirrored", mirrored),
            ("reversed", Array(template.reversed())),
            ("truncated", truncated),
            ("prepended", prepended),
            ("tail-0.3", tail(0.30)),
            ("tail-0.7", tail(0.70)),
        ]

        for (name, variant) in rejectedAtMinimum {
            let evaluation = TemplateMatcher.evaluate(variant, template)
            XCTAssertLessThan(
                evaluation.score,
                Constants.freePathMatchThresholdRange.lowerBound,
                "\(name): \(evaluation)"
            )
        }
        XCTAssertLessThan(
            TemplateMatcher.bestScore(tail(0.15), template),
            Constants.freePathMatchThreshold
        )
    }

    func testTwoThousandRoundedTurnTailsStayRareAndLongOnesNeverMatch() throws {
        let fixture = try loadFixture()
        var defaultMatches = 0
        var longTailDefaultMatches = 0
        var longerTailMinimumMatches = 0
        for index in 0..<2_000 {
            let stroke = fixture.strokes[index % fixture.strokes.count].cgPoints
            let fraction = CGFloat(15 + (index * 17) % 56) / 100
            let angle = CGFloat(60 + (index * 37) % 91)
            let tailed = GestureRecognitionTestSupport.appendingTail(
                to: stroke,
                lengthFraction: fraction,
                angleDegrees: angle
            )
            let score = TemplateMatcher.bestScore(tailed, fixture.template.cgPoints)
            if score >= Constants.freePathMatchThreshold {
                defaultMatches += 1
                if fraction >= 0.40 { longTailDefaultMatches += 1 }
            }
            if fraction >= 0.50, score >= Constants.freePathMatchThresholdRange.lowerBound {
                longerTailMinimumMatches += 1
            }
        }

        print("rounded-turn tails at default threshold: \(defaultMatches)/2000")
        XCTAssertLessThanOrEqual(defaultMatches, 60)
        XCTAssertEqual(longTailDefaultMatches, 0)
        XCTAssertEqual(longerTailMinimumMatches, 0)
    }

    func testDistinctSameTopologyRoundedTurnCandidatesRemainAmbiguous() throws {
        let template = try loadFixture().template.cgPoints
        let rotated = GestureRecognitionTestSupport.rotate(template, degrees: 2)
        XCTAssertNotEqual(template.map(CodablePoint.init), rotated.map(CodablePoint.init))
        let profiles = [
            GestureProfile(name: "First", pattern: .freePath(template.map(CodablePoint.init))),
            GestureProfile(name: "Second", pattern: .freePath(rotated.map(CodablePoint.init))),
        ]

        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: profiles,
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .ambiguous)
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertLessThan(
            result.candidates[0].score - result.candidates[1].score,
            Constants.freePathMinLeadOverSecond
        )
    }

    private func loadFixture() throws -> RoundedTurnGestureFixture {
        let url = try XCTUnwrap(
            Bundle(for: RoundedTurnGestureRegressionTests.self).url(
                forResource: "RecordedRoundedTurnGestureFixture",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            RoundedTurnGestureFixture.self,
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

private struct RoundedTurnGestureFixture: Decodable {
    let template: [RoundedTurnGesturePoint]
    let templateSegments: [RoundedTurnGestureSegment]
    let strokes: [[RoundedTurnGesturePoint]]
}

private struct RoundedTurnGestureSegment: Decodable {
    let angleDegrees: Double
    let lengthFraction: Double
}

private struct RoundedTurnGesturePoint: Decodable {
    let x: CGFloat
    let y: CGFloat
}

private extension Array where Element == RoundedTurnGesturePoint {
    var cgPoints: [CGPoint] { map { CGPoint(x: $0.x, y: $0.y) } }
}
