import CoreGraphics
import Foundation

struct GestureTestPathMetrics: Codable, Sendable {
    let pointCount: Int
    let pathLength: Double
    let width: Double
    let height: Double
}

struct GestureTestLogRecognitionPolicy: Codable, Sendable, Equatable {
    let minimumPathLength: Double
    let matchThreshold: Double
    let minimumLeadOverSecond: Double

    init(_ policy: GestureRecognitionPolicy) {
        minimumPathLength = Double(policy.minimumPathLength)
        matchThreshold = policy.matchThreshold
        minimumLeadOverSecond = policy.minimumLeadOverSecond
    }
}

struct GestureTestLogSegmentDiagnostics: Codable, Sendable, Equatable {
    let angleDegrees: Double
    let lengthFraction: Double
}

struct GestureTestLogMatchDiagnostics: Codable, Sendable, Equatable {
    let matchingMode: String?
    let distance: Double?
    let rotationDegrees: Int?
    let rawGeometryScore: Double
    let finalScore: Double
    let strokeSegments: [GestureTestLogSegmentDiagnostics]
    let templateSegments: [GestureTestLogSegmentDiagnostics]

    init(_ diagnostics: TemplateMatcher.Diagnostics, finalScore: Double) {
        matchingMode = diagnostics.mode?.rawValue
        distance = diagnostics.distance
        rotationDegrees = diagnostics.rotationDegrees
        rawGeometryScore = diagnostics.rawGeometryScore
        self.finalScore = finalScore
        strokeSegments = diagnostics.strokeSegments.map {
            GestureTestLogSegmentDiagnostics(
                angleDegrees: $0.angleDegrees,
                lengthFraction: $0.lengthFraction
            )
        }
        templateSegments = diagnostics.templateSegments.map {
            GestureTestLogSegmentDiagnostics(
                angleDegrees: $0.angleDegrees,
                lengthFraction: $0.lengthFraction
            )
        }
    }
}

struct GestureTestLogCandidate: Codable, Sendable {
    let profileID: UUID
    let profileName: String
    let score: Double
    let shapeScore: Double
    let structuralMismatch: StrokeStructureMatcher.Mismatch?
    /// Normalized 32-point template; optional so schema-v1/v2 lines remain decodable.
    let templatePath: [CodablePoint]?
    let diagnostics: GestureTestLogMatchDiagnostics?
}

struct GestureTestLogEntry: Codable, Sendable {
    let schemaVersion: Int
    let timestamp: Date
    let sessionID: UUID
    let selectedTrigger: MouseTriggerButton
    let decision: GestureEvaluationDecision
    let acceptedProfileID: UUID?
    let acceptedProfileName: String?
    /// Optional so schema-v1/v2/v3 lines remain decodable.
    let policy: GestureTestLogRecognitionPolicy?
    let metrics: GestureTestPathMetrics
    let rawPath: [CodablePoint]
    let sampledPath: [CodablePoint]
    let candidates: [GestureTestLogCandidate]

    init(
        sessionID: UUID,
        rawPath: [CGPoint],
        evaluation: GestureRecognitionEvaluation,
        timestamp: Date = Date()
    ) {
        let accepted = evaluation.acceptedCandidate
        schemaVersion = 4
        self.timestamp = timestamp
        self.sessionID = sessionID
        selectedTrigger = evaluation.button
        decision = evaluation.decision
        acceptedProfileID = accepted?.profile.id
        acceptedProfileName = accepted?.profile.name
        policy = GestureTestLogRecognitionPolicy(evaluation.policy)
        metrics = Self.metrics(for: rawPath, pathLength: evaluation.pathLength)
        self.rawPath = rawPath.map(CodablePoint.init)
        sampledPath = (UnistrokeGeometry.resampledPath(
            rawPath,
            count: Constants.freePathSampleCount
        ) ?? []).map(CodablePoint.init)
        candidates = evaluation.candidates.map { candidate in
            GestureTestLogCandidate(
                profileID: candidate.profile.id,
                profileName: candidate.profile.name,
                score: candidate.score,
                shapeScore: candidate.shapeScore,
                structuralMismatch: candidate.structuralMismatch,
                templatePath: Self.normalizedTemplatePath(for: candidate.profile),
                diagnostics: candidate.diagnostics.map {
                    GestureTestLogMatchDiagnostics($0, finalScore: candidate.score)
                }
            )
        }
    }

    private static func normalizedTemplatePath(
        for profile: GestureProfile
    ) -> [CodablePoint]? {
        let points = profile.pattern.freePathPoints.map(\.cgPoint)
        guard let sampled = UnistrokeGeometry.resampledPath(
            points,
            count: Constants.freePathSampleCount
        ), let normalized = UnistrokeGeometry.normalize(sampled, uniform: true) else {
            return nil
        }
        return normalized.map(CodablePoint.init)
    }

    private static func metrics(
        for points: [CGPoint],
        pathLength: CGFloat
    ) -> GestureTestPathMetrics {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        return GestureTestPathMetrics(
            pointCount: points.count,
            pathLength: Double(pathLength),
            width: Double(width),
            height: Double(height)
        )
    }
}

struct GestureTestLogStore {
    let logURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        logURL = support
            .appendingPathComponent(Constants.supportDirectoryName, isDirectory: true)
            .appendingPathComponent(Constants.gestureTestLogFileName)
    }

    init(logURL: URL) {
        self.logURL = logURL
    }

    func append(_ entry: GestureTestLogEntry, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var line = try JSONEncoder.gestureTestEncoder.encode(entry)
        line.append(0x0A)

        guard fileManager.fileExists(atPath: logURL.path) else {
            try line.write(to: logURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.synchronize()
            try handle.close()
        } catch {
            handle.closeFile()
            throw error
        }
    }
}

extension JSONEncoder {
    static var gestureTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var gestureTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
