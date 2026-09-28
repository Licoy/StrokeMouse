import XCTest
@testable import StrokeMouse

@MainActor
final class MultiSampleGestureTests: XCTestCase {
    func testLegacyDecodeDefaultsAdditionalPathsAndEmptyEncodingOmitsField()
        throws
    {
        let data = Data(
            """
            {
              "activation": {
                "type": "mouse",
                "trigger": {"button": "right"}
              },
              "points": [{"x": 0, "y": 0}, {"x": 0, "y": 1}]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(DrawnGesture.self, from: data)
        XCTAssertEqual(decoded.additionalPaths, [])
        XCTAssertEqual(decoded.allPaths, [decoded.points])

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(decoded)
            ) as? [String: Any]
        )
        XCTAssertNil(object["additionalPaths"])
    }

    func testOneThreeAndFiveSamplesRoundTripWithoutChangingPrimary() throws {
        let primary = PathTemplates.up
        let extras = [
            PathTemplates.down,
            PathTemplates.left,
            PathTemplates.right,
            GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init),
        ]

        for sampleCount in [1, 3, 5] {
            let gesture = DrawnGesture(
                activation: .mouse(.default),
                points: primary,
                additionalPaths: Array(extras.prefix(sampleCount - 1))
            )
            let decoded = try JSONDecoder().decode(
                DrawnGesture.self,
                from: JSONEncoder().encode(gesture)
            )

            XCTAssertEqual(decoded.points, primary)
            XCTAssertEqual(decoded.allPaths.count, sampleCount)
            XCTAssertEqual(decoded, gesture)
        }
    }

    func testSameProfileSamplesProduceOneCandidateButOtherProfileSetsMargin() {
        let path = GestureRecognitionTestSupport.recordedNarrowPeak
        let samples = [
            PathTemplates.up,
            path.map(CodablePoint.init),
            PathTemplates.down,
        ]
        let multiSample = profile(name: "Multi", paths: samples)

        let alone = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [multiSample],
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(alone.decision, .accepted)
        XCTAssertEqual(alone.candidates.count, 1)
        XCTAssertEqual(alone.acceptedCandidate?.profile.id, multiSample.id)
        XCTAssertEqual(alone.acceptedCandidate?.winningTemplateIndex, 1)
        XCTAssertEqual(alone.acceptedCandidate?.templateEvaluations.count, 3)

        let competing = profile(
            name: "Competing",
            paths: [path.map(CodablePoint.init)]
        )
        let withCompetitor = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [multiSample, competing],
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(withCompetitor.decision, .ambiguous)
        XCTAssertEqual(withCompetitor.candidates.count, 2)
    }

    func testWinnerFieldsAndDiagnosticsComeFromWinningSample() throws {
        let path = GestureRecognitionTestSupport.recordedNarrowPeak
        let gesture = profile(
            name: "Winner",
            paths: [PathTemplates.left, path.map(CodablePoint.init)]
        )
        let result = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [gesture],
            policy: .standard(minimumPathLength: 0)
        )
        let candidate = try XCTUnwrap(result.candidates.first)
        let winner = candidate.templateEvaluations[candidate.winningTemplateIndex]

        XCTAssertEqual(candidate.winningTemplateIndex, 1)
        XCTAssertEqual(candidate.score, winner.score)
        XCTAssertEqual(candidate.shapeScore, winner.shapeScore)
        XCTAssertEqual(candidate.structuralMismatch, winner.structuralMismatch)
        XCTAssertEqual(
            candidate.diagnostics?.rawGeometryScore,
            winner.diagnostics?.rawGeometryScore
        )

        let tied = profile(
            name: "Tie",
            paths: [path, path].map { $0.map(CodablePoint.init) }
        )
        let tieResult = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [tied],
            policy: .standard(minimumPathLength: 0)
        )
        XCTAssertEqual(tieResult.candidates.first?.winningTemplateIndex, 0)
    }

    func testTemplateCacheTracksFullCollectionAcrossEditAndIDReuse() {
        let id = UUID()
        let cache = GestureTemplateCache()
        let original = [PathTemplates.up, PathTemplates.down].map {
            $0.map(\.cgPoint)
        }
        let edited = [PathTemplates.left].map { $0.map(\.cgPoint) }
        let recreated = [PathTemplates.right].map { $0.map(\.cgPoint) }

        XCTAssertEqual(
            cache.preparedPaths(id: id, paths: original).map(\.points),
            original
        )
        XCTAssertEqual(
            cache.preparedPaths(id: id, paths: edited).map(\.points),
            edited
        )
        XCTAssertEqual(
            cache.preparedPaths(id: id, paths: recreated).map(\.points),
            recreated
        )
    }

    func testExportImportAndBackupPreserveEverySample() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ConfigStore(configURL: directory.appendingPathComponent("source.json"))
        let gesture = profile(
            name: "Portable",
            paths: [PathTemplates.up, PathTemplates.left, PathTemplates.right]
        )
        source.replaceAll([gesture])

        let backup = try source.makeBackupGestureFile()
        XCTAssertEqual(backup.gestures, [gesture])

        let package = try source.exportPackage(ids: [gesture.id])
        let exported = try JSONDecoder().decode(GestureConfigFile.self, from: package)
        XCTAssertEqual(exported.version, 2)
        XCTAssertEqual(exported.gestures, [gesture])

        let destination = ConfigStore(
            configURL: directory.appendingPathComponent("destination.json")
        )
        destination.replaceAll([])
        _ = try destination.importPackage(from: package)
        XCTAssertEqual(destination.gestures.first?.input, gesture.input)
    }

    func testMalformedAdditionalSamplesAreRejectedForBackupAndImport() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigStore(configURL: directory.appendingPathComponent("gestures.json"))
        let zeroLength = profile(
            name: "Zero",
            paths: [
                PathTemplates.up,
                [CodablePoint(x: 4, y: 4), CodablePoint(x: 4, y: 4)],
            ]
        )
        XCTAssertThrowsError(try store.validateBackupGestureFile(file(zeroLength))) {
            XCTAssertEqual(
                $0 as? ConfigStoreFailure,
                .invalidConfiguration(.zeroLengthDrawnPath(zeroLength.id))
            )
        }

        let tooMany = profile(
            name: "Too many",
            paths: Array(repeating: PathTemplates.up, count: 6)
        )
        let package = try JSONEncoder().encode(file(tooMany))
        XCTAssertThrowsError(try store.analyzeImportPackage(from: package)) {
            XCTAssertEqual(
                $0 as? ConfigStoreFailure,
                .invalidConfiguration(.tooManyDrawnSamples(tooMany.id))
            )
        }

        let nonFinite = profile(
            name: "Non-finite",
            paths: [
                PathTemplates.up,
                [CodablePoint(x: 0, y: 0), CodablePoint(x: .infinity, y: 1)],
            ]
        )
        XCTAssertThrowsError(try store.validateBackupGestureFile(file(nonFinite))) {
            XCTAssertEqual(
                $0 as? ConfigStoreFailure,
                .invalidConfiguration(.nonFiniteDrawnPoint(nonFinite.id))
            )
        }
    }

    private func profile(
        name: String,
        paths: [[CodablePoint]]
    ) -> GestureProfile {
        GestureProfile(
            name: name,
            input: .drawn(DrawnGesture(
                activation: .mouse(.default),
                points: paths[0],
                additionalPaths: Array(paths.dropFirst())
            ))
        )
    }

    private func file(_ gesture: GestureProfile) -> GestureConfigFile {
        GestureConfigFile(version: Constants.configVersion, gestures: [gesture])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "StrokeMouseMultiSampleTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
