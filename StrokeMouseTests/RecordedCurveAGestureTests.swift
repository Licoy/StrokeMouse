import CoreGraphics
import Dispatch
import Foundation
import XCTest
@testable import StrokeMouse

final class RecordedCurveAGestureTests: XCTestCase {
    func testNineReviewedLowercaseAShapedAttemptsTriggerTargetAtRecordedPolicy() throws {
        let fixture = try loadFixture()
        let positiveSamples = fixture.samples.filter { $0.intent == .reviewedLowercaseA }

        XCTAssertEqual(positiveSamples.count, 9)
        XCTAssertEqual(fixture.samples.filter { $0.intent == .unknownIntent }.count, 2)

        let profiles = makeProfiles(fixture.candidates)
        let targetID = try targetProfileID(in: profiles)
        let targetOnly = try XCTUnwrap(profiles.first { $0.id == targetID })
        for sample in positiveSamples {
            for scenario in [[targetOnly], profiles] {
                let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
                    path: sample.rawPath.cgPoints,
                    profiles: scenario,
                    policy: fixture.policy.recognitionPolicy
                )

                XCTAssertEqual(
                    evaluation.decision,
                    .accepted,
                    "sample=\(sample.id), candidates=\(scenario.count), "
                        + "target=\(targetSummary(evaluation, targetID: targetID))"
                )
                XCTAssertEqual(
                    evaluation.acceptedCandidate?.profile.id,
                    targetID,
                    "sample=\(sample.id), candidates=\(scenario.count)"
                )
            }
        }
    }

    func testHistoricalV1LogsAreReportedAsCurrentAlgorithmReevaluations() throws {
        let fixture = try loadFixture()
        XCTAssertNotEqual(fixture.recordedAlgorithmVersion, TemplateMatcher.algorithmVersion)

        for sample in fixture.samples {
            let report = GestureTestLogReplay.replay(
                try historicalEntry(sample: sample, fixture: fixture)
            )
            let reevaluated = try XCTUnwrap(report.evaluation, "sample=\(sample.id)")
            let target = try XCTUnwrap(reevaluated.candidates.first, "sample=\(sample.id)")

            XCTAssertEqual(report.fidelity, .currentAlgorithmReevaluation, sample.id)
            XCTAssertNil(report.unavailableReason, sample.id)
            if sample.intent == .reviewedLowercaseA {
                XCTAssertEqual(reevaluated.decision, .accepted, sample.id)
                XCTAssertEqual(report.decisionMatches, false, sample.id)
                XCTAssertGreaterThan(report.scoreDelta ?? 0, 0, sample.id)
                XCTAssertEqual(report.candidateScoresMatch, false, sample.id)
            }
            print(
                "\(sample.id) intent=\(sample.intent.rawValue) "
                    + "recorded(score=\(sample.recorded.target.score), "
                    + "decision=\(sample.recorded.decision)) "
                    + "current(score=\(target.score), decision=\(reevaluated.decision.rawValue)) "
                    + "delta=\(report.scoreDelta ?? .nan)"
            )
        }
    }

    func testRecordedLowercaseARemainsAcceptedAcrossAffineAndSeededSamplingNoise() throws {
        let fixture = try loadFixture()
        let profiles = makeProfiles(fixture.candidates)
        let targetID = try targetProfileID(in: profiles)
        let positiveSamples = fixture.samples.filter { $0.intent == .reviewedLowercaseA }
        let variations: [(String, CGFloat, CGPoint, CGFloat, Int, UInt64, CGFloat)] = [
            ("translated", 1, CGPoint(x: 73, y: -41), 0, 64, 0xA11, 0),
            ("uniform-scaled", 1.35, .zero, 0, 64, 0xA12, 0),
            ("jitter-0.1-density-32", 0.80, CGPoint(x: 29, y: 17), 0.1, 32, 0xB21, 0),
            ("jitter-0.5-density-96", 1.20, CGPoint(x: -53, y: 61), 0.5, 96, 0xB22, 0),
            ("jitter-0.1-density-160", 0.95, CGPoint(x: 101, y: -37), 0.1, 160, 0xB23, 0),
            ("rotate-minus-8", 1, .zero, 0, 64, 0xC31, -8),
            ("rotate-plus-8", 1, .zero, 0, 64, 0xC32, 8),
        ]

        for sample in positiveSamples {
            for (name, scale, offset, jitter, count, seed, rotation) in variations {
                let path = try perturbed(
                    sample.rawPath.cgPoints,
                    scale: scale,
                    offset: offset,
                    jitter: jitter,
                    sampleCount: count,
                    seed: seed,
                    rotationDegrees: rotation
                )
                let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
                    path: path,
                    profiles: profiles,
                    policy: fixture.policy.recognitionPolicy
                )
                let diagnostic = targetSummary(evaluation, targetID: targetID)
                if sample.id == "recorded-2" || sample.id == "recorded-4" {
                    print("\(sample.id) \(name) \(diagnostic)")
                }

                XCTAssertGreaterThanOrEqual(evaluation.pathLength, fixture.policy.minimumPathLength)
                XCTAssertEqual(
                    evaluation.decision,
                    .accepted,
                    "sample=\(sample.id), \(name), \(diagnostic)"
                )
                XCTAssertEqual(
                    evaluation.acceptedCandidate?.profile.id,
                    targetID,
                    "sample=\(sample.id), \(name), \(diagnostic)"
                )
            }
        }
    }

    func testExactTargetTemplateAcceptsFullAllowedRotationRange() throws {
        let fixture = try loadFixture()
        let target = try XCTUnwrap(fixture.candidates.first { $0.role == .target })
        let profile = makeProfile(target)
        let template = target.template.cgPoints.scaled(by: 200)

        for degrees in [CGFloat(-12), 12] {
            let rotated = try perturbed(
                template,
                scale: 1,
                offset: .zero,
                jitter: 0,
                sampleCount: template.count,
                seed: 0xD12,
                rotationDegrees: degrees
            )
            let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
                path: rotated,
                profiles: [profile],
                policy: fixture.policy.recognitionPolicy
            )

            XCTAssertEqual(
                evaluation.decision,
                .accepted,
                "rotation=\(degrees), " + targetSummary(evaluation, targetID: profile.id)
            )
            XCTAssertEqual(evaluation.acceptedCandidate?.profile.id, profile.id)
        }
    }

    func testRecordedLowercaseAPrefixesDoNotTripLiveUnlikelyHysteresis() throws {
        let fixture = try loadFixture()
        let target = try XCTUnwrap(fixture.candidates.first { $0.role == .target })
        let preparedTemplate = TemplateMatcher.prepare(target.template.cgPoints)

        for sample in fixture.samples where sample.intent == .reviewedLowercaseA {
            let raw = sample.rawPath.cgPoints
            var hysteresis = LiveGestureViability.Hysteresis()
            for count in stride(from: 4, through: raw.count, by: 4) {
                let prefix = Array(raw.prefix(count))
                guard PathSimplifier.pathLength(prefix) >= fixture.policy.minimumPathLength else {
                    continue
                }
                let observed = LiveGestureViability.evaluate(
                    path: prefix,
                    preparedTemplates: [preparedTemplate],
                    minimumPathLength: fixture.policy.minimumPathLength,
                    matchThreshold: fixture.policy.matchThreshold
                )
                hysteresis = LiveGestureViability.applyHysteresis(
                    current: hysteresis,
                    observed: observed
                )

                XCTAssertNotEqual(
                    hysteresis.state,
                    .unlikely,
                    "sample=\(sample.id), count=\(count)"
                )
            }
        }
    }

    func testNonEquivalentVariantsAndOtherRecordedCandidatesDoNotTriggerTarget() throws {
        let fixture = try loadFixture()
        let target = try XCTUnwrap(fixture.candidates.first { $0.role == .target })
        let targetProfile = makeProfile(target)
        let points = target.template.cgPoints.scaled(by: 200)
        let centerX = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let pathLength = PathSimplifier.pathLength(points)
        let endpoint = try XCTUnwrap(points.last)
        let sharpSegment = (1...12).map { index in
            CGPoint(
                x: endpoint.x,
                y: endpoint.y + pathLength * 0.25 * CGFloat(index) / 12
            )
        }
        let longTail = (1...12).map { index in
            CGPoint(
                x: endpoint.x + pathLength * 0.70 * CGFloat(index) / 12,
                y: endpoint.y
            )
        }
        let variants: [(String, [CGPoint])] = [
            ("reverse-non-equivalent", Array(points.reversed())),
            ("mirror-non-equivalent", points.map { CGPoint(x: centerX * 2 - $0.x, y: $0.y) }),
            ("prefix-35-percent", Array(points.prefix(max(2, points.count * 35 / 100)))),
            ("truncated-70-percent", Array(points.prefix(max(2, points.count * 70 / 100)))),
            ("additional-sharp-segment", points + sharpSegment),
            ("long-tail-70-percent", points + longTail),
        ]
        let competitorVariants: [(String, [CGPoint])] = fixture.candidates
            .filter { $0.role == .competitor }
            .map {
            ("other-candidate-\($0.id)", $0.template.cgPoints.scaled(by: 200))
        }
        let unknownIntentVariants: [(String, [CGPoint])] = fixture.samples
            .filter { $0.intent == .unknownIntent }
            .map { ("visually-non-equivalent-\($0.id)", $0.rawPath.cgPoints) }
        let rejectionPolicy = GestureRecognitionPolicy(
            minimumPathLength: fixture.policy.minimumPathLength,
            matchThreshold: Constants.freePathMatchThresholdRange.lowerBound,
            minimumLeadOverSecond: fixture.policy.minimumLeadOverSecond
        )

        for (name, path) in variants + competitorVariants + unknownIntentVariants {
            let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
                path: path,
                profiles: [targetProfile],
                policy: rejectionPolicy
            )
            XCTAssertGreaterThanOrEqual(
                evaluation.pathLength,
                fixture.policy.minimumPathLength,
                name
            )
            XCTAssertNotEqual(evaluation.decision, .tooShort, name)
            XCTAssertNotEqual(evaluation.decision, .invalidPath, name)
            XCTAssertNotEqual(evaluation.decision, .accepted, name)
            XCTAssertNil(evaluation.acceptedCandidate, name)
        }
    }

    func testEndpointAdditionsDegradeGraduallyAndLargeOnesCannotTrigger() throws {
        let fixture = try loadFixture()
        let target = try XCTUnwrap(fixture.candidates.first { $0.role == .target })
        let profile = makeProfile(target)
        let template = target.template.cgPoints
        let length = PathSimplifier.pathLength(template)
        let first = try XCTUnwrap(template.first)
        let last = try XCTUnwrap(template.last)
        func lead(_ fraction: CGFloat) -> [CGPoint] {
            let angle = CGFloat(75) * .pi / 180
            let start = CGPoint(
                x: first.x - cos(angle) * length * fraction,
                y: first.y - sin(angle) * length * fraction
            )
            return (0..<24).map { index in
                let progress = CGFloat(index) / 24
                return CGPoint(
                    x: start.x + (first.x - start.x) * progress,
                    y: start.y + (first.y - start.y) * progress
                )
            }
        }
        func tail(_ fraction: CGFloat) -> [CGPoint] {
            let angle = CGFloat(70) * .pi / 180
            return (1...24).map { index in
                let progress = CGFloat(index) / 24
                return CGPoint(
                    x: last.x + cos(angle) * length * fraction * progress,
                    y: last.y + sin(angle) * length * fraction * progress
                )
            }
        }
        func decision(_ path: [CGPoint], threshold: Double) -> GestureEvaluationDecision {
            GestureRecognitionEvaluator.evaluateDrawn(
                path: path.scaled(by: 200),
                profiles: [profile],
                policy: GestureRecognitionPolicy(
                    minimumPathLength: fixture.policy.minimumPathLength,
                    matchThreshold: threshold,
                    minimumLeadOverSecond: fixture.policy.minimumLeadOverSecond
                )
            ).decision
        }

        // A short entry or exit hook is ordinary hand motion and still triggers.
        for fraction in [CGFloat(0.05), 0.08] {
            XCTAssertEqual(decision(lead(fraction) + template, threshold: 0.70), .accepted)
            XCTAssertEqual(decision(template + tail(fraction), threshold: 0.70), .accepted)
        }
        // A quarter of the path or more is a different gesture.
        for fraction in [CGFloat(0.25), 0.35, 0.50] {
            let minimum = Constants.freePathMatchThresholdRange.lowerBound
            XCTAssertNotEqual(decision(lead(fraction) + template, threshold: minimum), .accepted)
            XCTAssertNotEqual(decision(template + tail(fraction), threshold: minimum), .accepted)
        }
        for addition in [{ lead($0) + template }, { template + tail($0) }] {
            let scores = [CGFloat(0.05), 0.10, 0.20, 0.30, 0.50].map {
                TemplateMatcher.bestScore(addition($0), template)
            }
            XCTAssertEqual(scores, scores.sorted(by: >), "\(scores)")
        }
    }

    func testUTailsArePenalizedByHowMuchTheyChangeTheShape() throws {
        let template = uCurve(count: 128)
        let cases: [(UInt64, CGFloat, Int)] = [
            (0x1515, 0.1, 64),
            (0x2020, 0.1, 97),
            (0x3535, 0.1, 160),
            (0x5050, 0.5, 64),
            (0x6565, 0.5, 97),
            (0x8080, 0.5, 160),
        ]
        let variants: [(String, CGFloat, CGFloat, Bool)] = [
            // A longer final arm is still the same U.
            ("collinear-15", 0.15, 90, true),
            ("collinear-20", 0.20, 90, true),
            // A new direction or a doubled arm is not.
            ("sideways-30", 0.30, 0, false),
            ("reversed-20", 0.20, -90, false),
            ("collinear-70", 0.70, 90, false),
        ]

        for (name, fraction, angle, tolerated) in variants {
            let tailed = GestureRecognitionTestSupport.appendingTail(
                to: template,
                lengthFraction: fraction,
                angleDegrees: angle
            )
            for (seed, jitter, sampleCount) in cases {
                let stroke = try perturbed(
                    tailed,
                    scale: 1,
                    offset: .zero,
                    jitter: jitter,
                    sampleCount: sampleCount,
                    seed: seed
                )
                let score = TemplateMatcher.bestScore(stroke, template)
                let context = "\(name), jitter=\(jitter), count=\(sampleCount), score=\(score)"
                if tolerated {
                    XCTAssertGreaterThanOrEqual(score, Constants.freePathMatchThreshold, context)
                } else {
                    XCTAssertLessThan(
                        score,
                        Constants.freePathMatchThresholdRange.lowerBound,
                        context
                    )
                }
            }
        }
    }

    func testIncompleteCurveSuffixStaysLiveWhileFinishedTailsRemainRejected() throws {
        let template = uCurve(count: 128)
        let preparedTemplate = TemplateMatcher.prepare(template)
        let prefix = Array(template.prefix(32))

        XCTAssertGreaterThanOrEqual(PathSimplifier.pathLength(prefix), 40)
        XCTAssertLessThan(
            TemplateMatcher.bestScore(prefix, template),
            Constants.freePathMatchThresholdRange.lowerBound
        )
        XCTAssertEqual(
            LiveGestureViability.evaluate(
                path: prefix,
                preparedTemplates: [preparedTemplate],
                minimumPathLength: 40,
                matchThreshold: Constants.freePathMatchThreshold
            ),
            .viable
        )

        let finishedTail = GestureRecognitionTestSupport.appendingTail(
            to: template,
            lengthFraction: 0.30,
            angleDegrees: 0
        )
        XCTAssertLessThan(
            TemplateMatcher.bestScore(finishedTail, template),
            Constants.freePathMatchThresholdRange.lowerBound
        )

        let polyline = PathTemplates.polyline(
            GestureRecognitionTestSupport.complexVertices
        ).map(\.cgPoint).scaled(by: 200)
        let polylineTail = GestureRecognitionTestSupport.appendingTail(
            to: polyline,
            lengthFraction: 0.50,
            angleDegrees: 5
        )
        XCTAssertGreaterThanOrEqual(PathSimplifier.pathLength(polylineTail), 40)
        XCTAssertEqual(
            LiveGestureViability.evaluate(
                path: polylineTail,
                preparedTemplates: [TemplateMatcher.prepare(polyline)],
                minimumPathLength: 40,
                matchThreshold: Constants.freePathMatchThreshold
            ),
            .unlikely
        )
    }

    func testRecordedACurveBenchmarkWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["STROKEMOUSE_CURVE_BENCHMARK"] == "1"
                || ProcessInfo.processInfo.environment[
                    "TEST_RUNNER_STROKEMOUSE_CURVE_BENCHMARK"
                ] == "1"
        )
        let fixture = try loadFixture()
        let terminal = try XCTUnwrap(
            fixture.samples.first { $0.intent == .reviewedLowercaseA }
        ).rawPath.cgPoints
        let prefix40 = Array(terminal.prefix(max(2, terminal.count * 40 / 100)))
        let prefix60 = Array(terminal.prefix(max(2, terminal.count * 60 / 100)))
        let zigzag = (0..<30).map { index in
            CGPoint(x: index.isMultiple(of: 2) ? -100 : 100, y: CGFloat(index) * 15)
        }
        let standard = benchmarkProfiles(fixture.candidates, count: 50, sampleCount: 3)
        let standardPrepared = preparedPaths(in: standard)
        _ = GestureRecognitionEvaluator.evaluateDrawn(
            path: terminal,
            profiles: standard,
            policy: fixture.policy.recognitionPolicy
        )
        for path in [prefix40, prefix60, zigzag] {
            _ = LiveGestureViability.evaluate(
                path: path,
                preparedTemplates: standardPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }

        let endP95 = p95 {
            _ = GestureRecognitionEvaluator.evaluateDrawn(
                path: terminal,
                profiles: standard,
                policy: fixture.policy.recognitionPolicy
            )
        }
        let live40P95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: prefix40,
                preparedTemplates: standardPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }
        let live60P95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: prefix60,
                preparedTemplates: standardPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }
        let liveNegativeP95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: zigzag,
                preparedTemplates: standardPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }
        let stress = benchmarkProfiles(fixture.candidates, count: 100, sampleCount: 5)
        let stressPrepared = preparedPaths(in: stress)
        let stressEndP95 = p95 {
            _ = GestureRecognitionEvaluator.evaluateDrawn(
                path: terminal,
                profiles: stress,
                policy: fixture.policy.recognitionPolicy
            )
        }
        let stressLive40P95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: prefix40,
                preparedTemplates: stressPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }
        let stressLive60P95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: prefix60,
                preparedTemplates: stressPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }
        let stressLiveNegativeP95 = p95 {
            _ = LiveGestureViability.evaluate(
                path: zigzag,
                preparedTemplates: stressPrepared,
                minimumPathLength: fixture.policy.minimumPathLength,
                matchThreshold: fixture.policy.matchThreshold
            )
        }

        print(
            "recorded-a benchmark end-50x3-p95-ms=\(endP95) "
                + "live-40pct-50x3-p95-ms=\(live40P95) "
                + "live-60pct-50x3-p95-ms=\(live60P95) "
                + "live-worst-50x3-p95-ms=\(max(live40P95, live60P95, liveNegativeP95)) "
                + "live-negative-50x3-p95-ms=\(liveNegativeP95) "
                + "stress-end-100x5-p95-ms=\(stressEndP95) "
                + "stress-live-40pct-100x5-p95-ms=\(stressLive40P95) "
                + "stress-live-60pct-100x5-p95-ms=\(stressLive60P95) "
                + "stress-live-negative-100x5-p95-ms=\(stressLiveNegativeP95)"
        )
        XCTAssertLessThanOrEqual(endP95, 30)
        XCTAssertLessThanOrEqual(max(live40P95, live60P95, liveNegativeP95), 8)
    }

    private func targetSummary(
        _ evaluation: GestureRecognitionEvaluation,
        targetID: UUID
    ) -> String {
        guard let target = evaluation.candidates.first(where: { $0.profile.id == targetID }) else {
            return "missing"
        }
        return "score=\(target.score), mismatch="
            + "\(String(describing: target.structuralMismatch)), distance="
            + "\(String(describing: target.diagnostics?.distance))"
    }

    private func perturbed(
        _ points: [CGPoint],
        scale: CGFloat,
        offset: CGPoint,
        jitter: CGFloat,
        sampleCount: Int,
        seed: UInt64,
        rotationDegrees: CGFloat = 0
    ) throws -> [CGPoint] {
        let center = UnistrokeGeometry.centroid(points)
        let radians = rotationDegrees * .pi / 180
        var generator = GestureRecognitionTestSupport.LinearCongruentialGenerator(seed: seed)
        let transformed = points.map { point in
            let xNoise = generator.nextCGFloat(in: -jitter...jitter)
            let yNoise = generator.nextCGFloat(in: -jitter...jitter)
            let x = (point.x - center.x) * scale
            let y = (point.y - center.y) * scale
            return CGPoint(
                x: center.x + x * cos(radians) - y * sin(radians) + offset.x + xNoise,
                y: center.y + x * sin(radians) + y * cos(radians) + offset.y + yNoise
            )
        }
        return try XCTUnwrap(
            UnistrokeGeometry.resampledPath(transformed, count: sampleCount)
        )
    }

    private func uCurve(count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let progress = CGFloat(index) / CGFloat(count - 1)
            if progress < 0.3 {
                return CGPoint(x: -80, y: 120 - progress / 0.3 * 180)
            }
            if progress < 0.7 {
                let angle = .pi - (progress - 0.3) / 0.4 * .pi
                return CGPoint(x: cos(angle) * 80, y: -60 - sin(angle) * 55)
            }
            return CGPoint(x: 80, y: -60 + (progress - 0.7) / 0.3 * 180)
        }
    }

    private func benchmarkProfiles(
        _ candidates: [RecordedCurveACandidate],
        count: Int,
        sampleCount: Int
    ) -> [GestureProfile] {
        (0..<count).map { index in
            let candidate = candidates[index % candidates.count]
            let base = candidate.template.cgPoints
            let paths = (0..<sampleCount).map { sample in
                UnistrokeGeometry.resampledPath(
                    base,
                    count: max(16, base.count - sample * 5)
                )!.map(CodablePoint.init)
            }
            return GestureProfile(
                id: UUID(uuidString: String(
                    format: "00000000-0000-0000-0001-%012d",
                    index + 1
                ))!,
                name: "benchmark-\(index)-\(candidate.id)",
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
            values.append(
                Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            )
        }
        values.sort()
        let index = max(0, (values.count * 95 + 99) / 100 - 1)
        return values[index]
    }

    private func historicalEntry(
        sample: RecordedCurveASample,
        fixture: RecordedCurveAFixture
    ) throws -> GestureTestLogEntry {
        let target = try XCTUnwrap(fixture.candidates.first { $0.role == .target })
        let points = sample.rawPath.cgPoints
        let bounds = points.reduce(into: CGRect.null) { $0 = $0.union(CGRect(origin: $1, size: .zero)) }
        let recorded = sample.recorded.target
        let candidate = GestureTestLogCandidate(
            profileID: target.stableUUID,
            profileName: target.id,
            score: recorded.score,
            shapeScore: recorded.shapeScore,
            structuralMismatch: recorded.structuralMismatch,
            templatePath: target.template,
            sourceTemplatePath: target.template,
            sourceTemplatePaths: [target.template],
            winningTemplateIndex: 0,
            templateEvaluations: [GestureTestLogTemplateEvaluation(
                finalScore: recorded.score,
                shapeScore: recorded.shapeScore,
                structuralMismatch: recorded.structuralMismatch,
                diagnostics: nil
            )],
            diagnostics: nil
        )
        let entry = HistoricalCurveALogEntry(
            schemaVersion: 6,
            timestamp: Date(timeIntervalSince1970: 0),
            sessionID: target.stableUUID,
            source: .canvas,
            activation: .mouse(.default),
            outcome: .recognition,
            algorithmVersion: fixture.recordedAlgorithmVersion,
            configurationRevision: nil,
            evaluationTier: sample.evaluationTier,
            selectedTrigger: .right,
            decision: try XCTUnwrap(GestureEvaluationDecision(rawValue: sample.recorded.decision)),
            acceptedProfileID: nil,
            acceptedProfileName: nil,
            policy: GestureTestLogRecognitionPolicy(fixture.policy.recognitionPolicy),
            metrics: GestureTestPathMetrics(
                pointCount: points.count,
                pathLength: Double(PathSimplifier.pathLength(points)),
                width: Double(bounds.width),
                height: Double(bounds.height)
            ),
            rawPath: sample.rawPath,
            sampledPath: (UnistrokeGeometry.resampledPath(
                points,
                count: Constants.freePathSampleCount
            ) ?? []).map(CodablePoint.init),
            candidates: [candidate]
        )
        return try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONEncoder.gestureTestEncoder.encode(entry)
        )
    }

    private func loadFixture() throws -> RecordedCurveAFixture {
        let url = try XCTUnwrap(
            Bundle(for: RecordedCurveAGestureTests.self).url(
                forResource: "RecordedCurveAGestureFixture",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            RecordedCurveAFixture.self,
            from: Data(contentsOf: url)
        )
    }

    private func makeProfiles(_ candidates: [RecordedCurveACandidate]) -> [GestureProfile] {
        candidates.map(makeProfile)
    }

    private func makeProfile(_ candidate: RecordedCurveACandidate) -> GestureProfile {
        GestureProfile(
            id: candidate.stableUUID,
            name: candidate.id,
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: candidate.template
            )),
            action: .none,
            scope: .global
        )
    }

    private func targetProfileID(in profiles: [GestureProfile]) throws -> UUID {
        try XCTUnwrap(profiles.first { $0.name == "target-a" }?.id)
    }
}

