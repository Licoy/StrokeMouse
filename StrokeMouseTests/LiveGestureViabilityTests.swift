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
}
