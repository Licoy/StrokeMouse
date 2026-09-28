import CoreGraphics
import Dispatch
import Foundation
import XCTest
@testable import StrokeMouse

final class CurveRecognitionTests: XCTestCase {
    private let glyphs = ["eight", "S", "epsilon", "D", "O", "C", "R", "G", "U"]

    func testTrainingCurvesMatchTheirRecordedTemplates() throws {
        for name in glyphs {
            let template = curve(name, count: 128)
            let evaluation = TemplateMatcher.evaluate(template, template)
            XCTAssertGreaterThanOrEqual(evaluation.score, 0.99, name)
            XCTAssertEqual(evaluation.diagnostics?.mode, .curveOrderedPath, name)
        }
    }

    func testCalibrationCurvesTolerateSamplingSpeedAndSmallShapeVariation() {
        for name in glyphs {
            let template = curve(name, count: 128)
            for (count, warp, xScale, yScale, rotation) in [
                (61, CGFloat(0.88), CGFloat(0.96), CGFloat(1.03), CGFloat(-8)),
                (193, CGFloat(1.12), CGFloat(1.04), CGFloat(0.97), CGFloat(8)),
            ] {
                let stroke = transformed(
                    curve(name, count: count, warp: warp),
                    xScale: xScale,
                    yScale: yScale,
                    rotation: rotation
                )
                let evaluation = TemplateMatcher.evaluate(stroke, template)
                XCTAssertGreaterThanOrEqual(
                    evaluation.score,
                    Constants.freePathMatchThreshold,
                    "\(name): \(evaluation)"
                )
            }
        }
    }

    func testHoldoutCurvesMatchUnseenVariations() {
        for name in glyphs {
            let base = curve(name, count: 89, warp: 1.06)
            let locallyDeformed = base.enumerated().map { index, point in
                let progress = CGFloat(index) / CGFloat(base.count - 1)
                return CGPoint(
                    x: point.x + sin(progress * .pi) * 3 + sin(CGFloat(index) * 1.7) * 0.6,
                    y: point.y + sin(progress * 2 * .pi) * 2 + cos(CGFloat(index) * 1.3) * 0.6
                )
            }
            let evaluation = TemplateMatcher.evaluate(
                transformed(
                    locallyDeformed,
                    xScale: 0.98,
                    yScale: 1.02,
                    rotation: 5
                ),
                curve(name, count: 128)
            )
            XCTAssertGreaterThanOrEqual(
                evaluation.score,
                Constants.freePathMatchThreshold,
                "\(name): \(evaluation)"
            )
        }
    }

    func testClosedCurveRejectsAdditionalLoop() {
        let template = curve("O", count: 128)
        let additionalLoop = template + Array(template.dropFirst())
        let evaluation = TemplateMatcher.evaluate(additionalLoop, template)
        XCTAssertLessThan(
            evaluation.score,
            Constants.freePathMatchThresholdRange.lowerBound,
            "\(evaluation)"
        )
    }

    func testIncompleteClosedCurveRemainsLiveViable() {
        let template = curve("O", count: 128)
        let prefix = Array(curve("O", count: 89).prefix(55))
        let state = LiveGestureViability.evaluate(
            path: prefix,
            preparedTemplates: [TemplateMatcher.prepare(template)],
            minimumPathLength: 0,
            matchThreshold: Constants.freePathMatchThreshold
        )
        XCTAssertEqual(state, .viable)
    }

    func testLongZigzagAgainstClosedCurveBecomesLiveUnlikely() {
        let template = curve("O", count: 128)
        let zigzag = (0..<30).map { index in
            CGPoint(x: index.isMultiple(of: 2) ? -100 : 100, y: CGFloat(index) * 15)
        }
        let state = LiveGestureViability.evaluate(
            path: zigzag,
            preparedTemplates: [TemplateMatcher.prepare(template)],
            minimumPathLength: 0,
            matchThreshold: Constants.freePathMatchThreshold
        )
        XCTAssertEqual(state, .unlikely)
    }

    func testLegacy32PointAndNew128PointEpsilonTemplatesMatchRawCurve() throws {
        let raw = curve("epsilon", count: 241, warp: 0.93)
        let legacy = try XCTUnwrap(UnistrokeGeometry.resampledPath(
            curve("epsilon", count: 97),
            count: 32
        ))
        let recorded = try XCTUnwrap(UnistrokeGeometry.recordedPath(
            curve("epsilon", count: 97)
        ))

        XCTAssertEqual(legacy.count, 32)
        XCTAssertEqual(recorded.count, 128)
        for template in [legacy, recorded] {
            let evaluation = TemplateMatcher.evaluate(raw, template)
            XCTAssertGreaterThanOrEqual(
                evaluation.score,
                Constants.freePathMatchThreshold,
                "\(evaluation)"
            )
        }
    }

