import CoreGraphics
import Foundation

/// Shared pure geometry operations for unistroke recording and matching.
enum UnistrokeGeometry {
    static func resampledPath(_ points: [CGPoint], count: Int) -> [CGPoint]? {
        guard count > 1, points.count >= 2,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return nil }

        let cleaned = removingConsecutiveDuplicates(points)
        let length = PathSimplifier.pathLength(cleaned)
        guard cleaned.count >= 2, length.isFinite, length > 1e-8 else { return nil }
        return PathSimplifier.resample(cleaned, count: count)
    }

    /// Recorder-facing representation: finite, de-duplicated, arc-length sampled,
    /// and uniformly normalized without discarding curved-path detail.
    static func recordedPath(_ points: [CGPoint]) -> [CGPoint]? {
        guard let sampled = resampledPath(
            points,
            count: Constants.freePathRecordingSampleCount
        ) else { return nil }
        return normalize(sampled, uniform: true)
    }

    static func normalize(_ points: [CGPoint], uniform: Bool) -> [CGPoint]? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        let major = max(width, height)
        guard major.isFinite, major > 1e-8 else { return nil }

        let scaleX = uniform ? major : max(width, 1e-8)
        let scaleY = uniform ? major : max(height, 1e-8)
        let scaled = points.map { CGPoint(x: $0.x / scaleX, y: $0.y / scaleY) }
        let center = centroid(scaled)
        return scaled.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y) }
    }

    static func trimmingTerminalFraction(_ points: [CGPoint], _ fraction: CGFloat) -> [CGPoint] {
        guard fraction > 1e-8, fraction < 1, points.count >= 2 else { return points }
        let target = PathSimplifier.pathLength(points) * (1 - fraction)
        guard target > 1e-8 else { return points }

        var result = [points[0]]
        var travelled: CGFloat = 0
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let length = hypot(end.x - start.x, end.y - start.y)
            if travelled + length < target {
                result.append(end)
                travelled += length
                continue
            }
            let progress = length > 1e-8 ? (target - travelled) / length : 0
            result.append(CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            ))
            break
        }
        return result
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func removingConsecutiveDuplicates(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points where result.last.map({
            hypot(point.x - $0.x, point.y - $0.y) > 1e-8
        }) ?? true {
            result.append(point)
        }
        return result
    }
}