private struct RecordedCurveAFixture: Decodable {
    let recordedAlgorithmVersion: String
    let policy: RecordedCurveAPolicy
    let candidates: [RecordedCurveACandidate]
    let samples: [RecordedCurveASample]
}

private struct RecordedCurveAPolicy: Decodable {
    let minimumPathLength: CGFloat
    let matchThreshold: Double
    let minimumLeadOverSecond: Double

    var recognitionPolicy: GestureRecognitionPolicy {
        GestureRecognitionPolicy(
            minimumPathLength: minimumPathLength,
            matchThreshold: matchThreshold,
            minimumLeadOverSecond: minimumLeadOverSecond
        )
    }
}

private struct RecordedCurveACandidate: Decodable {
    enum Role: String, Decodable {
        case target
        case competitor
    }

    let id: String
    let role: Role
    let template: [CodablePoint]

    var stableUUID: UUID {
        let suffix = role == .target ? 1 : (Int(id.split(separator: "-").last ?? "0") ?? 0) + 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}

private struct RecordedCurveASample: Decodable {
    enum Intent: String, Decodable {
        case reviewedLowercaseA
        case unknownIntent
    }

    let id: String
    let intent: Intent
    let evaluationTier: GestureTestLogEvaluationTier
    let rawPath: [CodablePoint]
    let recorded: RecordedCurveARecordedEvaluation
}

private struct RecordedCurveARecordedEvaluation: Decodable {
    let decision: String
    let target: RecordedCurveAMatch
    let closestCompetitor: RecordedCurveACompetitorMatch
}

private struct RecordedCurveAMatch: Decodable {
    let score: Double
    let shapeScore: Double
    let structuralMismatch: TemplateMatcher.Mismatch?
}

private struct RecordedCurveACompetitorMatch: Decodable {
    let id: String
    let score: Double
    let shapeScore: Double
    let structuralMismatch: TemplateMatcher.Mismatch?
}

private struct HistoricalCurveALogEntry: Encodable {
    let schemaVersion: Int
    let timestamp: Date
    let sessionID: UUID
    let source: GestureTestLogSource
    let activation: DrawActivation
    let outcome: GestureTestLogOutcome
    let algorithmVersion: String
    let configurationRevision: UInt64?
    let evaluationTier: GestureTestLogEvaluationTier
    let selectedTrigger: MouseTriggerButton
    let decision: GestureEvaluationDecision
    let acceptedProfileID: UUID?
    let acceptedProfileName: String?
    let policy: GestureTestLogRecognitionPolicy
    let metrics: GestureTestPathMetrics
    let rawPath: [CodablePoint]
    let sampledPath: [CodablePoint]
    let candidates: [GestureTestLogCandidate]
}

private extension Array where Element == CodablePoint {
    var cgPoints: [CGPoint] { map(\.cgPoint) }
}

private extension Array where Element == CGPoint {
    func scaled(by factor: CGFloat) -> [CGPoint] {
        map { CGPoint(x: $0.x * factor, y: $0.y * factor) }
    }
}
