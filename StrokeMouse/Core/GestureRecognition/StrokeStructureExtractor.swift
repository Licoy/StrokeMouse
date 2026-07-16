import CoreGraphics
import Foundation

struct StrokeStructureSegment {
    let vector: CGPoint
    let arcLength: CGFloat

    var chordLength: CGFloat { hypot(vector.x, vector.y) }
    var angle: Double { atan2(Double(vector.y), Double(vector.x)) }

    func combined(with other: StrokeStructureSegment) -> StrokeStructureSegment {
        StrokeStructureSegment(
            vector: CGPoint(x: vector.x + other.vector.x, y: vector.y + other.vector.y),
            arcLength: arcLength + other.arcLength
        )
    }
}

struct StrokeStructureSignature {
    let segments: [StrokeStructureSegment]
    let descriptors: [StrokeStructureDescriptor]
    let startTangent: Double
    let endTangent: Double
    let trimmedTerminalFraction: CGFloat
}

struct StrokeStructureExtraction {
    let signature: StrokeStructureSignature?
    let exceededTerminalBudget: Bool
}

/// Produces the ordered structural signature shared by gating and canonical scoring.
enum StrokeStructureExtractor {
    private struct TerminalAssessment {
        let trimmedFraction: CGFloat
        let exceededBudget: Bool
    }

