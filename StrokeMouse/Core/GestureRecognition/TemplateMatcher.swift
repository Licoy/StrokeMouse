import CoreGraphics
import Foundation

/// Direction-sensitive, ordered unistroke matching based on the published
/// $1/$N recognizer family. License notices ship with the app resources.
enum TemplateMatcher {
    static let algorithmVersion = "curve-signature-v2"

    enum MatchingMode: String, Sendable {
        case singleTurnCanonical
        case simpleSegmentCanonical
        case orderedPath
        case curveOrderedPath
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

    /// Precomputed per-path geometry (resampling + structural signature). The
    /// stroke side is prepared once per recognition pass instead of once per
    /// candidate template; template preparations can additionally be cached
    /// across passes because templates rarely change.
    struct PreparedPath {
        let points: [CGPoint]
        let sampleCount: Int
        let shapeSamples: [CGPoint]?
        let extraction: StrokeStructureExtraction
        let curveSignature: CurvePathSignature?
        /// Template-side flag; derived purely from these points so it can be
        /// precomputed regardless of which side the path ends up on.
        let flexibleSingleTurn: Bool
    }

    static func prepare(
        _ points: [CGPoint],
        sampleCount: Int = Constants.freePathSampleCount
    ) -> PreparedPath {
        let extraction = StrokeStructureExtractor.extract(points)
        let flexibleSingleTurn = extraction.signature.map { signature in
            StrokeStructureMatcher.usesFlexibleSingleTurn(
                points,
                segments: signature.descriptors
            )
        } ?? false
        return PreparedPath(
            points: points,
            sampleCount: sampleCount,
            shapeSamples: UnistrokeGeometry.resampledPath(points, count: sampleCount),
            extraction: extraction,
            curveSignature: CurvePathSignature.make(points),
            flexibleSingleTurn: flexibleSingleTurn
        )
    }

    private struct SimilarityEvaluation {
        let score: Double
        let distance: Double
        let rotationDegrees: Int
        let structuralMismatch: StrokeStructureMatcher.Mismatch?

        init(
            score: Double,
            distance: Double,
            rotationDegrees: Int,
            structuralMismatch: StrokeStructureMatcher.Mismatch? = nil
        ) {
            self.score = score
            self.distance = distance
            self.rotationDegrees = rotationDegrees
            self.structuralMismatch = structuralMismatch
        }
    }

    private static let nearOneDimensionalRatio: CGFloat = 0.25
    private static let rotationToleranceDegrees = 12
    private static let scoreDistanceScale = 0.18
    private static let curveScoreDistanceScale = 0.24
    /// Keeps the existing 55° turn budget meaningful after intermediate segments
    /// are intentionally removed from a rounded-turn canonical path.
    private static let singleTurnScoreDistanceScale = 0.36

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
        evaluate(
            stroke: prepare(stroke, sampleCount: sampleCount),
            template: prepare(template, sampleCount: sampleCount),
            sampleCount: sampleCount
        )
    }