    func testCurvesRejectReverseMirrorTailAndWrongStart() {
        for name in glyphs {
            let template = curve(name, count: 128)
            let centerX = ((template.map(\.x).min() ?? 0) + (template.map(\.x).max() ?? 0)) / 2
            let shifted = Array(template.dropFirst(31)) + Array(template.prefix(31))
            let variants = [
                ("reverse", Array(template.reversed())),
                ("mirror", template.map { CGPoint(x: centerX * 2 - $0.x, y: $0.y) }),
                ("wrong-start", shifted),
                ("truncated", Array(template.prefix(template.count * 2 / 3))),
                ("extra-segment", GestureRecognitionTestSupport.appendingTail(
                    to: template,
                    lengthFraction: 0.20,
                    angleDegrees: 90
                )),
            ]
            for (variant, stroke) in variants {
                XCTAssertLessThan(
                    TemplateMatcher.bestScore(stroke, template),
                    Constants.freePathMatchThresholdRange.lowerBound,
                    "\(name)-\(variant)"
                )
            }
            for fraction in [CGFloat(0.15), 0.30, 0.70] {
                let tail = GestureRecognitionTestSupport.appendingTail(
                    to: template,
                    lengthFraction: fraction,
                    angleDegrees: 90
                )
                XCTAssertLessThan(
                    TemplateMatcher.bestScore(tail, template),
                    Constants.freePathMatchThresholdRange.lowerBound,
                    "\(name)-tail-\(fraction)"
                )
            }
        }
    }

    func testCurveCandidateConfusionMatrixKeepsOtherGlyphsBelowMinimumThreshold() {
        let templates = glyphs.map { ($0, curve($0, count: 128)) }
        for (strokeName, stroke) in templates {
            for (templateName, template) in templates where strokeName != templateName {
                XCTAssertLessThan(
                    TemplateMatcher.bestScore(stroke, template),
                    Constants.freePathMatchThresholdRange.lowerBound,
                    "stroke=\(strokeName), template=\(templateName)"
                )
            }
        }
    }

