import XCTest
@testable import StrokeMouse

final class GestureTestLogReplayTests: XCTestCase {
    func testSchemaV6ExactlyReplaysMultiSampleAggregatedCandidate() throws {
        let path = GestureRecognitionTestSupport.recordedNarrowPeak
        let profile = GestureProfile(
            name: "Multi",
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: PathTemplates.left,
                additionalPaths: [path.map(CodablePoint.init)]
            ))
        )
        let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [profile],
            policy: .standard(minimumPathLength: 0)
        )
        let entry = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: path,
            evaluation: evaluation,
            source: .mouseRuntime,
            configurationRevision: 42
        )
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONEncoder.gestureTestEncoder.encode(entry)
        )

        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertEqual(decoded.configurationRevision, 42)
        XCTAssertEqual(decoded.candidates.first?.sourceTemplatePaths?.count, 2)
        XCTAssertEqual(decoded.candidates.first?.winningTemplateIndex, 1)
        XCTAssertEqual(decoded.candidates.first?.templateEvaluations?.count, 2)

        let report = GestureTestLogReplay.replay(decoded)
        XCTAssertEqual(report.fidelity, .exact)
        XCTAssertEqual(report.decisionMatches, true)
        XCTAssertEqual(report.winningProfileMatches, true)
        XCTAssertEqual(report.scoreDelta ?? .nan, 0, accuracy: 1e-12)
        XCTAssertEqual(report.mismatchMatches, true)
        XCTAssertEqual(report.winningSamplesMatch, true)
        XCTAssertEqual(report.candidateScoresMatch, true)
        XCTAssertFalse(report.hasMismatch)
    }

    func testAlgorithmVersionChangeUsesCurrentAlgorithmReevaluation() throws {
        let entry = makeEntry()
        let changed = try replacingJSONField(
            "algorithmVersion",
            with: "older-algorithm",
            in: entry
        )

        let report = GestureTestLogReplay.replay(changed)

        XCTAssertEqual(report.fidelity, .currentAlgorithmReevaluation)
        XCTAssertNotNil(report.evaluation)
    }

    func testMissingV6TemplatesIsUnavailableInsteadOfPretendingExact() throws {
        let entry = makeEntry()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.gestureTestEncoder.encode(entry)
            ) as? [String: Any]
        )
        var candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
        candidates[0].removeValue(forKey: "sourceTemplatePaths")
        object["candidates"] = candidates
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        let report = GestureTestLogReplay.replay(decoded)

        XCTAssertEqual(report.fidelity, .unavailable)
        XCTAssertNil(report.evaluation)
        XCTAssertNotNil(report.unavailableReason)
    }

    func testSchemaV5ExactSingleTemplateUsesCurrentAlgorithmReevaluation()
        throws
    {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.gestureTestEncoder.encode(makeEntry())
            ) as? [String: Any]
        )
        object["schemaVersion"] = 5
        object.removeValue(forKey: "source")
        object.removeValue(forKey: "algorithmVersion")
        object.removeValue(forKey: "evaluationTier")
        var candidates = try XCTUnwrap(object["candidates"] as? [[String: Any]])
        candidates[0].removeValue(forKey: "sourceTemplatePaths")
        candidates[0].removeValue(forKey: "winningTemplateIndex")
        candidates[0].removeValue(forKey: "templateEvaluations")
        object["candidates"] = candidates
        let entry = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        let report = GestureTestLogReplay.replay(entry)

        XCTAssertEqual(report.fidelity, .currentAlgorithmReevaluation)
        XCTAssertEqual(report.decisionMatches, true)
        XCTAssertNotNil(report.evaluation)
    }

    func testInfiniteDiagnosticDistanceIsOmittedAndEncodingSucceeds() throws {
        let diagnostics = TemplateMatcher.Diagnostics(
            mode: .orderedPath,
            distance: .infinity,
            rotationDegrees: 0,
            rawGeometryScore: 0.5,
            strokeSegments: [],
            templateSegments: []
        )
        let logged = GestureTestLogMatchDiagnostics(
            diagnostics,
            finalScore: 0.5
        )

        XCTAssertNil(logged.distance)
        XCTAssertNoThrow(try JSONEncoder.gestureTestEncoder.encode(logged))

        let invalidScore = GestureTestLogMatchDiagnostics(
            diagnostics,
            finalScore: .infinity
        )
        XCTAssertThrowsError(
            try JSONEncoder.gestureTestEncoder.encode(invalidScore)
        )
    }

    func testRuntimeSourcesPreserveMiddleMouseAndOptionModifier() throws {
        let path = PathTemplates.up.map(\.cgPoint)
        let middleProfile = GestureProfile(
            name: "Middle",
            input: .drawn(DrawnGesture(
                activation: .mouse(GestureTrigger(button: .middle)),
                points: PathTemplates.up
            ))
        )
        let middleEvaluation = GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: [middleProfile],
            button: .middle,
            policy: .standard(minimumPathLength: 0)
        )
        let middle = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: path,
            evaluation: middleEvaluation,
            source: .mouseRuntime,
            activation: .mouse(GestureTrigger(button: .middle))
        )
        XCTAssertEqual(middle.selectedTrigger, .middle)
        XCTAssertEqual(
            middle.activation,
            .mouse(GestureTrigger(button: .middle))
        )

        let modifierProfile = GestureProfile(
            name: "Option",
            input: .drawn(DrawnGesture(
                activation: .modifier(.option),
                points: PathTemplates.up
            ))
        )
        let modifierEvaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [modifierProfile],
            policy: .standard(minimumPathLength: 0)
        )
        let modifier = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: path,
            evaluation: modifierEvaluation,
            source: .modifierRuntime,
            activation: .modifier(.option)
        )
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONEncoder.gestureTestEncoder.encode(modifier)
        )
        XCTAssertEqual(decoded.activation, .modifier(.option))
    }

    func testInvalidAndTooShortPathsRoundTripAndReplayTheirDecisions() throws {
        let invalidEvaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: [],
            profiles: [],
            policy: .standard(minimumPathLength: 40)
        )
        let invalid = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: [],
            evaluation: invalidEvaluation
        )
        let invalidReport = GestureTestLogReplay.replay(invalid)
        XCTAssertEqual(invalidReport.fidelity, .exact)
        XCTAssertEqual(invalidReport.evaluation?.decision, .invalidPath)
        XCTAssertEqual(invalidReport.decisionMatches, true)

        let zeroLength = [CGPoint.zero, CGPoint.zero]
        let shortEvaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: zeroLength,
            profiles: [],
            policy: .standard(minimumPathLength: 40)
        )
        let tooShort = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: zeroLength,
            evaluation: shortEvaluation
        )
        let data = try JSONEncoder.gestureTestEncoder.encode(tooShort)
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: data
        )
        let shortReport = GestureTestLogReplay.replay(decoded)
        XCTAssertEqual(shortReport.fidelity, .exact)
        XCTAssertEqual(shortReport.evaluation?.decision, .tooShort)
        XCTAssertEqual(shortReport.decisionMatches, true)
    }

    func testCancelledDiagnosticRoundTripsAsNonrecognition() throws {
        let diagnostic = GestureDrawDiagnostic(
            source: .modifier(.option),
            path: [CGPoint.zero, CGPoint(x: 8, y: 3)],
            evaluation: nil,
            outcome: .cancelled,
            configurationRevision: 27
        )
        let entry = try GestureTestLogEntry(
            sessionID: UUID(),
            cancelledDiagnostic: diagnostic
        )
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONEncoder.gestureTestEncoder.encode(entry)
        )

        XCTAssertEqual(decoded.source, .modifierRuntime)
        XCTAssertEqual(decoded.activation, .modifier(.option))
        XCTAssertEqual(decoded.outcome, .cancelled)
        XCTAssertEqual(decoded.configurationRevision, 27)
        XCTAssertNil(decoded.decision)
        XCTAssertNil(decoded.policy)
        XCTAssertTrue(decoded.candidates.isEmpty)

        let report = GestureTestLogReplay.replay(decoded)
        XCTAssertEqual(report.fidelity, .nonrecognition)
        XCTAssertNil(report.evaluation)
        XCTAssertEqual(report.unavailableReason, "Cancelled before recognition")
        XCTAssertFalse(report.hasMismatch)
    }

    private func makeEntry() -> GestureTestLogEntry {
        let path = PathTemplates.up.map(\.cgPoint)
        let profile = GestureProfile(
            name: "Up",
            pattern: .freePath(PathTemplates.up)
        )
        let evaluation = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [profile],
            policy: .standard(minimumPathLength: 0)
        )
        return GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: path,
            evaluation: evaluation
        )
    }

    private func replacingJSONField(
        _ key: String,
        with value: Any,
        in entry: GestureTestLogEntry
    ) throws -> GestureTestLogEntry {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.gestureTestEncoder.encode(entry)
            ) as? [String: Any]
        )
        object[key] = value
        return try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
