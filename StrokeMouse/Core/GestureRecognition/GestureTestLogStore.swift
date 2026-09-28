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
        // A non-finite distance means the matcher did not produce a usable
        // distance; represent that explicitly instead of making JSON fail.
        distance = diagnostics.distance.flatMap { $0.isFinite ? $0 : nil }
        // Rotation search and segment signatures belonged to the structural
        // matchers; the fields stay so earlier log lines keep decoding.
        rotationDegrees = nil
        rawGeometryScore = diagnostics.rawGeometryScore
        self.finalScore = finalScore
        strokeSegments = []
        templateSegments = []
    }
}

enum GestureTestLogSource: String, Codable, Equatable, Sendable {
    case canvas
    case mouseRuntime
    case modifierRuntime
}

enum GestureTestLogEvaluationTier: String, Codable, Equatable, Sendable {
    case application
    case group
    case global
}

enum GestureTestLogOutcome: String, Codable, Equatable, Sendable {
    case recognition
    case cancelled
}

enum GestureTestLogEntryError: Error, Equatable {
    case notCancelled
    case unsupportedSource
}

struct GestureTestLogTemplateEvaluation: Codable, Sendable {
    let finalScore: Double
    let shapeScore: Double
    let structuralMismatch: TemplateMatcher.Mismatch?
    let diagnostics: GestureTestLogMatchDiagnostics?
}

struct GestureTestLogCandidate: Codable, Sendable {
    let profileID: UUID
    let profileName: String
    let score: Double
    let shapeScore: Double
    let structuralMismatch: TemplateMatcher.Mismatch?
    /// Normalized sampled template; optional so schema-v1/v2 lines remain decodable.
    let templatePath: [CodablePoint]?
    /// Exact persisted template; optional so schema-v1/v2/v3/v4 lines remain decodable.
    let sourceTemplatePath: [CodablePoint]?
    /// All exact persisted templates, in profile order; added in schema v6.
    let sourceTemplatePaths: [[CodablePoint]]?
    let winningTemplateIndex: Int?
    let templateEvaluations: [GestureTestLogTemplateEvaluation]?
    let diagnostics: GestureTestLogMatchDiagnostics?
}

