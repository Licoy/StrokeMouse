import CoreGraphics
import Foundation

/// Reduces noisy RDP segments without changing their original arc-length mass.
enum StrokeSegmentReducer {
    private static let minimumPrimaryTurnDegrees = 90.0
    private static let maximumCorrectionDegrees = 30.0
    private static let maximumCorrectionFraction = 0.20

    struct ShortMergeResult {
        let segments: [StrokeStructureSegment]
        let additionalTrimmedFraction: CGFloat
        let exceededTerminalBudget: Bool
    }

    static func mergeContinuous(_ input: [StrokeStructureSegment]) -> [StrokeStructureSegment] {
        var segments = input
        var didMerge = true
        while didMerge, segments.count > 1 {
            didMerge = false
            var result: [StrokeStructureSegment] = []
            var index = 0
            while index < segments.count {
                if index + 1 < segments.count,
                   angleDifference(segments[index].angle, segments[index + 1].angle)
                    <= degreesToRadians(Constants.freePathMergeAngleDegrees) {
                    result.append(segments[index].combined(with: segments[index + 1]))
                    index += 2
                    didMerge = true
                } else {
                    result.append(segments[index])
                    index += 1
                }
            }
            segments = result.filter { $0.chordLength > 1e-8 }
        }
        return segments
    }

    static func mergeShort(
        _ input: [StrokeStructureSegment],
        existingTerminalFraction: CGFloat
    ) -> ShortMergeResult {
        var segments = input
        let initialLength = segments.reduce(CGFloat.zero) { $0 + $1.arcLength }
        guard initialLength > 1e-8 else {
            return ShortMergeResult(
                segments: [],
                additionalTrimmedFraction: 0,
                exceededTerminalBudget: false
            )
        }

        var trimmedTerminalLength: CGFloat = 0
        while segments.count > 1 {
            let totalLength = segments.reduce(CGFloat.zero) { $0 + $1.arcLength }
            guard let index = shortestInsignificantSegment(in: segments, total: totalLength) else {
                break
            }

            if index == 0 {
                segments.replaceSubrange(0...1, with: [segments[0].combined(with: segments[1])])
            } else if index == segments.count - 1 {
                trimmedTerminalLength += segments[index].arcLength
                let additional = trimmedTerminalLength / initialLength
                let total = existingTerminalFraction + (1 - existingTerminalFraction) * additional
                guard total <= Constants.freePathShortSegmentFraction else {
                    return ShortMergeResult(
                        segments: segments,
                        additionalTrimmedFraction: 0,
                        exceededTerminalBudget: true
                    )
                }
                segments.removeLast()
            } else {
                mergeInternal(at: index, in: &segments)
            }
            segments.removeAll { $0.chordLength <= 1e-8 }
        }
        return ShortMergeResult(
            segments: mergeMinorOpposingCorrections(segments),
            additionalTrimmedFraction: trimmedTerminalLength / initialLength,
            exceededTerminalBudget: false
        )
    }

    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        abs(signedAngle(a - b))
    }

    static func signedAngle(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value < -.pi { value += 2 * .pi }
        return value
    }

    static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func shortestInsignificantSegment(
        in segments: [StrokeStructureSegment],
        total: CGFloat
    ) -> Int? {
        guard total > 1e-8 else { return nil }
        return segments.indices
            .filter {
                segments[$0].arcLength / total <= Constants.freePathShortSegmentFraction
            }
            .min { segments[$0].arcLength < segments[$1].arcLength }
    }

    private static func mergeInternal(
        at index: Int,
        in segments: inout [StrokeStructureSegment]
    ) {
        let left = angleDifference(segments[index].angle, segments[index - 1].angle)
        let right = angleDifference(segments[index].angle, segments[index + 1].angle)
        if left <= right {
            let merged = segments[index - 1].combined(with: segments[index])
            segments.replaceSubrange((index - 1)...index, with: [merged])
        } else {
            let merged = segments[index].combined(with: segments[index + 1])
            segments.replaceSubrange(index...(index + 1), with: [merged])
        }
    }

    /// A sharp turn often contains one small steering correction on its exit
    /// leg. Keep the primary turn, but fold that correction back into the same
    /// leg so a clean redraw is not required to reproduce recorder jitter.
    private static func mergeMinorOpposingCorrections(
        _ input: [StrokeStructureSegment]
    ) -> [StrokeStructureSegment] {
        guard input.count >= 3 else { return input }
        var segments = input
        var didMerge = true
        while didMerge, segments.count >= 3 {
            didMerge = false
            for index in 1..<(segments.count - 1) {
                let preceding = signedAngle(
                    segments[index].angle - segments[index - 1].angle
                )
                let following = signedAngle(
                    segments[index + 1].angle - segments[index].angle
                )
                if isMinorCorrection(following, relativeTo: preceding) {
                    let merged = segments[index].combined(with: segments[index + 1])
                    segments.replaceSubrange(index...(index + 1), with: [merged])
                    didMerge = true
                    break
                }
                if isMinorCorrection(preceding, relativeTo: following) {
                    let merged = segments[index - 1].combined(with: segments[index])
                    segments.replaceSubrange((index - 1)...index, with: [merged])
                    didMerge = true
                    break
                }
            }
        }
        return segments.filter { $0.chordLength > 1e-8 }
    }

    private static func isMinorCorrection(
        _ correction: Double,
        relativeTo primary: Double
    ) -> Bool {
        let primaryMagnitude = abs(primary)
        let correctionMagnitude = abs(correction)
        return primary * correction < 0
            && primaryMagnitude >= degreesToRadians(minimumPrimaryTurnDegrees)
            && correctionMagnitude <= degreesToRadians(maximumCorrectionDegrees)
            && correctionMagnitude <= primaryMagnitude * maximumCorrectionFraction
    }
}
