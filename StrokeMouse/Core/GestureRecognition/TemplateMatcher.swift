import CoreGraphics
import Foundation

/// Direction-sensitive, ordered unistroke matching based on the published
/// $1/$N recognizer family. License notices ship with the app resources.
enum TemplateMatcher {
    enum MatchingMode: String, Sendable {
        case simpleSegmentCanonical
        case orderedPath
    }

    struct SegmentDiagnostics: Sendable {
        let angleDegrees: Double
        let lengthFraction: Double
    }

    struct Diagnostics: Sendable {
        let mode: MatchingMode?
        let distance: Double?
        let rotationDegrees: Int?
        let rawGeometryScore: Double
        let strokeSegments: [SegmentDiagnostics]
        let templateSegments: [SegmentDiagnostics]
    }

    struct Evaluation: Sendable {
        let score: Double
        let shapeScore: Double
        let structuralMismatch: StrokeStructureMatcher.Mismatch?
        let diagnostics: Diagnostics?
    }

    private struct SimilarityEvaluation {
        let score: Double
        let distance: Double
        let rotationDegrees: Int
    }

    private static let nearOneDimensionalRatio: CGFloat = 0.25
    private static let rotationToleranceDegrees = 12
    private static let scoreDistanceScale = 0.18

    /// Score in 0...1. A structurally incompatible stroke always returns zero.
    static func bestScore(
        _ stroke: [CGPoint],
        _ template: [CGPoint],
        sampleCount: Int = Constants.freePathSampleCount
    ) -> Double {
        evaluate(stroke, template, sampleCount: sampleCount).score
    }

    /// Detailed result for the in-app diagnostic tool. A structural mismatch
    /// remains non-compensating, while `shapeScore` shows the raw geometry score.
    static func evaluate(
        _ stroke: [CGPoint],
        _ template: [CGPoint],
        sampleCount: Int = Constants.freePathSampleCount
    ) -> Evaluation {
        let rawGeometry = orderedSimilarity(stroke, template, sampleCount: sampleCount)
        let structure = StrokeStructureMatcher.evaluate(stroke, template)
        guard let cores = structure.cores else {
            return Evaluation(
                score: 0,
                shapeScore: rawGeometry.score,
                structuralMismatch: structure.mismatch,
                diagnostics: diagnostics(
                    structure: structure,
                    finalSimilarity: nil,
                    rawGeometryScore: rawGeometry.score
                )
            )
        }

        let finalGeometry: SimilarityEvaluation
        if let canonical = canonicalPaths(
            strokeSegments: cores.strokeSegments,
            templateSegments: cores.templateSegments
        ) {
            finalGeometry = orderedSimilarity(
                canonical.stroke,
                canonical.template,
                sampleCount: sampleCount
            )
        } else {
            finalGeometry = orderedSimilarity(
                cores.stroke,
                cores.template,
                sampleCount: sampleCount
            )
        }
        return Evaluation(
            score: finalGeometry.score,
            shapeScore: rawGeometry.score,
            structuralMismatch: nil,
            diagnostics: diagnostics(
                structure: structure,
                finalSimilarity: finalGeometry,
                rawGeometryScore: rawGeometry.score
            )
        )
    }

    /// Ordered $1-style point similarity after $N-style 1D/2D normalization.
    static func similarity(
        _ stroke: [CGPoint],
        _ template: [CGPoint],
        sampleCount: Int = Constants.freePathSampleCount
    ) -> Double {
        orderedSimilarity(stroke, template, sampleCount: sampleCount).score
    }

    private static func orderedSimilarity(
        _ stroke: [CGPoint],
        _ template: [CGPoint],
        sampleCount: Int
    ) -> SimilarityEvaluation {
        guard sampleCount > 1,
              let sampledStroke = UnistrokeGeometry.resampledPath(stroke, count: sampleCount),
              let sampledTemplate = UnistrokeGeometry.resampledPath(template, count: sampleCount)
        else { return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0) }

