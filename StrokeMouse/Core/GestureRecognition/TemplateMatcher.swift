import CoreGraphics
import Foundation

/// Direction-sensitive, ordered unistroke matching. Every drawn template uses
/// the same elastic comparison and score scale, so candidates from different
/// shape families rank against each other fairly.
enum TemplateMatcher {
    static let algorithmVersion = "elastic-path-v3"

    enum MatchingMode: String, Sendable {
        case elasticPath
    }

    /// Why an evaluation could not produce a score. Only the invalid cases
    /// are produced today; the remaining raw values keep diagnostic logs
    /// written by earlier structural gates decodable.
    enum Mismatch: String, Codable, Sendable, Equatable {
        case invalidStroke
        case invalidTemplate
        case terminalOverrun
        case segmentCount
        case segmentProportion
        case lineDirection
        case startDirection
        case turnDirection
        case turnAngle
        case endpointDirection
    }

    struct Diagnostics: Sendable {
        let mode: MatchingMode?
        let distance: Double?
        let rawGeometryScore: Double
    }

    struct Evaluation: Sendable {
        let score: Double
        let shapeScore: Double
        let structuralMismatch: Mismatch?
        let diagnostics: Diagnostics?
    }

    /// Precomputed per-path profiles. The stroke side is prepared once per
    /// recognition pass; template preparations are cached across passes.
    struct PreparedPath: Sendable {
        let points: [CGPoint]
        let profile: ElasticPathProfile?
        /// Coarse whole-path and leading-portion profiles, longest first,
        /// used only by live HUD feedback.
        let liveProfiles: [ElasticPathProfile]
    }

    private static let livePrefixFractions: [CGFloat] = [
        0.10, 0.20, 0.30, 0.40, 0.50, 0.65, 0.80,
    ]

    static func prepare(_ points: [CGPoint]) -> PreparedPath {
        let profile = ElasticPathProfile(points)
        let live = profile == nil ? [] : ([1] + livePrefixFractions.reversed()).compactMap {
            ElasticPathProfile(
                UnistrokeGeometry.trimmingTerminalFraction(points, 1 - $0),
                sampleCount: ElasticPathMatcher.liveSampleCount
            )
        }
        return PreparedPath(points: points, profile: profile, liveProfiles: live)
    }

    /// Score in 0...1.
    static func bestScore(_ stroke: [CGPoint], _ template: [CGPoint]) -> Double {
        evaluate(stroke, template).score
    }

    static func evaluate(_ stroke: [CGPoint], _ template: [CGPoint]) -> Evaluation {
        evaluate(stroke: prepare(stroke), template: prepare(template))
    }

    static func evaluate(stroke: PreparedPath, template: PreparedPath) -> Evaluation {
        guard let strokeProfile = stroke.profile else { return rejection(.invalidStroke) }
        guard let templateProfile = template.profile else { return rejection(.invalidTemplate) }
        let distance = ElasticPathMatcher.distance(strokeProfile, templateProfile)
        let score = ElasticPathMatcher.score(distance: distance)
        return Evaluation(
            score: score,
            shapeScore: score,
            structuralMismatch: nil,
            diagnostics: Diagnostics(
                mode: .elasticPath,
                distance: distance.isFinite ? distance : nil,
                rawGeometryScore: score
            )
        )
    }

    /// HUD-only check: can the in-progress stroke still become this template?
    /// Compares coarse profiles of the whole template and its leading
    /// portions. The mean cost is a lower bound of the final distance, so it
    /// screens candidates cheaply before the full distance is computed.
    /// Final recognition never uses prefixes.
    static func liveMeetsThreshold(
        stroke: PreparedPath,
        template: PreparedPath,
        threshold: Double
    ) -> Bool {
        guard let strokeProfile = stroke.liveProfiles.first else { return false }
        let limit = ElasticPathMatcher.maximumDistance(forScore: threshold)
        return template.liveProfiles.contains { candidate in
            ElasticPathMatcher.meanDistance(strokeProfile, candidate, abandonAbove: limit) <= limit
                && ElasticPathMatcher.distance(strokeProfile, candidate) <= limit
        }
    }

    private static func rejection(_ mismatch: Mismatch) -> Evaluation {
        Evaluation(score: 0, shapeScore: 0, structuralMismatch: mismatch, diagnostics: nil)
    }
}
