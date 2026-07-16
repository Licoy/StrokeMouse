import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TemplateMatcherRobustnessTests: XCTestCase {
    private typealias Support = GestureRecognitionTestSupport

    func testRecordedPeakMatchesWiderAngleRedraw() {
        let redraw = Support.peak(Support.PeakVariation(
            width: 140,
            height: 160,
            apexFraction: 0.52,
            endpointOffset: -12,
            jitter: 0
        ))
        let score = TemplateMatcher.bestScore(redraw, Support.recordedNarrowPeak)
        XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold, "score=\(score)")
    }

    func testRecordedPeakStronglyRejectsSignificantTrailingStroke() {
        let template = Support.recordedNarrowPeak
        let end = template[template.count - 1]
        let tail = (1...20).map { index -> CGPoint in
            let progress = CGFloat(index) / 20
            return CGPoint(x: end.x + 0.8 * progress, y: end.y + 0.08 * progress)
        }
        let score = TemplateMatcher.bestScore(template + tail, template)
        XCTAssertLessThan(score, Constants.freePathMatchThreshold)
        XCTAssertLessThan(score, 0.60, "A structural rejection must not be a threshold near-miss")
    }

    func testSeededNaturalVariationsMeetRecallTargetWithVariableSpeed() {
        let sampleCount = 2_000
        var generator = Support.LinearCongruentialGenerator(seed: 0xC0FFEE)
        var accepted = 0
        var minimumScore = Double.infinity
        var rejectedExamples: [String] = []

        for _ in 0..<sampleCount {
            let variation = Support.randomPeak(using: &generator)
            let pointCount = Int(generator.nextCGFloat(in: 24...120))
            let timing = generator.nextCGFloat(in: 0.45...2.2)
            let rotation = generator.nextCGFloat(in: -12...12)
            let stroke = Support.rotate(
                Support.peak(variation, sampleCount: pointCount, timingExponent: timing),
                degrees: rotation
            )
            let score = TemplateMatcher.bestScore(stroke, Support.recordedNarrowPeak)
            minimumScore = min(minimumScore, score)
            if score >= Constants.freePathMatchThreshold {
                accepted += 1
            } else if rejectedExamples.count < 5 {
                rejectedExamples.append(
                    "\(variation), points=\(pointCount), timing=\(timing), "
                        + "rotation=\(rotation), score=\(score)"
                )
            }
        }

        let recall = Double(accepted) / Double(sampleCount)
        print("Seeded variable-speed recall: \(accepted)/\(sampleCount), min=\(minimumScore)")
        XCTAssertGreaterThanOrEqual(recall, 0.96, "examples=\(rejectedExamples)")
    }

    func testSeededTrailingStrokeCorpusHasNoFalseMatches() {
        let sampleCount = 2_000
        var generator = Support.LinearCongruentialGenerator(seed: 0xBAD5EED)
        var falseMatches = 0

        for _ in 0..<sampleCount {
            let variation = Support.randomPeak(using: &generator)
            let stroke = Support.appendingTail(
                to: Support.peak(
                    variation,
                    sampleCount: Int(generator.nextCGFloat(in: 24...120)),
                    timingExponent: generator.nextCGFloat(in: 0.45...2.2)
                ),
                lengthFraction: generator.nextCGFloat(in: 0.15...0.70),
                angleDegrees: generator.nextCGFloat(in: -5...20)
            )
            let score = TemplateMatcher.bestScore(
                Support.rotate(stroke, degrees: generator.nextCGFloat(in: -12...12)),
                Support.recordedNarrowPeak
            )
            if score >= Constants.freePathMatchThreshold { falseMatches += 1 }
        }

        XCTAssertEqual(falseMatches, 0)
    }

    func testShortOverrunIsAllowedButNewTurningSegmentIsRejected() {
        let short = Support.appendingTail(
            to: Support.recordedNarrowPeak,
            lengthFraction: 0.08,
            angleDegrees: 5
        )
        let significant = Support.appendingTail(
            to: Support.recordedNarrowPeak,
            lengthFraction: 0.10,
            angleDegrees: 5
        )

        let shortEvaluation = TemplateMatcher.evaluate(short, Support.recordedNarrowPeak)
        XCTAssertGreaterThanOrEqual(
            shortEvaluation.score,
            Constants.freePathMatchThreshold,
            "mismatch=\(String(describing: shortEvaluation.structuralMismatch))"
        )
        XCTAssertLessThan(
            TemplateMatcher.bestScore(significant, Support.recordedNarrowPeak),
            Constants.freePathMatchThreshold
        )
    }

    func testFragmentedTerminalOverrunUsesOneCumulativeBudget() {
        let firstTail = Support.appendingTail(
            to: Support.recordedNarrowPeak,
            lengthFraction: 0.06,
            angleDegrees: 0
        )
        let fragmentedTail = Support.appendingTail(
            to: firstTail,
            lengthFraction: 0.06,
            angleDegrees: 45
        )

        let evaluation = TemplateMatcher.evaluate(fragmentedTail, Support.recordedNarrowPeak)
        XCTAssertEqual(evaluation.structuralMismatch, .terminalOverrun)
        XCTAssertLessThan(
            evaluation.score,
            Constants.freePathMatchThreshold
        )

        let complex = PathTemplates.polyline(Support.complexVertices).map(\.cgPoint)
        let complexFirstTail = Support.appendingTail(
            to: complex,
            lengthFraction: 0.06,
            angleDegrees: 0
        )
        let complexFragmentedTail = Support.appendingTail(
            to: complexFirstTail,
            lengthFraction: 0.06,
            angleDegrees: 45
        )
        XCTAssertEqual(
            TemplateMatcher.evaluate(complexFragmentedTail, complex).structuralMismatch,
            .terminalOverrun
        )
    }

    func testPeakScoreIsContinuousAcrossWidthApexAndRotationSweeps() {
        assertContinuousSweep(stride(from: CGFloat(110), through: 170, by: 2)) { width in
            Support.peak(self.variation(width: width, apex: 0.52))
        }
        assertContinuousSweep(stride(from: CGFloat(0.36), through: 0.54, by: 0.01)) { apex in
            Support.peak(self.variation(width: 140, apex: apex))
        }
        assertContinuousSweep(stride(from: CGFloat(-30), through: 30, by: 2)) { endpoint in
            Support.peak(self.variation(width: 140, apex: 0.52, endpoint: endpoint))
        }
        assertContinuousSweep(stride(from: CGFloat(-12), through: 12, by: 1)) { degrees in
            Support.rotate(Support.peak(self.variation(width: 140, apex: 0.52)), degrees: degrees)
        }
    }

    func testOneDimensionalNormalizationBoundaryDoesNotCreateScoreCliff() {
        let template = PathTemplates.polyline([
            CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.26), CGPoint(x: 1, y: 0),
        ]).map(\.cgPoint)
        var previous: Double?
        for height in stride(from: CGFloat(0.23), through: 0.29, by: 0.005) {
            let candidate = PathTemplates.polyline([
                CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: height), CGPoint(x: 1, y: 0),
            ]).map(\.cgPoint)
            let score = TemplateMatcher.bestScore(candidate, template)
            XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold)
            if let previous { XCTAssertLessThan(abs(score - previous), 0.08) }
            previous = score
        }
    }

    func testSegmentMergeBoundaryDoesNotCreateAcceptanceCliff() {
        let template = PathTemplates.polyline(kinkedComplexPath(turnDegrees: 20)).map(\.cgPoint)
        var previous: Double?
        for turn in stride(from: CGFloat(18), through: 22, by: 1) {
            let candidate = PathTemplates.polyline(kinkedComplexPath(turnDegrees: turn)).map(\.cgPoint)
            let score = TemplateMatcher.bestScore(candidate, template)
            XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold, "turn=\(turn)")
            if let previous { XCTAssertLessThan(abs(score - previous), 0.08, "turn=\(turn)") }
            previous = score
        }
    }

    func testWrongOrderMirrorsTruncationAndPrependedStrokeAreRejected() {
        let template = Support.recordedNarrowPeak
        let start = template[0]
        let prefix = (0..<12).map { index -> CGPoint in
            let progress = CGFloat(index) / 12
            return CGPoint(x: start.x - 0.5 * (1 - progress), y: start.y - 0.05 * (1 - progress))
        }
        let variants = [
            prefix + template,
            Array(template.prefix(16)),
            Array(template.reversed()),
            template.map { CGPoint(x: -$0.x, y: $0.y) },
            template.map { CGPoint(x: $0.x, y: -$0.y) },
        ]
        for stroke in variants {
            XCTAssertLessThan(
                TemplateMatcher.bestScore(stroke, template),
                Constants.freePathMatchThreshold
            )
        }
    }

    func testComplexPathUsesLocalEndpointTangents() {
        let template = PathTemplates.polyline(Support.complexVertices).map(\.cgPoint)
        let redraw = Support.rotate(
            PathTemplates.polyline(Support.complexVertices.map {
                CGPoint(x: 80 + $0.x * 220, y: 40 + $0.y * 220)
            }).map(\.cgPoint),
            degrees: 8
        )
        let hooked = Support.appendingTail(to: redraw, lengthFraction: 0.20, angleDegrees: 5)

        XCTAssertGreaterThanOrEqual(
            TemplateMatcher.bestScore(redraw, template),
            Constants.freePathMatchThreshold
        )
        XCTAssertLessThan(
            TemplateMatcher.bestScore(hooked, template),
            Constants.freePathMatchThreshold
        )
    }

    func testDegenerateAndNonFinitePathsAreRejected() {
        XCTAssertEqual(TemplateMatcher.bestScore([.zero, .zero], Support.recordedNarrowPeak), 0)
        XCTAssertEqual(
            TemplateMatcher.bestScore(
                [.zero, CGPoint(x: CGFloat.nan, y: 1)],
                Support.recordedNarrowPeak
            ),
            0
        )
    }

    private func variation(
        width: CGFloat,
        apex: CGFloat,
        endpoint: CGFloat = -12
    ) -> Support.PeakVariation {
        Support.PeakVariation(
            width: width,
            height: 160,
            apexFraction: apex,
            endpointOffset: endpoint,
            jitter: 2
        )
    }

    private func assertContinuousSweep<S: Sequence>(
        _ values: S,
        stroke: (S.Element) -> [CGPoint]
    ) {
        var previous: Double?
        for value in values {
            let score = TemplateMatcher.bestScore(stroke(value), Support.recordedNarrowPeak)
            XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold, "value=\(value)")
            if let previous { XCTAssertLessThan(abs(score - previous), 0.08, "value=\(value)") }
            previous = score
        }
    }

    private func kinkedComplexPath(turnDegrees: CGFloat) -> [CGPoint] {
        let endpoint = Support.complexVertices[1]
        let baseAngle = atan2(endpoint.y, endpoint.x)
        let halfTurn = turnDegrees * .pi / 360
        let halfLength = hypot(endpoint.x, endpoint.y) / (2 * cos(halfTurn))
        let midpoint = CGPoint(
            x: cos(baseAngle - halfTurn) * halfLength,
            y: sin(baseAngle - halfTurn) * halfLength
        )
        return [.zero, midpoint] + Array(Support.complexVertices.dropFirst())
    }
}
