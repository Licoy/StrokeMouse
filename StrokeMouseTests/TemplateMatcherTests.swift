import CoreGraphics
import XCTest
@testable import StrokeMouse

final class TemplateMatcherTests: XCTestCase {
    func testIdenticalPathsHighScore() {
        let path = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50),
            CGPoint(x: 0, y: 50),
        ]
        let score = TemplateMatcher.similarity(path, path)
        XCTAssertGreaterThan(score, 0.95)
    }

    func testDifferentPathsLowerScore() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let b = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
        let score = TemplateMatcher.bestScore(a, b)
        XCTAssertLessThan(score, Constants.freePathMatchThreshold)
    }

    func testDefaultUpTemplateMatchesLiveUpStroke() {
        let template = PathTemplates.up.map(\.cgPoint)
        let stroke = (0..<40).map { CGPoint(x: 200, y: 100 + CGFloat($0) * 8) }
        let score = TemplateMatcher.bestScore(stroke, template)
        XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold)
    }

    func testDefaultDownLeftMatches() {
        let template = PathTemplates.downLeft.map(\.cgPoint)
        var stroke: [CGPoint] = []
        for i in 0..<20 { stroke.append(CGPoint(x: 300, y: 400 - CGFloat(i) * 8)) }
        for i in 0..<20 { stroke.append(CGPoint(x: 300 - CGFloat(i) * 8, y: 240)) }
        let score = TemplateMatcher.bestScore(stroke, template)
        XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold)
    }

    func testHorizontalMatchesRightTemplate() {
        let template = PathTemplates.right.map(\.cgPoint)
        let stroke = (0..<40).map { CGPoint(x: 100 + CGFloat($0) * 5, y: 200) }
        let score = TemplateMatcher.bestScore(stroke, template)
        XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold)
    }

    func testOppositeHorizontalDirectionDoesNotMatch() {
        let leftTemplate = PathTemplates.left.map(\.cgPoint)
        let rightStroke = (0..<40).map { CGPoint(x: 100 + CGFloat($0) * 5, y: 200) }
        let score = TemplateMatcher.bestScore(rightStroke, leftTemplate)
        XCTAssertLessThan(score, Constants.freePathMatchThreshold)
    }

    func testOppositeVerticalDirectionDoesNotMatch() {
        let downTemplate = PathTemplates.down.map(\.cgPoint)
        let upStroke = (0..<40).map { CGPoint(x: 200, y: 100 + CGFloat($0) * 5) }
        let score = TemplateMatcher.bestScore(upStroke, downTemplate)
        XCTAssertLessThan(score, Constants.freePathMatchThreshold)
    }

    func testPeakMatchesPeakTemplate() {
        let template = PathTemplates.peak.map(\.cgPoint)
        var stroke: [CGPoint] = []
        for i in 0..<20 { stroke.append(CGPoint(x: 100 + CGFloat(i) * 5, y: 100 + CGFloat(i) * 8)) }
        for i in 0..<20 { stroke.append(CGPoint(x: 200 + CGFloat(i) * 5, y: 260 - CGFloat(i) * 8)) }
        let score = TemplateMatcher.bestScore(stroke, template)
        XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold)
    }

    func testRecordedNarrowPeakMatchesNaturalRedraws() {
        let template = PathTemplates.polyline([
            CGPoint(x: 0, y: 0.05),
            CGPoint(x: 0.306, y: 0.992),
            CGPoint(x: 0.72, y: 0),
        ]).map(\.cgPoint)
        let redraws = [
            [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 285), CGPoint(x: 230, y: 100)],
            [CGPoint(x: 100, y: 100), CGPoint(x: 142, y: 290), CGPoint(x: 205, y: 94)],
            [CGPoint(x: 100, y: 100), CGPoint(x: 165, y: 275), CGPoint(x: 270, y: 106)],
            [CGPoint(x: 100, y: 100), CGPoint(x: 151, y: 270), CGPoint(x: 158, y: 282),
             CGPoint(x: 168, y: 270), CGPoint(x: 245, y: 105)],
        ].map { PathTemplates.polyline($0).map(\.cgPoint) }

        for (index, redraw) in redraws.enumerated() {
            let score = TemplateMatcher.bestScore(redraw, template)
            XCTAssertGreaterThanOrEqual(
                score,
                Constants.freePathMatchThreshold,
                "Natural redraw #\(index + 1) should match the recorded peak (score=\(score))"
            )
        }
    }

    func testRecordedNarrowPeakMatchesNoisyNaturalRedraw() {
        let template = PathTemplates.polyline([
            CGPoint(x: 0, y: 0.05),
            CGPoint(x: 0.306, y: 0.992),
            CGPoint(x: 0.72, y: 0),
        ]).map(\.cgPoint)
        let redraw = peakStroke(PeakVariation(
            width: 115,
            height: 160,
            apexFraction: 0.42,
            endpointOffset: 0,
            jitter: 5
        ))
        let score = TemplateMatcher.bestScore(redraw, template)

        XCTAssertGreaterThanOrEqual(
            score,
            Constants.freePathMatchThreshold,
            "A slightly shaky redraw should still match its recorded peak (score=\(score))"
        )
    }

    func testRecordedNarrowPeakRecognitionRateAcrossNaturalVariations() {
        let template = PathTemplates.polyline([
            CGPoint(x: 0, y: 0.05),
            CGPoint(x: 0.306, y: 0.992),
            CGPoint(x: 0.72, y: 0),
        ]).map(\.cgPoint)
        var scores: [Double] = []
        var rejected: [String] = []

        for width in [80.0, 115.0, 160.0] {
            for apexFraction in [0.32, 0.42, 0.52] {
                for endpointOffset in [-12.0, 0.0, 12.0] {
                    for jitter in [0.0, 2.5, 5.0] {
                        let stroke = peakStroke(PeakVariation(
                            width: width,
                            height: 160,
                            apexFraction: apexFraction,
                            endpointOffset: endpointOffset,
                            jitter: jitter
                        ))
                        let score = TemplateMatcher.bestScore(stroke, template)
                        scores.append(score)
                        if score < Constants.freePathMatchThreshold {
                            rejected.append(
                                "width=\(width), apex=\(apexFraction), endpoint=\(endpointOffset), "
                                    + "jitter=\(jitter), score=\(score)"
                            )
                        }
                    }
                }
            }
        }

        let accepted = scores.filter { $0 >= Constants.freePathMatchThreshold }.count
        let recognitionRate = Double(accepted) / Double(scores.count)
        XCTAssertGreaterThanOrEqual(
            recognitionRate,
            0.9,
            "Expected at least 90% recognition, got \(accepted)/\(scores.count); "
                + "minimum score=\(scores.min() ?? 0); rejected=\(rejected)"
        )
    }

    func testPeakDoesNotMatchHorizontal() {
        let horizontal = PathTemplates.right.map(\.cgPoint)
        var peak: [CGPoint] = []
        for i in 0..<20 { peak.append(CGPoint(x: 100 + CGFloat(i) * 5, y: 100 + CGFloat(i) * 8)) }
        for i in 0..<20 { peak.append(CGPoint(x: 200 + CGFloat(i) * 5, y: 260 - CGFloat(i) * 8)) }
        let score = TemplateMatcher.bestScore(peak, horizontal)
        XCTAssertLessThan(
            score,
            Constants.freePathMatchThreshold,
            "Peak stroke must not match a horizontal template (score=\(score))"
        )
    }

    func testShallowPeakDoesNotMatchHorizontal() {
        let horizontal = PathTemplates.right.map(\.cgPoint)
        var peak: [CGPoint] = []
        for i in 0..<30 { peak.append(CGPoint(x: CGFloat(i) * 5, y: CGFloat(i))) }
        for i in 0..<30 { peak.append(CGPoint(x: 150 + CGFloat(i) * 5, y: 30 - CGFloat(i))) }
        let score = TemplateMatcher.bestScore(peak, horizontal)
        XCTAssertLessThan(
            score,
            Constants.freePathMatchThreshold,
            "Shallow peak must not match horizontal (score=\(score))"
        )
    }

    func testHorizontalDoesNotMatchPeakTemplate() {
        let peak = PathTemplates.peak.map(\.cgPoint)
        let stroke = (0..<40).map { CGPoint(x: 100 + CGFloat($0) * 5, y: 200) }
        let score = TemplateMatcher.bestScore(stroke, peak)
        XCTAssertLessThan(score, Constants.freePathMatchThreshold)
    }

    func testDirectionDistanceExact() {
        let a: [Direction] = [.up, .right]
        XCTAssertEqual(DirectionQuantizer.distance(a, a), 0)
    }

    func testDirectionDistanceOneEdit() {
        let a: [Direction] = [.up, .right]
        let b: [Direction] = [.up]
        XCTAssertEqual(DirectionQuantizer.distance(a, b), 1)
    }

    func testQuantizeUpStrokeYUp() {
        let points = (0..<20).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 5) }
        let dirs = DirectionQuantizer.quantize(points, minSegmentLength: 10, axis: .yUp)
        XCTAssertEqual(dirs.first, .up)
    }

    private struct PeakVariation {
        let width: CGFloat
        let height: CGFloat
        let apexFraction: CGFloat
        let endpointOffset: CGFloat
        let jitter: CGFloat
    }

    private func peakStroke(_ variation: PeakVariation) -> [CGPoint] {
        (0...40).map { index in
            let progress = CGFloat(index) / 40
            let isRising = progress <= 0.5
            let segmentProgress = isRising ? progress * 2 : (progress - 0.5) * 2
            let apex = CGPoint(x: variation.width * variation.apexFraction, y: variation.height)
            let start = isRising ? CGPoint.zero : apex
            let end = isRising ? apex : CGPoint(x: variation.width, y: variation.endpointOffset)
            let noise = sin(CGFloat(index) * 1.37) * variation.jitter
            return CGPoint(
                x: 100 + start.x + (end.x - start.x) * segmentProgress + noise * 0.3,
                y: 100 + start.y + (end.y - start.y) * segmentProgress + noise
            )
        }
    }
}
