import CoreGraphics
import Foundation

/// Sampling-stable features for curved unistrokes. This intentionally does not
/// use RDP segment counts: curves are described by tangent flow and turn order.
struct CurvePathSignature: Sendable {
    private static let minimumRunTurn = 12.0 * Double.pi / 180
    private static let minimumSupportedTurn = 0.5 * Double.pi / 180
    private static let cornerTurn = 42.0 * Double.pi / 180
    private static let alignmentBand = 4
    private static let tangentWeight = 0.08
    private static let alignmentStateCount = 5

    let normalizedPoints: [CGPoint]
    let positiveTurn: Double
    let negativeTurn: Double
    let turnRuns: [Double]
    let closureRatio: CGFloat
    let stableCornerCount: Int
    let maximumTurnConcentration: Double
    let smoothTurnFraction: Double
    let turnSupportFraction: Double
    let terminalStraightTurnCount: Int

    var isCurve: Bool {
        let total = positiveTurn + negativeTurn
        let hasReversal = min(positiveTurn, negativeTurn) >= 0.35
        let distributed = maximumTurnConcentration <= 0.55
            && turnSupportFraction >= 0.30
            && stableCornerCount <= 1
        return (closureRatio <= 0.14 && maximumTurnConcentration <= 0.55)
            || (distributed && (
                total >= 170 * .pi / 180
                || (hasReversal && total >= 80 * .pi / 180)
            ))
    }

    static func make(_ points: [CGPoint]) -> CurvePathSignature? {
        guard let sampled = UnistrokeGeometry.resampledPath(
            points,
            count: Constants.freePathSampleCount
        ), let normalized = UnistrokeGeometry.normalize(sampled, uniform: true) else {
            return nil
        }
        let headings = tangentHeadings(normalized, offset: 2)
        guard headings.count >= 2 else { return nil }
        let rawTurns = zip(headings, headings.dropFirst()).map {
            StrokeSegmentReducer.signedAngle($1 - $0)
        }
        let turns = stabilizingCuspSigns(in: rawTurns)
        let positive = turns.reduce(0.0) { $0 + max(0, $1) }
        let negative = turns.reduce(0.0) { $0 + max(0, -$1) }
        let length = PathSimplifier.pathLength(normalized)
        guard length.isFinite, length > 1e-8 else { return nil }
        let endpointDistance = hypot(
            normalized.last!.x - normalized[0].x,
            normalized.last!.y - normalized[0].y
        )
        return CurvePathSignature(
            normalizedPoints: normalized,
            positiveTurn: positive,
            negativeTurn: negative,
            turnRuns: significantRuns(turns),
            closureRatio: endpointDistance / length,
            stableCornerCount: stableCorners(turns),
            maximumTurnConcentration: turnConcentration(turns),
            smoothTurnFraction: smoothTurnFraction(turns),
            turnSupportFraction: turnSupportFraction(turns),
            terminalStraightTurnCount: terminalStraightCount(in: normalized)
        )
    }

    func mismatch(with template: CurvePathSignature) -> StrokeStructureMatcher.Mismatch? {
        guard !hasExcessTerminalStraight(relativeTo: template) else {
            return .terminalOverrun
        }
        let strokeClosed = closureRatio <= 0.14
        let templateClosed = template.closureRatio <= 0.14
        guard strokeClosed == templateClosed else { return .endpointDirection }
        guard abs(closureRatio - template.closureRatio) <= 0.08 else {
            return .endpointDirection
        }

        let strokeSigns = turnRuns.map { $0 > 0 }
        let templateSigns = template.turnRuns.map { $0 > 0 }
        guard strokeSigns == templateSigns else { return .turnDirection }

        let turnTolerance = 85.0 * .pi / 180
        guard abs(positiveTurn - template.positiveTurn) <= turnTolerance,
              abs(negativeTurn - template.negativeTurn) <= turnTolerance else {
            return .turnAngle
        }
        return nil
    }

    func hasExcessTerminalStraight(relativeTo template: CurvePathSignature) -> Bool {
        terminalStraightTurnCount > template.terminalStraightTurnCount + Self.alignmentBand
    }

