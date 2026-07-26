import CoreGraphics
import Foundation

/// Shared pure geometry operations for unistroke shape and structure matching.
enum UnistrokeGeometry {
    private static let smoothingFraction: CGFloat = 0.04

    static func resampledPath(_ points: [CGPoint], count: Int) -> [CGPoint]? {
        guard points.count >= 2,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return nil }

        var cleaned: [CGPoint] = []
        cleaned.reserveCapacity(points.count)
        for point in points {
            if let last = cleaned.last, hypot(point.x - last.x, point.y - last.y) <= 1e-8 {
                continue
            }
            cleaned.append(point)
        }
        guard cleaned.count >= 2, PathSimplifier.pathLength(cleaned) > 1e-8 else { return nil }
        let smoothed = PathSimplifier.simplify(
            cleaned,
            epsilon: majorExtent(cleaned) * smoothingFraction
        )
        return PathSimplifier.resample(smoothed, count: count)
    }

    static func normalize(_ points: [CGPoint], uniform: Bool) -> [CGPoint]? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        let major = max(width, height)
        guard major > 1e-8 else { return nil }

        let scaleX = uniform ? major : max(width, 1e-8)
        let scaleY = uniform ? major : max(height, 1e-8)
        let scaled = points.map { CGPoint(x: $0.x / scaleX, y: $0.y / scaleY) }
        let center = centroid(scaled)
        return scaled.map { CGPoint(x: $0.x - center.x, y: $0.y - center.y) }
    }

    static func isNearOneDimensional(_ points: [CGPoint], threshold: CGFloat) -> Bool {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return true }
        let width = maxX - minX
        let height = maxY - minY
        let major = max(width, height)
        return major <= 1e-8 || min(width, height) / major <= threshold
    }

    static func rotate(_ points: [CGPoint], radians: CGFloat) -> [CGPoint] {
        let center = centroid(points)
        let cosine = cos(radians)
        let sine = sin(radians)
        return points.map { point in
            let x = point.x - center.x
            let y = point.y - center.y
            return CGPoint(
                x: x * cosine - y * sine + center.x,
                y: x * sine + y * cosine + center.y
            )
        }
    }

    /// `rotate` followed by `normalize` fused into a single buffer, with the
    /// rotation center hoisted so repeated calls over the same points (the
    /// ±rotation-tolerance search) skip per-call centroid and bbox passes.
    static func rotatedNormalized(
        _ points: [CGPoint],
        around center: CGPoint,
        radians: CGFloat,
        uniform: Bool
    ) -> [CGPoint]? {
        guard !points.isEmpty else { return nil }
        let cosine = cos(radians)
        let sine = sin(radians)

        var rotated = [CGPoint]()
        rotated.reserveCapacity(points.count)
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for point in points {
            let x = point.x - center.x
            let y = point.y - center.y
            let rotatedPoint = CGPoint(
                x: x * cosine - y * sine + center.x,
                y: x * sine + y * cosine + center.y
            )
            rotated.append(rotatedPoint)
            minX = min(minX, rotatedPoint.x)
            maxX = max(maxX, rotatedPoint.x)
            minY = min(minY, rotatedPoint.y)
            maxY = max(maxY, rotatedPoint.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        let major = max(width, height)
        guard major > 1e-8 else { return nil }
        let scaleX = uniform ? major : max(width, 1e-8)
        let scaleY = uniform ? major : max(height, 1e-8)

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for index in rotated.indices {
            let scaled = CGPoint(x: rotated[index].x / scaleX, y: rotated[index].y / scaleY)
            rotated[index] = scaled
            sumX += scaled.x
            sumY += scaled.y
        }
        let count = CGFloat(rotated.count)
        let centerX = sumX / count
        let centerY = sumY / count
        for index in rotated.indices {
            rotated[index].x -= centerX
            rotated[index].y -= centerY
        }
        return rotated
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

    private static func majorExtent(_ points: [CGPoint]) -> CGFloat {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return 0 }
        return max(maxX - minX, maxY - minY)
    }
}
