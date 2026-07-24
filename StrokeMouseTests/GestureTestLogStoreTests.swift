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
            minimumLength: 0
        )
        let sessionID = UUID()
        let entry = GestureTestLogEntry(
            sessionID: sessionID,
            rawPath: GestureRecognitionTestSupport.recordedNarrowPeak,
            evaluation: evaluation
        )

        XCTAssertEqual(entry.schemaVersion, 3)
        let diagnostics = try XCTUnwrap(entry.candidates.first?.diagnostics)
        let templatePath = try XCTUnwrap(entry.candidates.first?.templatePath)
        XCTAssertEqual(templatePath.count, Constants.freePathSampleCount)
        XCTAssertEqual(templatePath.map(\.x).reduce(0, +), 0, accuracy: 1e-10)
        XCTAssertEqual(templatePath.map(\.y).reduce(0, +), 0, accuracy: 1e-10)
        XCTAssertEqual(diagnostics.matchingMode, "simpleSegmentCanonical")
        XCTAssertEqual(diagnostics.strokeSegments.count, 2)
        XCTAssertEqual(diagnostics.templateSegments.count, 2)
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
        XCTAssertEqual(decoded[0].candidates.first?.profileName, "Peak")
        XCTAssertEqual(
            decoded[0].candidates.first?.templatePath?.count,
            Constants.freePathSampleCount
        )
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
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy")
        XCTAssertNil(entry.candidates.first?.diagnostics)
        XCTAssertNil(entry.candidates.first?.templatePath)
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
        XCTAssertEqual(entry.candidates.first?.profileName, "Legacy v2")
        XCTAssertNotNil(entry.candidates.first?.diagnostics)
        XCTAssertNil(entry.candidates.first?.templatePath)
    }

    func testStructuralRejectionLeavesFinalGeometryDiagnosticsEmpty() throws {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let profile = GestureProfile(
            name: "Peak",
            pattern: .freePath(template.map(CodablePoint.init)),
            action: .none
        )
        let rejected = GestureRecognitionTestSupport.appendingTail(
            to: template,
            lengthFraction: 0.30,
            angleDegrees: 0
        )
        let evaluation = GestureRecognitionEvaluator.evaluate(
            path: rejected,
            profiles: [profile],
            button: .right,
            minimumLength: 0
        )

        let entry = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: rejected,
            evaluation: evaluation
        )
        let candidate = try XCTUnwrap(entry.candidates.first)
        let diagnostics = try XCTUnwrap(candidate.diagnostics)

        XCTAssertEqual(candidate.score, 0)
        XCTAssertNotNil(candidate.structuralMismatch)
        XCTAssertNil(diagnostics.matchingMode)
        XCTAssertNil(diagnostics.distance)
        XCTAssertNil(diagnostics.rotationDegrees)
        XCTAssertGreaterThan(diagnostics.rawGeometryScore, 0)
        XCTAssertEqual(diagnostics.finalScore, 0)
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
            minimumLength: 0
        )
        let entry = GestureTestLogEntry(
            sessionID: UUID(),
            rawPath: PathTemplates.up.map(\.cgPoint),
            evaluation: evaluation
        )

        XCTAssertThrowsError(try store.append(entry))
        try? FileManager.default.removeItem(at: directory)
    }
}
