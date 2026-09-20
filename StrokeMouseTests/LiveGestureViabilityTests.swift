import CoreGraphics
import XCTest
@testable import StrokeMouse

final class LiveGestureViabilityTests: XCTestCase {
    func testHopeThresholdClampsAroundMatchThreshold() {
        let hope = LiveGestureViability.hopeThreshold(
            matchThreshold: Constants.freePathMatchThreshold
        )
        let expected = Constants.freePathMatchThreshold
            - Constants.liveViabilityHopeThresholdOffset
        XCTAssertEqual(hope, expected, accuracy: 0.001)

        let low = LiveGestureViability.hopeThreshold(matchThreshold: 0.50)
        XCTAssertEqual(
            low,
            Constants.liveViabilityHopeThresholdRange.lowerBound,
            accuracy: 0.001
        )

        let high = LiveGestureViability.hopeThreshold(matchThreshold: 0.95)
        XCTAssertEqual(
            high,
            Constants.liveViabilityHopeThresholdRange.upperBound,
            accuracy: 0.001
        )
    }

    func testShortPathStaysViable() {
        let template = Self.horizontalLine(length: 120)
        let prepared = TemplateMatcher.prepare(template)
        let short = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
        ]
        let state = LiveGestureViability.evaluate(
            path: short,
            preparedTemplates: [prepared],
            minimumPathLength: 40,
            matchThreshold: 0.70
        )
        XCTAssertEqual(state, .viable)
    }

    func testMatchingPrefixStaysViable() {
        let template = Self.horizontalLine(length: 120)
        let prepared = TemplateMatcher.prepare(template)
        // Incomplete but same direction — should remain hopeful.
        let prefix = Self.horizontalLine(length: 70)
        let state = LiveGestureViability.evaluate(
            path: prefix,
            preparedTemplates: [prepared],
            minimumPathLength: 40,
            matchThreshold: 0.70
        )
        XCTAssertEqual(state, .viable)
    }

    func testScrambledPathIsUnlikely() {
        let template = Self.horizontalLine(length: 120)
        let prepared = TemplateMatcher.prepare(template)
        // Long zigzag orthogonal to the template.
        var path: [CGPoint] = []
        for i in 0..<20 {
            let x = CGFloat(i % 2) * 80
            let y = CGFloat(i) * 12
            path.append(CGPoint(x: x, y: y))
        }
        let state = LiveGestureViability.evaluate(
            path: path,
            preparedTemplates: [prepared],
            minimumPathLength: 40,
            matchThreshold: 0.70
        )
        XCTAssertEqual(state, .unlikely)
    }

    func testEmptyTemplatesBecomeUnlikelyOnceLongEnough() {
        let path = Self.horizontalLine(length: 100)
        let state = LiveGestureViability.evaluate(
            path: path,
            preparedTemplates: [],
            minimumPathLength: 40,
            matchThreshold: 0.70
        )
        XCTAssertEqual(state, .unlikely)
    }

    func testFinalAcceptedSingleTurnRedrawNeverTurnsLiveFeedbackUnlikely() {
        let template = Self.polyline([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 200, y: 400),
            CGPoint(x: 400, y: 0),
        ])
        let preparedTemplate = TemplateMatcher.prepare(template)
        let redraw = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 100),
            CGPoint(x: 100, y: 200),
            CGPoint(x: 150, y: 300),
            CGPoint(x: 200, y: 400),
            CGPoint(x: 220, y: 360),
            CGPoint(x: 240, y: 320),
            CGPoint(x: 260, y: 280),
            CGPoint(x: 280, y: 240),
        ]
        let profile = GestureProfile(
            name: "Single turn",
            pattern: .freePath(template.map(CodablePoint.init))
        )
        let policy = GestureRecognitionPolicy(
            minimumPathLength: 0,
            matchThreshold: Constants.freePathMatchThreshold
        )
        let finalEvaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: redraw,
            profiles: [profile],
            policy: policy
        )
        XCTAssertEqual(finalEvaluation.decision, .accepted)

        var hysteresis = LiveGestureViability.Hysteresis()
        for pathCount in [2, 5, 9] {
            let observed = LiveGestureViability.evaluate(
                path: Array(redraw.prefix(pathCount)),
                preparedTemplates: [preparedTemplate],
                minimumPathLength: policy.minimumPathLength,
                matchThreshold: policy.matchThreshold
            )
            hysteresis = LiveGestureViability.applyHysteresis(
                current: hysteresis,
                observed: observed
            )
        }
        XCTAssertEqual(hysteresis.state, .viable)
    }

    func testAcceptedLowercaseERemainsViableAtTerminalSample() {
        let raw = GestureRecognitionTestSupport.lowercaseE()
        let recorded = PathSimplifier.resample(
            PathSimplifier.normalize(PathSimplifier.simplify(raw, epsilon: 2)),
            count: Constants.freePathSampleCount
        )
        let preparedTemplate = TemplateMatcher.prepare(recorded)

        let state = LiveGestureViability.evaluate(
            path: raw,
            preparedTemplates: [preparedTemplate],
            minimumPathLength: 40,
            matchThreshold: Constants.freePathMatchThreshold
        )

        XCTAssertEqual(state, .viable)
    }

    func testHysteresisRequiresConsecutiveUnlikelyEvals() {
        var h = LiveGestureViability.Hysteresis()
        h = LiveGestureViability.applyHysteresis(
            current: h,
            observed: .unlikely,
            consecutiveRequired: 3
        )
        XCTAssertEqual(h.state, .viable)
        XCTAssertEqual(h.consecutiveUnlikelyEvals, 1)

        h = LiveGestureViability.applyHysteresis(
            current: h,
            observed: .unlikely,
            consecutiveRequired: 3
        )
        XCTAssertEqual(h.state, .viable)
        XCTAssertEqual(h.consecutiveUnlikelyEvals, 2)

        h = LiveGestureViability.applyHysteresis(
            current: h,
            observed: .unlikely,
            consecutiveRequired: 3
        )
        XCTAssertEqual(h.state, .unlikely)
        XCTAssertEqual(h.consecutiveUnlikelyEvals, 3)
    }

    func testHysteresisRecoversImmediatelyOnViable() {
        var h = LiveGestureViability.Hysteresis(
            state: .unlikely,
            consecutiveUnlikelyEvals: 5
        )
        h = LiveGestureViability.applyHysteresis(
            current: h,
            observed: .viable,
            consecutiveRequired: 3
        )
        XCTAssertEqual(h.state, .viable)
        XCTAssertEqual(h.consecutiveUnlikelyEvals, 0)
    }

    // MARK: - Helpers

    private static func horizontalLine(length: CGFloat) -> [CGPoint] {
        (0...12).map { i in
            CGPoint(x: length * CGFloat(i) / 12, y: 0)
        }
    }

    private static func polyline(
        _ vertices: [CGPoint],
        samplesPerSegment: Int = 20
    ) -> [CGPoint] {
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
