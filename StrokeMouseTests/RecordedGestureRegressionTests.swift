import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

final class RecordedGestureRegressionTests: XCTestCase {
    func testAllNineteenRecordedRedrawsScoreAboveNinetyPercent() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.strokes.count, 19)

        var scores: [Double] = []
        for (index, stroke) in fixture.strokes.enumerated() {
            let evaluation = TemplateMatcher.evaluate(stroke.cgPoints, fixture.template.cgPoints)
            scores.append(evaluation.score)
            XCTAssertNil(evaluation.structuralMismatch, "stroke=\(index + 1)")
            XCTAssertGreaterThanOrEqual(evaluation.score, 0.90, "stroke=\(index + 1)")
            XCTAssertEqual(
                TemplateMatcher.bestScore(stroke.cgPoints, fixture.template.cgPoints),
                evaluation.score,
                accuracy: 1e-12
            )
        }

        let minimumScore = scores.min() ?? 0
        let maximumScore = scores.max() ?? 0
        print("Recorded score range: \(minimumScore)...\(maximumScore)")
        XCTAssertGreaterThanOrEqual(minimumScore, 0.90)
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

    func testRecordedModifierVAcceptsCleanTrackpadRedraw() {
        let redraw = [
            CGPoint(x: 0.000, y: 1.000),
            CGPoint(x: 0.015, y: 0.900),
            CGPoint(x: 0.055, y: 0.745),
            CGPoint(x: 0.100, y: 0.590),
            CGPoint(x: 0.150, y: 0.430),
            CGPoint(x: 0.205, y: 0.260),
            CGPoint(x: 0.260, y: 0.090),
            CGPoint(x: 0.284, y: 0.000),
            CGPoint(x: 0.330, y: 0.105),
            CGPoint(x: 0.410, y: 0.250),
            CGPoint(x: 0.500, y: 0.410),
            CGPoint(x: 0.585, y: 0.570),
            CGPoint(x: 0.665, y: 0.710),
            CGPoint(x: 0.725, y: 0.800),
            CGPoint(x: 0.770, y: 0.875),
            CGPoint(x: 0.797, y: 0.935),
        ]

        let evaluation = TemplateMatcher.evaluate(redraw, Self.recordedModifierVTemplate)

        XCTAssertGreaterThanOrEqual(evaluation.shapeScore, Constants.freePathMatchThreshold)
        XCTAssertNil(evaluation.structuralMismatch)
        XCTAssertGreaterThanOrEqual(evaluation.score, Constants.freePathMatchThreshold)
    }

    func testSharpVWithSignificantOpposingThirdTurnMissesDefaultThreshold() {
        let vertices = [-75.0, 75.0, 40.0].reduce(into: [CGPoint.zero]) { points, degrees in
            let radians = degrees * .pi / 180
            let last = points[points.count - 1]
            points.append(CGPoint(
                x: last.x + cos(radians),
                y: last.y + sin(radians)
            ))
        }
        let template = polyline(Array(vertices.prefix(3)))
        let evaluation = TemplateMatcher.evaluate(polyline(vertices), template)

        XCTAssertLessThan(evaluation.score, Constants.freePathMatchThreshold)
    }

    func testRecordedRedrawTailsLoseScoreAsTheyGrow() throws {
        let fixture = try loadFixture()
        for (index, stroke) in fixture.strokes.enumerated() {
            let scores = [CGFloat(0), 0.15, 0.30, 0.50, 0.70].map { fraction in
                TemplateMatcher.evaluate(
                    appendingTail(to: stroke.cgPoints, fraction: fraction),
                    fixture.template.cgPoints
                ).score
            }
            let context = "stroke=\(index + 1), scores=\(scores)"
            XCTAssertEqual(scores, scores.sorted(by: >), context)
            XCTAssertLessThan(scores[2], Constants.freePathMatchThreshold, context)
            XCTAssertLessThan(scores[3], Constants.freePathMatchThresholdRange.lowerBound, context)
            XCTAssertLessThan(scores[4], Constants.freePathMatchThresholdRange.lowerBound, context)
        }
    }

    func testSeverelyTruncatedSecondLegIsRejected() {
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

        XCTAssertNil(evaluation.structuralMismatch)
        XCTAssertLessThan(evaluation.score, Constants.freePathMatchThresholdRange.lowerBound)
    }

    func testSafeSegmentProportionSweepStaysContinuousAndExtremesAreRejected() {
        let start = CGPoint(x: 0, y: 0)
        let apex = CGPoint(x: 0.5, y: 1)
        let leg = CGPoint(x: 0.5, y: -1)
        let template = polyline([start, apex, CGPoint(x: 1, y: 0)])
        func score(_ factor: CGFloat) -> Double {
            let endpoint = CGPoint(x: apex.x + leg.x * factor, y: apex.y + leg.y * factor)
            return TemplateMatcher.bestScore(polyline([start, apex, endpoint]), template)
        }
        var previousScore: Double?

        for factor in stride(from: CGFloat(0.6), through: 1.8, by: 0.1) {
            let current = score(factor)
            XCTAssertGreaterThanOrEqual(
                current,
                Constants.freePathMatchThreshold,
                "factor=\(factor)"
            )
            if let previousScore {
                XCTAssertLessThan(abs(current - previousScore), 0.08, "factor=\(factor)")
            }
            previousScore = current
        }

        for factor in [CGFloat(0.2), 0.3, 2.5, 4.0] {
            XCTAssertLessThan(
                score(factor),
                Constants.freePathMatchThresholdRange.lowerBound,
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

    private static let recordedModifierVTemplate = [
        CGPoint(x: 0, y: 1),
        CGPoint(x: 0.008045163637662627, y: 0.9310604122100498),
        CGPoint(x: 0.01828509124569431, y: 0.862550507196971),
        CGPoint(x: 0.03683092927530037, y: 0.7956667026222861),
        CGPoint(x: 0.055376767304906434, y: 0.7287828980476012),
        CGPoint(x: 0.07392260533451249, y: 0.6618990934729163),
        CGPoint(x: 0.09246844336411855, y: 0.5950152888982314),
        CGPoint(x: 0.11101428139372464, y: 0.5281314843235463),
        CGPoint(x: 0.12956011942333068, y: 0.4612476797488615),
        CGPoint(x: 0.14810595745293675, y: 0.3943638751741766),
        CGPoint(x: 0.16665179548254283, y: 0.3274800705994916),
        CGPoint(x: 0.1851976335121489, y: 0.2605962660248067),
        CGPoint(x: 0.20374347154175498, y: 0.19371246145012178),
        CGPoint(x: 0.222289309571361, y: 0.12682865687543687),
        CGPoint(x: 0.24083514760096708, y: 0.05994485230075186),
        CGPoint(x: 0.2568299477386475, y: 0.007173421914217335),
        CGPoint(x: 0.2507866096087429, y: 0.07631725379279261),
        CGPoint(x: 0.24474327147883834, y: 0.14546108567136767),
        CGPoint(x: 0.24812014989411002, y: 0.2132188362397655),
        CGPoint(x: 0.2738236814240691, y: 0.27769146523450566),
        CGPoint(x: 0.30564158422186477, y: 0.3388329944162512),
        CGPoint(x: 0.3458747522520766, y: 0.39538990038588306),
        CGPoint(x: 0.38610792028228835, y: 0.451946806355515),
        CGPoint(x: 0.4263410883125, y: 0.5085037123251468),
        CGPoint(x: 0.470364566636683, y: 0.5619629929274758),
        CGPoint(x: 0.5177778960951722, y: 0.6126519228063534),
        CGPoint(x: 0.5651912255536615, y: 0.6633408526852311),
        CGPoint(x: 0.6126045550121508, y: 0.7140297825641088),
        CGPoint(x: 0.6600178844706404, y: 0.7647187124429867),
        CGPoint(x: 0.7074312139291297, y: 0.8154076423218646),
        CGPoint(x: 0.7548445433876187, y: 0.8660965722007419),
        CGPoint(x: 0.8022578728461082, y: 0.9167855020796197),
    ]
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