    /// Prepared-path variant that skips all redundant per-side precomputation.
    static func evaluate(
        stroke: PreparedPath,
        template: PreparedPath,
        sampleCount: Int = Constants.freePathSampleCount
    ) -> Evaluation {
        if template.curveSignature?.isCurve == true,
           !template.flexibleSingleTurn {
            return evaluateCurve(
                stroke: stroke,
                template: template,
                sampleCount: sampleCount
            )
        }

        let rawGeometry = orderedSimilarity(
            sampledStroke: shapeSamples(of: stroke, sampleCount: sampleCount),
            sampledTemplate: shapeSamples(of: template, sampleCount: sampleCount),
            sampleCount: sampleCount
        )
        let structure = StrokeStructureMatcher.evaluate(
            stroke.points,
            template.points,
            strokeExtraction: stroke.extraction,
            templateExtraction: template.extraction,
            templateFlexibleSingleTurn: template.flexibleSingleTurn
        )
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
            templateSegments: cores.templateSegments,
            flexibleSingleTurn: structure.usesFlexibleSingleTurn
        ) {
            let distanceScale = structure.usesFlexibleSingleTurn
                ? singleTurnScoreDistanceScale
                : scoreDistanceScale
            finalGeometry = orderedSimilarity(
                canonical.stroke,
                canonical.template,
                sampleCount: sampleCount,
                distanceScale: distanceScale
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

    private static func evaluateCurve(
        stroke: PreparedPath,
        template: PreparedPath,
        sampleCount: Int
    ) -> Evaluation {
        let optimisticGeometry = orderedSimilarity(
            sampledStroke: shapeSamples(of: stroke, sampleCount: sampleCount),
            sampledTemplate: shapeSamples(of: template, sampleCount: sampleCount),
            sampleCount: sampleCount
        )
        let structure = StrokeStructureMatcher.evaluate(
            stroke.points,
            template.points,
            strokeExtraction: stroke.extraction,
            templateExtraction: template.extraction,
            templateFlexibleSingleTurn: template.flexibleSingleTurn
        )
        guard let strokeSignature = stroke.curveSignature,
              let templateSignature = template.curveSignature else {
            return curveRejection(
                structure: structure,
                mismatch: .segmentCount,
                shapeScore: optimisticGeometry.score
            )
        }
        if let mismatch = strokeSignature.mismatch(with: templateSignature) {
            return curveRejection(
                structure: structure,
                mismatch: mismatch,
                shapeScore: optimisticGeometry.score
            )
        }

        let geometry = curveSimilarity(
            sampledStroke: shapeSamples(of: stroke, sampleCount: sampleCount),
            sampledTemplate: shapeSamples(of: template, sampleCount: sampleCount),
            sampleCount: sampleCount
        )
        if let mismatch = geometry.structuralMismatch {
            return curveRejection(
                structure: structure,
                mismatch: mismatch,
                shapeScore: geometry.score
            )
        }
        return Evaluation(
            score: geometry.score,
            shapeScore: geometry.score,
            structuralMismatch: nil,
            diagnostics: diagnostics(
                structure: structure,
                finalSimilarity: geometry,
                rawGeometryScore: geometry.score,
                forceOrderedPath: true
            )
        )
    }

    private static func curveRejection(
        structure: StrokeStructureMatcher.Evaluation,
        mismatch: StrokeStructureMatcher.Mismatch,
        shapeScore: Double
    ) -> Evaluation {
        Evaluation(
            score: 0,
            shapeScore: shapeScore,
            structuralMismatch: mismatch,
            diagnostics: diagnostics(
                structure: structure,
                finalSimilarity: nil,
                rawGeometryScore: shapeScore,
                forceOrderedPath: true
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

    /// Optimistic HUD-only score against plausible prefixes of a curve.
    /// Final matching never calls this path.
    static func liveCurvePrefixScore(
        stroke: PreparedPath,
        template: PreparedPath
    ) -> Double {
        guard template.curveSignature?.isCurve == true,
              !template.flexibleSingleTurn,
              stroke.curveSignature != nil else { return 0 }
        return [0.20, 0.35, 0.50, 0.65, 0.80].reduce(0) { best, fraction in
            let prefix = UnistrokeGeometry.trimmingTerminalFraction(
                template.points,
                CGFloat(1 - fraction)
            )
            let evaluation = curveSimilarity(
                sampledStroke: shapeSamples(
                    of: stroke,
                    sampleCount: Constants.freePathSampleCount
                ),
                sampledTemplate: UnistrokeGeometry.resampledPath(
                    prefix,
                    count: Constants.freePathSampleCount
                ),
                sampleCount: Constants.freePathSampleCount,
                usesAlignment: false
            )
            return max(best, evaluation.score)
        }
    }

    /// Threshold-only HUD check. Position distance is a lower bound for the
    /// final position-plus-tangent cost, so an over-budget rotation can stop
    /// before tangent work without changing the viability result.
    static func liveCurvePrefixMeetsThreshold(
        stroke: PreparedPath,
        template: PreparedPath,
        threshold: Double
    ) -> Bool {
        guard threshold > 0, threshold < 1,
              template.curveSignature?.isCurve == true,
              !template.flexibleSingleTurn,
              let sampledStroke = shapeSamples(
                of: stroke,
                sampleCount: Constants.freePathSampleCount
              ) else { return false }
        let maximumDistance = -log(threshold) * scoreDistanceScale
        return [0.20, 0.35, 0.50, 0.65, 0.80].contains { fraction in
            let prefix = UnistrokeGeometry.trimmingTerminalFraction(
                template.points,
                CGFloat(1 - fraction)
            )
            guard let sampledTemplate = UnistrokeGeometry.resampledPath(
                prefix,
                count: Constants.freePathSampleCount
            ) else { return false }
            return curvePrefixMeetsThreshold(
                sampledStroke: sampledStroke,
                sampledTemplate: sampledTemplate,
                maximumDistance: maximumDistance
            )
        }
    }

    private static func shapeSamples(
        of prepared: PreparedPath,
        sampleCount: Int
    ) -> [CGPoint]? {
        prepared.sampleCount == sampleCount
            ? prepared.shapeSamples
            : UnistrokeGeometry.resampledPath(prepared.points, count: sampleCount)
    }

    private static func orderedSimilarity(
        _ stroke: [CGPoint],
        _ template: [CGPoint],
        sampleCount: Int,
        distanceScale: Double = scoreDistanceScale
    ) -> SimilarityEvaluation {
        orderedSimilarity(
            sampledStroke: UnistrokeGeometry.resampledPath(stroke, count: sampleCount),
            sampledTemplate: UnistrokeGeometry.resampledPath(template, count: sampleCount),
            sampleCount: sampleCount,
            distanceScale: distanceScale
        )
    }

    private static func curveSimilarity(
        sampledStroke: [CGPoint]?,
        sampledTemplate: [CGPoint]?,
        sampleCount: Int,
        usesAlignment: Bool = true
    ) -> SimilarityEvaluation {
        guard sampleCount > 8, let sampledStroke, let sampledTemplate,
              let normalizedTemplate = UnistrokeGeometry.normalize(
                  sampledTemplate,
                  uniform: true
              ) else {
            return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0)
        }

        let center = UnistrokeGeometry.centroid(sampledStroke)
        var bestPreliminaryDistance = Double.infinity
        var bestCandidate: [CGPoint]?
        var bestRotation = 0
        for degrees in -rotationToleranceDegrees...rotationToleranceDegrees {
            guard let candidate = UnistrokeGeometry.rotatedNormalized(
                sampledStroke,
                around: center,
                radians: CGFloat(degrees) * .pi / 180,
                uniform: true
            ) else { continue }
            let position = orderedPointDistance(
                candidate,
                normalizedTemplate,
                abandonAverageAbove: bestPreliminaryDistance
            )
            guard position.isFinite else { continue }
            let tangent = CurvePathSignature.tangentDistance(candidate, normalizedTemplate)
            let distance = position + tangent * 0.08
            if distance < bestPreliminaryDistance {
                bestPreliminaryDistance = distance
                bestCandidate = candidate
                bestRotation = degrees
            }
        }
        guard let bestCandidate else {
            return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0)
        }
        let bestDistance = usesAlignment
            ? CurvePathSignature.alignedDistance(bestCandidate, normalizedTemplate)
            : bestPreliminaryDistance
        let distanceScale = usesAlignment ? curveScoreDistanceScale : scoreDistanceScale
        let endpointMismatch = usesAlignment
            ? CurvePathSignature.endpointMismatch(bestCandidate, normalizedTemplate)
            : nil
        return SimilarityEvaluation(
            score: min(1, max(0, exp(-bestDistance / distanceScale))),
            distance: bestDistance,
            rotationDegrees: bestRotation,
            structuralMismatch: endpointMismatch
        )
    }

    private static func curvePrefixMeetsThreshold(
        sampledStroke: [CGPoint],
        sampledTemplate: [CGPoint],
        maximumDistance: Double
    ) -> Bool {
        guard let normalizedTemplate = UnistrokeGeometry.normalize(
            sampledTemplate,
            uniform: true
        ) else { return false }
        let center = UnistrokeGeometry.centroid(sampledStroke)
        for degrees in -rotationToleranceDegrees...rotationToleranceDegrees {
            guard let candidate = UnistrokeGeometry.rotatedNormalized(
                sampledStroke,
                around: center,
                radians: CGFloat(degrees) * .pi / 180,
                uniform: true
            ) else { continue }
            let position = orderedPointDistance(
                candidate,
                normalizedTemplate,
                abandonAverageAbove: maximumDistance
            )
            guard position.isFinite else { continue }
            let tangent = CurvePathSignature.tangentDistance(candidate, normalizedTemplate)
            if position + tangent * 0.08 <= maximumDistance { return true }
        }
        return false
    }

    private static func orderedSimilarity(
        sampledStroke: [CGPoint]?,
        sampledTemplate: [CGPoint]?,
        sampleCount: Int,
        distanceScale: Double = scoreDistanceScale
    ) -> SimilarityEvaluation {
        guard sampleCount > 1, let sampledStroke, let sampledTemplate
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

        let rotationCenter = UnistrokeGeometry.centroid(sampledStroke)
        var bestDistance = Double.infinity
        var bestRotation = 0
        for degrees in -rotationToleranceDegrees...rotationToleranceDegrees {
            guard let candidate = UnistrokeGeometry.rotatedNormalized(
                sampledStroke,
                around: rotationCenter,
                radians: CGFloat(degrees) * .pi / 180,
                uniform: uniformScale
            ) else {
                continue
            }
            let distance = orderedPointDistance(
                candidate,
                normalizedTemplate,
                abandonAverageAbove: bestDistance
            )
            if distance < bestDistance {
                bestDistance = distance
                bestRotation = degrees
            }
        }

        guard bestDistance.isFinite else {
            return SimilarityEvaluation(score: 0, distance: .infinity, rotationDegrees: 0)
        }
        let score = min(1, max(0, exp(-bestDistance / distanceScale)))
        return SimilarityEvaluation(
            score: score,
            distance: bestDistance,
            rotationDegrees: bestRotation
        )
    }

    private static func canonicalPaths(
        strokeSegments: [StrokeStructureDescriptor],
        templateSegments: [StrokeStructureDescriptor],
        flexibleSingleTurn: Bool
    ) -> (stroke: [CGPoint], template: [CGPoint])? {
        if flexibleSingleTurn,
           StrokeStructureMatcher.monotonicTurn(in: strokeSegments) != nil,
           let stroke = singleTurnCanonicalPath(strokeSegments),
           let template = singleTurnCanonicalPath(templateSegments) {
            return (stroke, template)
        }

        guard (2...4).contains(templateSegments.count),
              strokeSegments.count == templateSegments.count,
              let stroke = canonicalPath(strokeSegments, lengthsFrom: templateSegments),
              let template = canonicalPath(templateSegments, lengthsFrom: templateSegments)
        else { return nil }
        return (stroke, template)
    }

    private static func singleTurnCanonicalPath(
        _ segments: [StrokeStructureDescriptor]
    ) -> [CGPoint]? {
        guard let first = segments.first, let last = segments.last else { return nil }
        let corner = first.unitDirection
        return [
            .zero,
            corner,
            CGPoint(
                x: corner.x + last.unitDirection.x,
                y: corner.y + last.unitDirection.y
            ),
        ]
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
        rawGeometryScore: Double,
        forceOrderedPath: Bool = false
    ) -> Diagnostics {
        let mode: MatchingMode? = finalSimilarity.map { _ in
            if forceOrderedPath { return .curveOrderedPath }
            if structure.usesFlexibleSingleTurn {
                return .singleTurnCanonical
            }
            return (2...4).contains(structure.templateSegments.count)
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

    /// Average pairwise distance. Once the running total proves the average
    /// cannot beat `abandonAverageAbove`, the remaining pairs are skipped.
    private static func orderedPointDistance(
        _ a: [CGPoint],
        _ b: [CGPoint],
        abandonAverageAbove limit: Double = .infinity
    ) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        let abandonTotal = limit.isFinite ? limit * Double(a.count) : .infinity
        var total = 0.0
        for index in a.indices {
            total += hypot(Double(a[index].x - b[index].x), Double(a[index].y - b[index].y))
            if total > abandonTotal { return .infinity }
        }
        return total / Double(a.count)
    }
}