    func testSharpPolylinesDoNotUseCurveMatching() {
        let paths = [
            [CGPoint.zero, CGPoint(x: 100, y: 0), .zero],
            [CGPoint.zero, CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)],
            GestureRecognitionTestSupport.complexVertices,
        ]
        for path in paths {
            XCTAssertFalse(CurvePathSignature.make(path)?.isCurve ?? true)
        }
    }

    func testRecordedPathPreservesEndpointsAndRejectsInvalidInput() throws {
        let input = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30, y: 60),
            CGPoint(x: 90, y: 30),
        ]
        let sampled = try XCTUnwrap(UnistrokeGeometry.resampledPath(
            input,
            count: Constants.freePathRecordingSampleCount
        ))
        XCTAssertEqual(sampled.first, input.first)
        XCTAssertEqual(sampled.last, input.last)
        let expected = try XCTUnwrap(UnistrokeGeometry.normalize(sampled, uniform: true))
        let recorded = try XCTUnwrap(UnistrokeGeometry.recordedPath(input))
        XCTAssertEqual(recorded.count, Constants.freePathRecordingSampleCount)
        XCTAssertEqual(recorded.first!.x, expected.first!.x, accuracy: 1e-12)
        XCTAssertEqual(recorded.first!.y, expected.first!.y, accuracy: 1e-12)
        XCTAssertEqual(recorded.last!.x, expected.last!.x, accuracy: 1e-12)
        XCTAssertEqual(recorded.last!.y, expected.last!.y, accuracy: 1e-12)
        XCTAssertNil(UnistrokeGeometry.recordedPath([.zero, CGPoint(x: CGFloat.nan, y: 1)]))
        XCTAssertNil(UnistrokeGeometry.recordedPath([.zero, .zero]))
    }

    func testCurvePerformanceWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["STROKEMOUSE_CURVE_BENCHMARK"] == "1"
                || ProcessInfo.processInfo.environment[
                    "TEST_RUNNER_STROKEMOUSE_CURVE_BENCHMARK"
                ] == "1"
        )
        let standardProfiles = benchmarkProfiles(count: 50, sampleCount: 3)
        let standardTemplates = preparedPaths(in: standardProfiles)
        let stroke = curve("eight", count: 89, warp: 1.04)
        _ = GestureRecognitionEvaluator.evaluateDrawn(
            path: stroke,
            profiles: standardProfiles,
            policy: .standard(minimumPathLength: 0)
        )
        let endP95 = p95 {
            _ = GestureRecognitionEvaluator.evaluateDrawn(
                path: stroke,
                profiles: standardProfiles,
                policy: .standard(minimumPathLength: 0)
            )
        }
        let liveP95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: stroke,
                preparedTemplates: standardTemplates,
                minimumPathLength: 0,
                matchThreshold: Constants.freePathMatchThreshold
            )
        }

        let stressProfiles = benchmarkProfiles(count: 100, sampleCount: 5)
        let stressTemplates = preparedPaths(in: stressProfiles)
        let stressEndP95 = p95 {
            _ = GestureRecognitionEvaluator.evaluateDrawn(
                path: stroke,
                profiles: stressProfiles,
                policy: .standard(minimumPathLength: 0)
            )
        }
        let stressLiveP95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: stroke,
                preparedTemplates: stressTemplates,
                minimumPathLength: 0,
                matchThreshold: Constants.freePathMatchThreshold
            )
        }
        print(
            "curve benchmark end-50x3-p95-ms=\(endP95) "
                + "live-50x3-p95-ms=\(liveP95) "
                + "stress-end-100x5-p95-ms=\(stressEndP95) "
                + "stress-live-100x5-p95-ms=\(stressLiveP95)"
        )
        XCTAssertLessThanOrEqual(endP95, 30)
        XCTAssertLessThanOrEqual(liveP95, 8)
    }

    private func transformed(
        _ points: [CGPoint],
        xScale: CGFloat,
        yScale: CGFloat,
        rotation: CGFloat
    ) -> [CGPoint] {
        let radians = rotation * .pi / 180
        return points.map {
            let x = $0.x * xScale
            let y = $0.y * yScale
            return CGPoint(
                x: x * cos(radians) - y * sin(radians) + 240,
                y: x * sin(radians) + y * cos(radians) - 130
            )
        }
    }

    private func curve(_ name: String, count: Int, warp: CGFloat = 1) -> [CGPoint] {
        (0..<count).map { index in
            let linear = CGFloat(index) / CGFloat(count - 1)
            return curvePoint(name, progress: pow(linear, warp))
        }
    }

    private func curvePoint(_ name: String, progress p: CGFloat) -> CGPoint {
        switch name {
        case "eight":
            let angle = p * 2 * CGFloat.pi
            return CGPoint(x: sin(angle) * 120, y: sin(angle * 2) * 80)
        case "S":
            return CGPoint(x: sin(p * 2 * .pi) * 70, y: (1 - 2 * p) * 120)
        case "epsilon":
            let angle = (-0.15 + p * 1.75) * CGFloat.pi
            return CGPoint(x: sin(angle) * 85, y: sin(angle * 2) * 55)
        case "O":
            let angle = (-0.5 + 2 * p) * CGFloat.pi
            return CGPoint(x: cos(angle) * 80, y: sin(angle) * 115)
        case "C":
            let angle = (0.25 + 1.5 * p) * CGFloat.pi
            return CGPoint(x: cos(angle) * 80, y: sin(angle) * 115)
        case "U":
            if p < 0.3 { return CGPoint(x: -80, y: 120 - p / 0.3 * 180) }
            if p < 0.7 {
                let angle = .pi - (p - 0.3) / 0.4 * .pi
                return CGPoint(x: cos(angle) * 80, y: -60 - sin(angle) * 55)
            }
            return CGPoint(x: 80, y: -60 + (p - 0.7) / 0.3 * 180)
        case "D":
            if p < 0.32 { return CGPoint(x: -70, y: 110 - p / 0.32 * 220) }
            let angle = (-0.5 + (p - 0.32) / 0.68) * CGFloat.pi
            return CGPoint(x: -70 + cos(angle) * 140, y: sin(angle) * 110)
        case "R":
            if p < 0.25 { return CGPoint(x: -60, y: -110 + p / 0.25 * 220) }
            if p < 0.7 {
                let q = (p - 0.25) / 0.45
                return CGPoint(x: -60 + sin(q * .pi) * 105, y: 110 - q * 110)
            }
            let q = (p - 0.7) / 0.3
            return CGPoint(x: -60 + q * 145, y: -q * 110)
        case "G":
            if p < 0.8 {
                let angle = (0.2 + 1.55 * p / 0.8) * CGFloat.pi
                return CGPoint(x: cos(angle) * 85, y: sin(angle) * 110)
            }
            let q = (p - 0.8) / 0.2
            return CGPoint(x: 60 - q * 55, y: -25)
        default:
            return .zero
        }
    }

    private func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func benchmarkProfiles(count: Int, sampleCount: Int) -> [GestureProfile] {
        (0..<count).map { index in
            let name = glyphs[index % glyphs.count]
            let paths = (0..<sampleCount).map { sample in
                curve(
                    name,
                    count: 128 - sample * 7,
                    warp: 1 + CGFloat(sample) * 0.02
                ).map(CodablePoint.init)
            }
            return GestureProfile(
                name: "curve-\(index)",
                input: .drawn(DrawnGesture(
                    activation: .mouse(.default),
                    points: paths[0],
                    additionalPaths: Array(paths.dropFirst())
                ))
            )
        }
    }

    private func preparedPaths(in profiles: [GestureProfile]) -> [TemplateMatcher.PreparedPath] {
        profiles.flatMap { profile -> [TemplateMatcher.PreparedPath] in
            guard case let .drawn(drawn) = profile.input else { return [] }
            return drawn.allPaths.map { TemplateMatcher.prepare($0.map(\.cgPoint)) }
        }
    }

    private func p95(iterations: Int = 100, operation: () -> Void) -> Double {
        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            values.append(milliseconds(since: start))
        }
        values.sort()
        let index = max(0, (values.count * 95 + 99) / 100 - 1)
        return values[index]
    }
}