struct GestureTestLogEntry: Codable, Sendable {
    let schemaVersion: Int
    let timestamp: Date
    let sessionID: UUID
    /// Added in schema v6. Legacy entries have no trustworthy input source.
    let source: GestureTestLogSource?
    let activation: DrawActivation?
    let outcome: GestureTestLogOutcome?
    let algorithmVersion: String?
    let configurationRevision: UInt64?
    /// Candidates contain only this already-selected scope tier.
    let evaluationTier: GestureTestLogEvaluationTier?
    let selectedTrigger: MouseTriggerButton
    let decision: GestureEvaluationDecision?
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
        source: GestureTestLogSource = .canvas,
        activation: DrawActivation? = nil,
        configurationRevision: UInt64? = nil,
        timestamp: Date = Date()
    ) {
        let accepted = evaluation.acceptedCandidate
        schemaVersion = 6
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.source = source
        let resolvedActivation = activation ?? .mouse(
            GestureTrigger(button: evaluation.button)
        )
        self.activation = resolvedActivation
        outcome = .recognition
        algorithmVersion = TemplateMatcher.algorithmVersion
        self.configurationRevision = configurationRevision
        evaluationTier = evaluation.candidates.first.map {
            Self.evaluationTier(for: $0.profile.scope)
        }
        if case .mouse(let trigger) = resolvedActivation {
            selectedTrigger = trigger.button
        } else {
            selectedTrigger = evaluation.button
        }
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
            let allSourcePaths = Self.sourceTemplatePaths(for: candidate.profile)
            return GestureTestLogCandidate(
                profileID: candidate.profile.id,
                profileName: candidate.profile.name,
                score: candidate.score,
                shapeScore: candidate.shapeScore,
                structuralMismatch: candidate.structuralMismatch,
                templatePath: Self.normalizedTemplatePath(for: candidate.profile),
                sourceTemplatePath: allSourcePaths?.first,
                sourceTemplatePaths: allSourcePaths,
                winningTemplateIndex: candidate.winningTemplateIndex,
                templateEvaluations: candidate.templateEvaluations.map { item in
                    GestureTestLogTemplateEvaluation(
                        finalScore: item.score,
                        shapeScore: item.shapeScore,
                        structuralMismatch: item.structuralMismatch,
                        diagnostics: item.diagnostics.map {
                            GestureTestLogMatchDiagnostics(
                                $0,
                                finalScore: item.score
                            )
                        }
                    )
                },
                diagnostics: candidate.diagnostics.map {
                    GestureTestLogMatchDiagnostics($0, finalScore: candidate.score)
                }
            )
        }
    }

    init(
        sessionID: UUID,
        cancelledDiagnostic diagnostic: GestureDrawDiagnostic,
        timestamp: Date = Date()
    ) throws {
        guard diagnostic.evaluation == nil,
              diagnostic.outcome == .cancelled
        else {
            throw GestureTestLogEntryError.notCancelled
        }
        let resolvedSource: GestureTestLogSource
        let resolvedActivation: DrawActivation
        switch diagnostic.source {
        case .mouse(let button):
            resolvedSource = .mouseRuntime
            resolvedActivation = .mouse(GestureTrigger(button: button))
            selectedTrigger = button
        case .modifier(let key):
            resolvedSource = .modifierRuntime
            resolvedActivation = .modifier(key)
            selectedTrigger = .right
        case .multitouch:
            throw GestureTestLogEntryError.unsupportedSource
        }
        schemaVersion = 6
        self.timestamp = timestamp
        self.sessionID = sessionID
        source = resolvedSource
        activation = resolvedActivation
        outcome = .cancelled
        algorithmVersion = TemplateMatcher.algorithmVersion
        configurationRevision = diagnostic.configurationRevision
        evaluationTier = nil
        decision = nil
        acceptedProfileID = nil
        acceptedProfileName = nil
        policy = nil
        metrics = Self.metrics(
            for: diagnostic.path,
            pathLength: PathSimplifier.pathLength(diagnostic.path)
        )
        rawPath = diagnostic.path.map(CodablePoint.init)
        sampledPath = (UnistrokeGeometry.resampledPath(
            diagnostic.path,
            count: Constants.freePathSampleCount
        ) ?? []).map(CodablePoint.init)
        candidates = []
    }

    private static func sourceTemplatePaths(
        for profile: GestureProfile
    ) -> [[CodablePoint]]? {
        guard case .drawn(let drawn) = profile.input else { return nil }
        return drawn.allPaths
    }

    private static func normalizedTemplatePath(
        for profile: GestureProfile
    ) -> [CodablePoint]? {
        guard case .drawn(let drawn) = profile.input else { return nil }
        let points = drawn.points.map(\.cgPoint)
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

    private static func evaluationTier(
        for scope: AppScope
    ) -> GestureTestLogEvaluationTier {
        switch scope {
        case .apps: return .application
        case .group: return .group
        case .global: return .global
        }
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

    func readEntries() throws -> [GestureTestLogEntry] {
        let data = try Data(contentsOf: logURL)
        return try data.split(separator: 0x0A, omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, line in
                guard line.contains(where: { !$0.isASCIIWhitespace }) else {
                    return nil
                }
                do {
                    let entry = try JSONDecoder.gestureTestDecoder.decode(
                        GestureTestLogEntry.self,
                        from: Data(line)
                    )
                    try GestureTestLogReplay.validate(entry)
                    return entry
                } catch {
                    throw GestureTestLogReadError.invalidLine(
                        line: offset + 1,
                        detail: error.localizedDescription
                    )
                }
            }
    }
}

enum GestureTestLogReadError: Error, Equatable, LocalizedError {
    case invalidLine(line: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidLine(let line, let detail):
            return String(
                format: L10n.string("gestureTest.replayReadLineError"),
                locale: L10n.locale,
                line,
                detail
            )
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0D
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
