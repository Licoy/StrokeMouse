import XCTest
@testable import StrokeMouse

final class GestureTestLogStoreTests: XCTestCase {
    func testAppendsDecodableJSONLinesWithoutActionPayload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GestureTestLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("gesture-test-log.jsonl")
        let store = GestureTestLogStore(logURL: url)
        let secret = "do-not-persist-this-script"
        let profile = GestureProfile(
            name: "Peak",
            pattern: .freePath(GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init)),
            action: .shell(secret)
        )
        let evaluation = GestureRecognitionEvaluator.evaluate(
            path: GestureRecognitionTestSupport.recordedNarrowPeak,
            profiles: [profile],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )
        let sessionID = UUID()
        let entry = GestureTestLogEntry(
            sessionID: sessionID,
            rawPath: GestureRecognitionTestSupport.recordedNarrowPeak,
            evaluation: evaluation
        )

        XCTAssertEqual(entry.schemaVersion, 6)
        XCTAssertEqual(entry.source, .canvas)
        XCTAssertEqual(entry.algorithmVersion, TemplateMatcher.algorithmVersion)
        let policy = try XCTUnwrap(entry.policy)
        XCTAssertEqual(policy.minimumPathLength, 0)
        XCTAssertEqual(policy.matchThreshold, Constants.freePathMatchThreshold)
        XCTAssertEqual(policy.minimumLeadOverSecond, Constants.freePathMinLeadOverSecond)
        let diagnostics = try XCTUnwrap(entry.candidates.first?.diagnostics)
        let templatePath = try XCTUnwrap(entry.candidates.first?.templatePath)
        let sourceTemplatePath = try XCTUnwrap(entry.candidates.first?.sourceTemplatePath)
        let sourceTemplatePaths = try XCTUnwrap(
            entry.candidates.first?.sourceTemplatePaths
        )
        XCTAssertEqual(
            sourceTemplatePath,
            GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init)
        )
        XCTAssertEqual(sourceTemplatePaths, [sourceTemplatePath])
        XCTAssertEqual(entry.candidates.first?.winningTemplateIndex, 0)
        XCTAssertEqual(entry.candidates.first?.templateEvaluations?.count, 1)
        XCTAssertEqual(templatePath.count, Constants.freePathSampleCount)
        XCTAssertEqual(templatePath.map(\.x).reduce(0, +), 0, accuracy: 1e-10)
        XCTAssertEqual(templatePath.map(\.y).reduce(0, +), 0, accuracy: 1e-10)
        XCTAssertEqual(diagnostics.matchingMode, "elasticPath")
        XCTAssertEqual(diagnostics.distance ?? 1, 0, accuracy: 1e-12)
        XCTAssertNil(diagnostics.rotationDegrees)
        XCTAssertTrue(diagnostics.strokeSegments.isEmpty)
        XCTAssertTrue(diagnostics.templateSegments.isEmpty)
        XCTAssertEqual(diagnostics.finalScore, entry.candidates.first?.score)

        try store.append(entry)
        try store.append(entry)

        let data = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertFalse(text.contains(secret))

        let decoded = try lines.map { line in
            try JSONDecoder.gestureTestDecoder.decode(
                GestureTestLogEntry.self,
                from: Data(line.utf8)
            )
        }
        XCTAssertEqual(decoded.map(\.sessionID), [sessionID, sessionID])
        XCTAssertEqual(decoded[0].rawPath.count, GestureRecognitionTestSupport.recordedNarrowPeak.count)
        XCTAssertEqual(decoded[0].policy, policy)
        XCTAssertEqual(decoded[0].candidates.first?.profileName, "Peak")
        XCTAssertEqual(
            decoded[0].candidates.first?.templatePath?.count,
            Constants.freePathSampleCount
        )
        XCTAssertEqual(decoded[0].candidates.first?.sourceTemplatePath, sourceTemplatePath)
        XCTAssertEqual(
            decoded[0].candidates.first?.diagnostics?.finalScore,
            decoded[0].candidates.first?.score
        )

        try? FileManager.default.removeItem(at: directory)
    }

    func testDecodesSchemaV1LineWithoutDiagnostics() throws {
        let json = """
        {
          "schemaVersion": 1,
          "timestamp": "2026-07-16T00:00:00Z",
          "sessionID": "10000000-0000-0000-0000-000000000001",
          "selectedTrigger": "right",
          "decision": "belowThreshold",
          "metrics": {"pointCount": 2, "pathLength": 10, "width": 10, "height": 0},
          "rawPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "sampledPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "candidates": [{
            "profileID": "20000000-0000-0000-0000-000000000002",
            "profileName": "Legacy",
            "score": 0.5,
            "shapeScore": 0.5
          }]
        }
        """

        let entry = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.schemaVersion, 1)
        XCTAssertNil(entry.policy)
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy")
        XCTAssertNil(entry.candidates.first?.diagnostics)
        XCTAssertNil(entry.candidates.first?.templatePath)
        XCTAssertNil(entry.candidates.first?.sourceTemplatePath)
    }

    func testDecodesSchemaV2LineWithoutTemplatePath() throws {
        let json = """
        {
          "schemaVersion": 2,
          "timestamp": "2026-07-16T00:00:00Z",
          "sessionID": "10000000-0000-0000-0000-000000000001",
          "selectedTrigger": "right",
          "decision": "belowThreshold",
          "metrics": {"pointCount": 2, "pathLength": 10, "width": 10, "height": 0},
          "rawPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "sampledPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "candidates": [{
            "profileID": "20000000-0000-0000-0000-000000000002",
            "profileName": "Legacy v2",
            "score": 0.5,
            "shapeScore": 0.5,
            "diagnostics": {
              "matchingMode": "orderedPath",
              "distance": 0.1,
              "rotationDegrees": 0,
              "rawGeometryScore": 0.5,
              "finalScore": 0.5,
              "strokeSegments": [],
              "templateSegments": []
            }
          }]
        }
        """

        let entry = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.schemaVersion, 2)
        XCTAssertNil(entry.policy)
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy v2")
        XCTAssertNotNil(entry.candidates.first?.diagnostics)
        XCTAssertNil(entry.candidates.first?.templatePath)
        XCTAssertNil(entry.candidates.first?.sourceTemplatePath)
    }

    func testDecodesSchemaV3LineWithoutRecognitionPolicy() throws {
        let json = """
        {
          "schemaVersion": 3,
          "timestamp": "2026-07-16T00:00:00Z",
          "sessionID": "10000000-0000-0000-0000-000000000001",
          "selectedTrigger": "right",
          "decision": "belowThreshold",
          "metrics": {"pointCount": 2, "pathLength": 10, "width": 10, "height": 0},
          "rawPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "sampledPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "candidates": [{
            "profileID": "20000000-0000-0000-0000-000000000002",
            "profileName": "Legacy v3",
            "score": 0.5,
            "shapeScore": 0.5,
            "templatePath": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]
          }]
        }
        """

        let entry = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.schemaVersion, 3)
        XCTAssertNil(entry.policy)
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy v3")
        XCTAssertEqual(entry.candidates.first?.templatePath?.count, 2)
        XCTAssertNil(entry.candidates.first?.sourceTemplatePath)
    }

    func testDecodesSchemaV4LineWithoutSourceTemplatePath() throws {
        let json = """
        {
          "schemaVersion": 4,
          "timestamp": "2026-07-16T00:00:00Z",
          "sessionID": "10000000-0000-0000-0000-000000000001",
          "selectedTrigger": "right",
          "decision": "belowThreshold",
          "policy": {
            "minimumPathLength": 20,
            "matchThreshold": 0.8,
            "minimumLeadOverSecond": 0.1
          },
          "metrics": {"pointCount": 2, "pathLength": 10, "width": 10, "height": 0},
          "rawPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "sampledPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
          "candidates": [{
            "profileID": "20000000-0000-0000-0000-000000000002",
            "profileName": "Legacy v4",
            "score": 0.5,
            "shapeScore": 0.5,
            "templatePath": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]
          }]
        }
        """

        let entry = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(entry.schemaVersion, 4)
        XCTAssertEqual(entry.policy?.minimumPathLength, 20)
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy v4")
        XCTAssertEqual(entry.candidates.first?.templatePath?.count, 2)
        XCTAssertNil(entry.candidates.first?.sourceTemplatePath)
    }

    func testDecodesSchemaV5FixtureWithoutV6ReplayFields() throws {
        let data = Data(
            """
            {
              "schemaVersion": 5,
              "timestamp": "2026-09-20T00:00:00Z",
              "sessionID": "10000000-0000-0000-0000-000000000001",
              "selectedTrigger": "right",
              "decision": "accepted",
              "acceptedProfileID": "20000000-0000-0000-0000-000000000002",
              "acceptedProfileName": "Legacy v5",
              "policy": {
                "minimumPathLength": 0,
                "matchThreshold": 0.8,
                "minimumLeadOverSecond": 0.1
              },
              "metrics": {"pointCount": 2, "pathLength": 10, "width": 10, "height": 0},
              "rawPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
              "sampledPath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}],
              "candidates": [{
                "profileID": "20000000-0000-0000-0000-000000000002",
                "profileName": "Legacy v5",
                "score": 1,
                "shapeScore": 1,
                "sourceTemplatePath": [{"x": 0, "y": 0}, {"x": 10, "y": 0}]
              }]
            }
            """.utf8
        )
        let decoded = try JSONDecoder.gestureTestDecoder.decode(
            GestureTestLogEntry.self,
            from: data
        )

        XCTAssertEqual(decoded.schemaVersion, 5)
        XCTAssertNil(decoded.source)
        XCTAssertNil(decoded.activation)
        XCTAssertNil(decoded.algorithmVersion)
        XCTAssertNil(decoded.configurationRevision)
        XCTAssertNil(decoded.evaluationTier)
        XCTAssertEqual(decoded.candidates.first?.sourceTemplatePath?.count, 2)
        XCTAssertNil(decoded.candidates.first?.sourceTemplatePaths)
        XCTAssertNil(decoded.candidates.first?.winningTemplateIndex)
        XCTAssertNil(decoded.candidates.first?.templateEvaluations)
    }

    func testInvalidTemplateIsLoggedWithMismatchAndWithoutGeometry() throws {
        let profile = GestureProfile(
            name: "Collapsed",
            pattern: .freePath([CodablePoint(x: 0.5, y: 0.5), CodablePoint(x: 0.5, y: 0.5)]),
            action: .none
        )
        let stroke = GestureRecognitionTestSupport.recordedNarrowPeak
        let evaluation = GestureRecognitionEvaluator.evaluate(
            path: stroke,
            profiles: [profile],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        let entry = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: stroke,
            evaluation: evaluation
        )
        let candidate = try XCTUnwrap(entry.candidates.first)

        XCTAssertEqual(candidate.score, 0)
        XCTAssertEqual(candidate.structuralMismatch, .invalidTemplate)
        XCTAssertNil(candidate.diagnostics)
    }

    func testAppendThrowsWhenParentPathIsAFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GestureTestLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: parentFile)
        let store = GestureTestLogStore(logURL: parentFile.appendingPathComponent("log.jsonl"))
        let evaluation = GestureRecognitionEvaluator.evaluate(
            path: PathTemplates.up.map(\.cgPoint),
            profiles: [],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )
        let entry = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: PathTemplates.up.map(\.cgPoint),
            evaluation: evaluation
        )

        XCTAssertThrowsError(try store.append(entry))
        try? FileManager.default.removeItem(at: directory)
    }

    func testReaderReportsMalformedJSONLineNumber() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GestureTestLogStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gesture-test-log.jsonl")
        let valid = """
        {"schemaVersion":1,"timestamp":"2026-07-16T00:00:00Z","sessionID":"10000000-0000-0000-0000-000000000001","selectedTrigger":"right","decision":"noCandidates","metrics":{"pointCount":2,"pathLength":10,"width":10,"height":0},"rawPath":[{"x":0,"y":0},{"x":10,"y":0}],"sampledPath":[],"candidates":[]}
        """
        try Data("\(valid)\n{broken}\n".utf8).write(to: url)

        XCTAssertThrowsError(try GestureTestLogStore(logURL: url).readEntries()) {
            guard case .invalidLine(let line, _) = $0 as? GestureTestLogReadError else {
                return XCTFail("Expected a line-numbered read error, got \($0)")
            }
            XCTAssertEqual(line, 2)
        }
    }
}