    static func endpointMismatch(
        _ stroke: [CGPoint],
        _ template: [CGPoint]
    ) -> StrokeStructureMatcher.Mismatch? {
        guard stroke.count == template.count, stroke.count > 8 else { return .invalidStroke }
        let strokeHeadings = pointHeadings(stroke, offset: 8)
        let templateHeadings = pointHeadings(template, offset: 8)
        guard StrokeSegmentReducer.angleDifference(
            strokeHeadings[0],
            templateHeadings[0]
        ) <= StrokeSegmentReducer.degreesToRadians(Constants.freePathStartAngleDegrees) else {
            return .startDirection
        }
        guard StrokeSegmentReducer.angleDifference(
            strokeHeadings[strokeHeadings.count - 1],
            templateHeadings[templateHeadings.count - 1]
        ) <= StrokeSegmentReducer.degreesToRadians(Constants.freePathEndAngleDegrees) else {
            return .endpointDirection
        }
        return nil
    }

    static func tangentDistance(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> Double {
        guard lhs.count == rhs.count, lhs.count >= 9 else { return .infinity }
        var total = 0.0
        var count = 0
        for offset in [2, 4, 8] {
            let left = tangentHeadings(lhs, offset: offset)
            let right = tangentHeadings(rhs, offset: offset)
            for (a, b) in zip(left, right) {
                total += abs(StrokeSegmentReducer.signedAngle(a - b)) / .pi
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : .infinity
    }

    /// Endpoint-anchored, direction-preserving alignment for local arc-length
    /// proportion differences. Symmetric step weights keep warp steps from
    /// lowering the average merely by making the path longer.
    static func alignedDistance(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> Double {
        guard lhs.count == rhs.count, lhs.count >= 9 else { return .infinity }
        let count = lhs.count
        let leftHeadings = [2, 4, 8].map { pointHeadings(lhs, offset: $0) }
        let rightHeadings = [2, 4, 8].map { pointHeadings(rhs, offset: $0) }
        var costs = Array(
            repeating: Double.infinity,
            count: count * count * alignmentStateCount
        )

        for row in 0..<count {
            for column in max(0, row - alignmentBand)...min(count - 1, row + alignmentBand) {
                let local = alignmentCost(
                    lhs[row],
                    rhs[column],
                    leftHeadings: leftHeadings,
                    rightHeadings: rightHeadings,
                    leftIndex: row,
                    rightIndex: column
                )
                let base = (row * count + column) * alignmentStateCount
                if row == 0, column == 0 {
                    costs[base] = local * 2
                    continue
                }
                if row > 0, column > 0 {
                    let previous = ((row - 1) * count + column - 1) * alignmentStateCount
                    costs[base] = costs[previous..<(previous + alignmentStateCount)].min()!
                        + local * 2
                }
                if column > 0 {
                    let previous = (row * count + column - 1) * alignmentStateCount
                    costs[base + 1] = min(costs[previous], costs[previous + 3], costs[previous + 4])
                        + local
                    costs[base + 2] = costs[previous + 1] + local
                }
                if row > 0 {
                    let previous = ((row - 1) * count + column) * alignmentStateCount
                    costs[base + 3] = min(costs[previous], costs[previous + 1], costs[previous + 2])
                        + local
                    costs[base + 4] = costs[previous + 3] + local
                }
            }
        }

        let end = (count * count - 1) * alignmentStateCount
        return costs[end..<(end + alignmentStateCount)].min()! / Double(count * 2)
    }

    private static func alignmentCost(
        _ lhs: CGPoint,
        _ rhs: CGPoint,
        leftHeadings: [[Double]],
        rightHeadings: [[Double]],
        leftIndex: Int,
        rightIndex: Int
    ) -> Double {
        let position = hypot(Double(lhs.x - rhs.x), Double(lhs.y - rhs.y))
        let tangent = leftHeadings.indices.reduce(0.0) { total, scale in
            total + abs(StrokeSegmentReducer.signedAngle(
                leftHeadings[scale][leftIndex] - rightHeadings[scale][rightIndex]
            )) / .pi
        } / Double(leftHeadings.count)
        return position + tangent * tangentWeight
    }

    private static func tangentHeadings(_ points: [CGPoint], offset: Int) -> [Double] {
        guard points.count > offset * 2 else { return [] }
        return (offset..<(points.count - offset)).map { index in
            atan2(
                Double(points[index + offset].y - points[index - offset].y),
                Double(points[index + offset].x - points[index - offset].x)
            )
        }
    }

    private static func pointHeadings(_ points: [CGPoint], offset: Int) -> [Double] {
        points.indices.map { index in
            let start = max(0, index - offset)
            let end = min(points.count - 1, index + offset)
            return atan2(
                Double(points[end].y - points[start].y),
                Double(points[end].x - points[start].x)
            )
        }
    }

    private static func significantRuns(_ turns: [Double]) -> [Double] {
        var runs: [Double] = []
        for turn in turns where abs(turn) > 1e-4 {
            if let last = runs.last, last * turn > 0 {
                runs[runs.count - 1] += turn
            } else {
                runs.append(turn)
            }
        }
        var filtered = coalescingRuns(runs.filter { abs($0) >= minimumRunTurn })
        while filtered.count >= 3 {
            guard let index = filtered.indices.dropFirst().dropLast().min(by: {
                abs(filtered[$0]) < abs(filtered[$1])
            }), abs(filtered[index]) < minimumRunTurn * 2 else { break }
            filtered[index - 1] += filtered[index] + filtered[index + 1]
            filtered.removeSubrange(index...(index + 1))
            filtered = coalescingRuns(filtered.filter { abs($0) >= minimumRunTurn })
        }
        return filtered
    }

    /// A sampled cusp can land on either side of ±π. Stabilize one such cusp
    /// only when the remaining path has a strong, sustained turn direction.
    private static func stabilizingCuspSigns(in turns: [Double]) -> [Double] {
        // Arc-length resampling can move a branch-cut cusp by roughly one
        // tangent window; 135° keeps that cusp class stable across re-sampling.
        let cuspThreshold = 135.0 * .pi / 180
        var concentratedRuns: [Range<Int>] = []
        var start = 0
        while start < turns.count {
            let sign = turns[start].sign
            var end = start + 1
            while end < turns.count, turns[end].sign == sign { end += 1 }
            let range = start..<end
            let total = turns[range].reduce(0, +)
            if range.count <= alignmentBand, abs(total) >= cuspThreshold {
                concentratedRuns.append(range)
            }
            start = end
        }
        guard concentratedRuns.count == 1, let cusp = concentratedRuns.first else {
            return turns
        }

        let directional = turns.indices.filter { !cusp.contains($0) }.map { turns[$0] }
        let signedTurn = directional.reduce(0, +)
        let absoluteTurn = directional.map(abs).reduce(0, +)
        guard absoluteTurn >= .pi,
              abs(signedTurn) / absoluteTurn >= 0.8 else { return turns }

        var stabilized = turns
        for index in cusp {
            stabilized[index] = copysign(abs(turns[index]), signedTurn)
        }
        return stabilized
    }

    private static func coalescingRuns(_ runs: [Double]) -> [Double] {
        runs.reduce(into: []) { result, run in
            if let last = result.last, last * run > 0 {
                result[result.count - 1] += run
            } else {
                result.append(run)
            }
        }
    }

    private static func stableCorners(_ turns: [Double]) -> Int {
        guard turns.count >= 5 else { return 0 }
        var count = 0
        var lastCorner = -6
        for index in 2..<(turns.count - 2) {
            let window = turns[(index - 2)...(index + 2)].map(abs)
            let total = window.reduce(0, +)
            let peak = window.max() ?? 0
            guard total >= cornerTurn,
                  peak >= total * 0.55,
                  index - lastCorner >= 6 else { continue }
            count += 1
            lastCorner = index
        }
        return count
    }

    private static func turnConcentration(_ turns: [Double]) -> Double {
        let magnitudes = turns.map(abs)
        let total = magnitudes.reduce(0, +)
        guard total > 1e-8 else { return 1 }
        let window = 7
        let maximum = magnitudes.indices.map { start in
            magnitudes[start..<min(start + window, magnitudes.count)].reduce(0, +)
        }.max() ?? total
        return maximum / total
    }

    private static func smoothTurnFraction(_ turns: [Double]) -> Double {
        let magnitudes = turns.map(abs)
        let total = magnitudes.reduce(0, +)
        guard total > 1e-8 else { return 0 }
        let smoothLimit = 15.0 * .pi / 180
        return magnitudes.filter { $0 <= smoothLimit }.reduce(0, +) / total
    }

    private static func turnSupportFraction(_ turns: [Double]) -> Double {
        guard !turns.isEmpty else { return 0 }
        return Double(turns.filter { abs($0) >= minimumSupportedTurn }.count)
            / Double(turns.count)
    }

    private static func terminalStraightCount(in points: [CGPoint]) -> Int {
        let scales = [2, 4, 8].map { pointHeadings(points, offset: $0) }
        guard let first = scales.first, first.count >= 2 else { return 0 }
        let supportedTurn = minimumRunTurn / Double(alignmentBand)
        let turns = first.indices.dropLast().map { index in
            scales.reduce(0.0) { total, headings in
                total + abs(StrokeSegmentReducer.signedAngle(
                    headings[index + 1] - headings[index]
                ))
            } / Double(scales.count)
        }
        guard let lastTurn = turns.lastIndex(where: { $0 >= supportedTurn }) else {
            return turns.count
        }
        return turns.count - lastTurn - 1
    }
}