    static func extract(_ points: [CGPoint]) -> StrokeStructureExtraction {
        guard let sampled = UnistrokeGeometry.resampledPath(
            points,
            count: Constants.freePathStructureSampleCount
        ), let normalized = UnistrokeGeometry.normalize(sampled, uniform: true) else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: false)
        }

        let terminal = terminalAssessment(normalized)
        guard !terminal.exceededBudget else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: true)
        }
        let analysisPath = UnistrokeGeometry.trimmingTerminalFraction(
            normalized,
            terminal.trimmedFraction
        )
        let smoothed = smooth(analysisPath, radius: 2)
        let simplified = PathSimplifier.simplify(
            smoothed,
            epsilon: Constants.freePathStructureSimplifyEpsilon
        )
        guard var segments = sourceSegments(simplified: simplified, source: smoothed),
              !segments.isEmpty else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: false)
        }

        segments = StrokeSegmentReducer.mergeContinuous(segments)
        let merged = StrokeSegmentReducer.mergeShort(
            segments,
            existingTerminalFraction: terminal.trimmedFraction
        )
        guard !merged.exceededTerminalBudget else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: true)
        }
        guard !merged.segments.isEmpty else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: false)
        }

        return extraction(from: merged, terminal: terminal, smoothedPath: smoothed)
    }

    private static func extraction(
        from merged: StrokeSegmentReducer.ShortMergeResult,
        terminal: TerminalAssessment,
        smoothedPath: [CGPoint]
    ) -> StrokeStructureExtraction {
        let core = UnistrokeGeometry.trimmingTerminalFraction(
            smoothedPath,
            merged.additionalTrimmedFraction
        )
        guard let tangents = endpointTangents(core),
              let descriptors = descriptors(for: merged.segments) else {
            return StrokeStructureExtraction(signature: nil, exceededTerminalBudget: false)
        }
        let totalTrimmedFraction = terminal.trimmedFraction
            + (1 - terminal.trimmedFraction) * merged.additionalTrimmedFraction
        return StrokeStructureExtraction(
            signature: StrokeStructureSignature(
                segments: merged.segments,
                descriptors: descriptors,
                startTangent: tangents.start,
                endTangent: tangents.end,
                trimmedTerminalFraction: totalTrimmedFraction
            ),
            exceededTerminalBudget: false
        )
    }

    private static func descriptors(
        for segments: [StrokeStructureSegment]
    ) -> [StrokeStructureDescriptor]? {
        let total = segments.reduce(CGFloat.zero) { $0 + $1.arcLength }
        guard total > 1e-8 else { return nil }
        return segments.map { segment in
            let length = segment.chordLength
            return StrokeStructureDescriptor(
                unitDirection: CGPoint(
                    x: segment.vector.x / length,
                    y: segment.vector.y / length
                ),
                lengthFraction: segment.arcLength / total
            )
        }
    }

    private static func terminalAssessment(_ points: [CGPoint]) -> TerminalAssessment {
        let simplified = PathSimplifier.simplify(
            points,
            epsilon: Constants.freePathTerminalProbeEpsilon
        )
        guard let source = sourceSegments(simplified: simplified, source: points) else {
            return TerminalAssessment(trimmedFraction: 0, exceededBudget: false)
        }
        let segments = StrokeSegmentReducer.mergeContinuous(source)
        let total = segments.reduce(CGFloat.zero) { $0 + $1.arcLength }
        guard total > 1e-8 else {
            return TerminalAssessment(trimmedFraction: 0, exceededBudget: false)
        }

        var terminalFraction: CGFloat = 0
        for segment in segments.reversed() {
            let fraction = segment.arcLength / total
            guard fraction <= Constants.freePathShortSegmentFraction else { break }
            terminalFraction += fraction
            if terminalFraction > Constants.freePathShortSegmentFraction {
                return TerminalAssessment(trimmedFraction: 0, exceededBudget: true)
            }
        }
        return TerminalAssessment(trimmedFraction: terminalFraction, exceededBudget: false)
    }

    private static func sourceSegments(
        simplified: [CGPoint],
        source: [CGPoint]
    ) -> [StrokeStructureSegment]? {
        guard simplified.count >= 2, source.count >= simplified.count else { return nil }
        var sourceIndex = 0
        var segments: [StrokeStructureSegment] = []
        for endpoint in simplified.dropFirst() {
            guard let endpointIndex = source[sourceIndex...].firstIndex(of: endpoint),
                  endpointIndex > sourceIndex else { return nil }
            let vector = CGPoint(
                x: source[endpointIndex].x - source[sourceIndex].x,
                y: source[endpointIndex].y - source[sourceIndex].y
            )
            let arcLength = pathLength(source, from: sourceIndex, through: endpointIndex)
            if hypot(vector.x, vector.y) > 1e-8, arcLength > 1e-8 {
                segments.append(StrokeStructureSegment(vector: vector, arcLength: arcLength))
            }
            sourceIndex = endpointIndex
        }
        return segments
    }

    private static func pathLength(
        _ points: [CGPoint],
        from start: Int,
        through end: Int
    ) -> CGFloat {
        guard end > start else { return 0 }
        return ((start + 1)...end).reduce(CGFloat.zero) { length, index in
            length + hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            )
        }
    }

    /// Continuous tangents over the first and final eighth of arc length.
    private static func endpointTangents(_ points: [CGPoint]) -> (start: Double, end: Double)? {
        let count = Constants.freePathStructureSampleCount
        let sampled = PathSimplifier.resample(points, count: count)
        let offset = count / 8
        guard offset > 0, sampled.count > offset else { return nil }
        let startVector = CGPoint(
            x: sampled[offset].x - sampled[0].x,
            y: sampled[offset].y - sampled[0].y
        )
        let last = sampled.count - 1
        let endVector = CGPoint(
            x: sampled[last].x - sampled[last - offset].x,
            y: sampled[last].y - sampled[last - offset].y
        )
        guard hypot(startVector.x, startVector.y) > 1e-8,
              hypot(endVector.x, endVector.y) > 1e-8 else { return nil }
        return (
            atan2(Double(startVector.y), Double(startVector.x)),
            atan2(Double(endVector.y), Double(endVector.x))
        )
    }

    private static func smooth(_ points: [CGPoint], radius: Int) -> [CGPoint] {
        guard radius > 0, points.count > radius * 2 else { return points }
        return points.indices.map { index in
            guard index != points.startIndex,
                  index != points.index(before: points.endIndex) else { return points[index] }
            let lower = max(points.startIndex, index - radius)
            let upper = min(points.index(before: points.endIndex), index + radius)
            let count = CGFloat(upper - lower + 1)
            let sum = points[lower...upper].reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            return CGPoint(x: sum.x / count, y: sum.y / count)
        }
    }
}
