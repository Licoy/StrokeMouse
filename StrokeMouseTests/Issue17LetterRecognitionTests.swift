import CoreGraphics
import Foundation
import XCTest
@testable import StrokeMouse

/// Real letter attempts from GitHub issue #17. Under the structural gates most
/// curved letters scored zero; these tests keep the elastic matcher honest
/// against the reporter's own drawings.
final class Issue17LetterRecognitionTests: XCTestCase {
    private let drawnLetters = ["S", "U", "E", "G", "O", "D", "C", "V"]

    func testReporterTemplatesRecognizeTheirLetterAttempts() throws {
        let fixture = try loadFixture()
        let profiles = fixture.templates.map { template in
            GestureProfile(
                name: template.name,
                pattern: .freePath(template.cgPoints.map(CodablePoint.init))
            )
        }
        var accepted: [String: Int] = [:]
        var wrong = 0
        for trace in fixture.traces {
            let evaluation = evaluate(trace.cgPoints, profiles: profiles, fixture: fixture)
            guard let winner = evaluation.acceptedCandidate?.profile.name else { continue }
            if winner == trace.label {
                accepted[trace.label, default: 0] += 1
            } else {
                wrong += 1
            }
        }

        let total = accepted.values.reduce(0, +)
        print(
            "issue-17 single template: accepted=\(total)/\(fixture.traces.count), "
                + "wrong=\(wrong), \(accepted)"
        )
        XCTAssertGreaterThanOrEqual(Double(total) / Double(fixture.traces.count), 0.88)
        XCTAssertLessThanOrEqual(wrong, 1)
        for letter in drawnLetters {
            let attempts = fixture.traces.filter { $0.label == letter }.count
            XCTAssertGreaterThanOrEqual(
                Double(accepted[letter, default: 0]) / Double(attempts),
                0.70,
                letter
            )
        }
    }

    func testFiveRecordedAttemptsPerLetterRecognizeTheRemainingAttempts() throws {
        let fixture = try loadFixture()
        var accepted = 0
        var wrong = 0
        var total = 0
        // Samples are taken the way a user records them: the first or the
        // last five attempts of each letter, never chosen by score.
        for usesFirstAttempts in [true, false] {
            var sampleIndices = Set<Int>()
            var profiles = drawnLetters.map { letter -> GestureProfile in
                let indices = fixture.traces.indices.filter { fixture.traces[$0].label == letter }
                let chosen = usesFirstAttempts ? indices.prefix(5) : indices.suffix(5)
                sampleIndices.formUnion(chosen)
                let paths = chosen.map { index in
                    UnistrokeGeometry.recordedPath(fixture.traces[index].cgPoints)!
                        .map(CodablePoint.init)
                }
                return GestureProfile(
                    name: letter,
                    input: .drawn(DrawnGesture(
                        activation: .mouse(.default),
                        points: paths[0],
                        additionalPaths: Array(paths.dropFirst())
                    ))
                )
            }
            profiles += fixture.templates.filter { !drawnLetters.contains($0.name) }.map {
                GestureProfile(
                    name: $0.name,
                    pattern: .freePath($0.cgPoints.map(CodablePoint.init))
                )
            }
            for index in fixture.traces.indices where !sampleIndices.contains(index) {
                let trace = fixture.traces[index]
                total += 1
                let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
                    path: trace.cgPoints,
                    profiles: profiles,
                    policy: fixture.policy.recognitionPolicy
                )
                guard let winner = evaluation.acceptedCandidate?.profile.name else { continue }
                if winner == trace.label { accepted += 1 } else { wrong += 1 }
            }
        }

        print("issue-17 five samples: accepted=\(accepted)/\(total), wrong=\(wrong)")
        XCTAssertGreaterThanOrEqual(Double(accepted) / Double(total), 0.85)
        XCTAssertLessThan(Double(wrong) / Double(total), 0.01)
    }

    func testReversedAttemptsNeverMatchTheirLetter() throws {
        let fixture = try loadFixture()
        let templates = Dictionary(uniqueKeysWithValues: fixture.templates.map {
            ($0.name, TemplateMatcher.prepare($0.cgPoints))
        })
        for (index, trace) in fixture.traces.enumerated() {
            let template = try XCTUnwrap(templates[trace.label])
            let score = TemplateMatcher.evaluate(
                stroke: TemplateMatcher.prepare(Array(trace.cgPoints.reversed())),
                template: template
            ).score
            XCTAssertLessThan(
                score,
                Constants.freePathMatchThresholdRange.lowerBound,
                "trace=\(index), letter=\(trace.label)"
            )
        }
    }

    func testLiveFeedbackRarelyWarnsWhileDrawingRealLetters() throws {
        let fixture = try loadFixture()
        let templates = fixture.templates.map { TemplateMatcher.prepare($0.cgPoints) }
        var warned = 0
        for trace in fixture.traces {
            let points = trace.cgPoints
            var hysteresis = LiveGestureViability.Hysteresis()
            for count in stride(from: 4, through: points.count, by: 4) {
                let observed = LiveGestureViability.evaluate(
                    path: Array(points.prefix(count)),
                    preparedTemplates: templates,
                    minimumPathLength: Constants.defaultMinStrokeDistance,
                    matchThreshold: fixture.policy.matchThreshold
                )
                hysteresis = LiveGestureViability.applyHysteresis(
                    current: hysteresis,
                    observed: observed
                )
            }
            if hysteresis.state == .unlikely { warned += 1 }
        }

        print("issue-17 live warnings: \(warned)/\(fixture.traces.count)")
        XCTAssertLessThanOrEqual(warned, 3)
    }

    private func evaluate(
        _ path: [CGPoint],
        profiles: [GestureProfile],
        fixture: Issue17Fixture
    ) -> GestureRecognitionEvaluation {
        GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: profiles,
            policy: fixture.policy.recognitionPolicy
        )
    }

    private func loadFixture() throws -> Issue17Fixture {
        let url = try XCTUnwrap(
            Bundle(for: Issue17LetterRecognitionTests.self).url(
                forResource: "Issue17LetterTracesFixture",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(Issue17Fixture.self, from: Data(contentsOf: url))
    }
}

private struct Issue17Fixture: Decodable {
    struct Policy: Decodable {
        let matchThreshold: Double
        let minimumLeadOverSecond: Double

        var recognitionPolicy: GestureRecognitionPolicy {
            GestureRecognitionPolicy(
                minimumPathLength: 0,
                matchThreshold: matchThreshold,
                minimumLeadOverSecond: minimumLeadOverSecond
            )
        }
    }

    struct Template: Decodable {
        let name: String
        let points: [[CGFloat]]

        var cgPoints: [CGPoint] { points.map { CGPoint(x: $0[0], y: $0[1]) } }
    }

    struct Trace: Decodable {
        let label: String
        let points: [[CGFloat]]

        var cgPoints: [CGPoint] { points.map { CGPoint(x: $0[0], y: $0[1]) } }
    }

    let policy: Policy
    let templates: [Template]
    let traces: [Trace]
}