        let uniformScale = UnistrokeGeometry.isNearOneDimensional(
            sampledStroke,
            threshold: nearOneDimensionalRatio
        ) || UnistrokeGeometry.isNearOneDimensional(
            sampledTemplate,
            threshold: nearOneDimensionalRatio
        )
        guard let normalizedTemplate = UnistrokeGeometry.normalize(
            sampledTemplate,
            uniform: uniformScale
        ) else {
            return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0)
        }

        var bestDistance = Double.infinity
        var bestRotation = 0
        for degrees in -rotationToleranceDegrees...rotationToleranceDegrees {
            let rotated = UnistrokeGeometry.rotate(
                sampledStroke,
                radians: CGFloat(degrees) * .pi / 180
            )
            guard let candidate = UnistrokeGeometry.normalize(rotated, uniform: uniformScale) else {
                continue
            }
            let distance = orderedPointDistance(candidate, normalizedTemplate)
            if distance < bestDistance {
                bestDistance = distance
                bestRotation = degrees
            }
        }

        guard bestDistance.isFinite else {
            return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0)
        }
        let score = min(1, max(0, exp(-bestDistance / scoreDistanceScale)))
        return SimilarityEvaluation(
            score: score,
            distance: bestDistance,
            rotationDegrees: bestRotation
        )
    }

    private static func canonicalPaths(
        strokeSegments: [StrokeStructureDescriptor],
        templateSegments: [StrokeStructureDescriptor]
    ) -> (stroke: [CGPoint], template: [CGPoint])? {
        guard (2...4).contains(templateSegments.count),
              strokeSegments.count == templateSegments.count,
              let stroke = canonicalPath(strokeSegments, lengthsFrom: templateSegments),
              let template = canonicalPath(templateSegments, lengthsFrom: templateSegments)
        else { return nil }
        return (stroke, template)
    }

    private static func canonicalPath(
        _ directions: [StrokeStructureDescriptor],
        lengthsFrom target: [StrokeStructureDescriptor]
    ) -> [CGPoint]? {
        guard directions.count == target.count, !directions.isEmpty else { return nil }
        var points = [CGPoint.zero]
        points.reserveCapacity(directions.count + 1)
        for (direction, targetSegment) in zip(directions, target) {
            guard targetSegment.lengthFraction > 0 else { return nil }
            let endpoint = CGPoint(
                x: points[points.count - 1].x
                    + direction.unitDirection.x * targetSegment.lengthFraction,
                y: points[points.count - 1].y
                    + direction.unitDirection.y * targetSegment.lengthFraction
            )
            points.append(endpoint)
        }
        return points
    }

    private static func diagnostics(
        structure: StrokeStructureMatcher.Evaluation,
        finalSimilarity: SimilarityEvaluation?,
        rawGeometryScore: Double
    ) -> Diagnostics {
        let mode: MatchingMode? = finalSimilarity.map { _ in
            (2...4).contains(structure.templateSegments.count)
                ? .simpleSegmentCanonical
                : .orderedPath
        }
        return Diagnostics(
            mode: mode,
            distance: finalSimilarity?.distance,
            rotationDegrees: finalSimilarity?.rotationDegrees,
            rawGeometryScore: rawGeometryScore,
            strokeSegments: structure.strokeSegments.map(segmentDiagnostics),
            templateSegments: structure.templateSegments.map(segmentDiagnostics)
        )
    }

    private static func segmentDiagnostics(
        _ segment: StrokeStructureDescriptor
    ) -> SegmentDiagnostics {
        SegmentDiagnostics(
            angleDegrees: segment.angleDegrees,
            lengthFraction: Double(segment.lengthFraction)
        )
    }

    private static func orderedPointDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        let total = zip(a, b).reduce(0.0) { partial, pair in
            partial + hypot(Double(pair.0.x - pair.1.x), Double(pair.0.y - pair.1.y))
        }
        return total / Double(a.count)
    }
}
