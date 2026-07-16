import CoreGraphics
import Foundation

enum PathSimplifier {
    /// Douglas–Peucker polyline simplification.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        return douglasPeucker(points, epsilon: epsilon)
    }

    /// Normalize into unit square [0,1]×[0,1] using independent X/Y scales.
    /// Prefer `normalize` for matching — independent scales discard aspect ratio.
    static func normalizeUnitSquare(_ points: [CGPoint]) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return points }

        let width = max(maxX - minX, 1e-6)
        let height = max(maxY - minY, 1e-6)

        return points.map { point in
            CGPoint(
                x: (point.x - minX) / width,
                y: (point.y - minY) / height
            )
        }
    }

    /// Normalize preserving aspect ratio (preferred for free-path matching).
    static func normalize(_ points: [CGPoint]) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return points }

        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = max(width, height)

        return points.map { point in
            CGPoint(
                x: (point.x - minX) / scale,
                y: (point.y - minY) / scale
            )
        }
    }

    /// Width / height of the axis-aligned bounding box (minimum 1e-6 per axis).
    static func boundingAspectRatio(_ points: [CGPoint]) -> CGFloat {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return 1 }
        let width = max(maxX - minX, 1e-6)
        let height = max(maxY - minY, 1e-6)
        return width / height
    }

    /// Max perpendicular distance from any point to the start→end chord, relative to chord length.
    /// ~0 for a pure line; higher for peaks / curves (capped conceptually around 0.5+ for sharp peaks).
    static func relativeChordDeviation(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        let start = points[0]
        let end = points[points.count - 1]
        let chord = hypot(end.x - start.x, end.y - start.y)
        guard chord > 1e-6 else {
            // Closed or tiny stroke: use path length scale.
            let len = max(pathLength(points), 1e-6)
            var maxDev: CGFloat = 0
            for p in points {
                maxDev = max(maxDev, hypot(p.x - start.x, p.y - start.y))
            }
            return maxDev / len
        }
        var maxDev: CGFloat = 0
        for p in points {
            maxDev = max(maxDev, perpendicularDistance(p, lineStart: start, lineEnd: end))
        }
        return maxDev / chord
    }

    /// 1 = perfectly straight along start→end; 0 = strongly bent (peak / loop).
    static func straightness(_ points: [CGPoint]) -> CGFloat {
        let dev = relativeChordDeviation(points)
        // Deviation of 0.35·chord → straightness 0.
        return max(0, 1 - min(1, dev / 0.35))
    }

    /// Resample polyline to a fixed number of points along arc length.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 1 else { return points }
        guard points.count >= 2 else {
            return Array(repeating: points.first ?? .zero, count: count)
        }

        var distances: [CGFloat] = [0]
        for i in 1..<points.count {
            distances.append(distances[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = distances.last ?? 0
        guard total > 0 else {
            return Array(repeating: points[0], count: count)
        }

        var result: [CGPoint] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let target = total * CGFloat(i) / CGFloat(count - 1)
            result.append(point(at: target, points: points, distances: distances))
        }
        return result
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }

    // MARK: - Private

    private static func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDistance: CGFloat = 0
        var index = 0
        let end = points.count - 1
        for i in 1..<end {
            let d = perpendicularDistance(points[i], lineStart: points[0], lineEnd: points[end])
            if d > maxDistance {
                maxDistance = d
                index = i
            }
        }

        if maxDistance > epsilon {
            let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[index...end]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [points[0], points[end]]
    }

    private static func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        if dx == 0 && dy == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let numerator = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        let denominator = hypot(dx, dy)
        return numerator / denominator
    }

    private static func point(at distance: CGFloat, points: [CGPoint], distances: [CGFloat]) -> CGPoint {
        if distance <= 0 { return points[0] }
        if distance >= (distances.last ?? 0) { return points[points.count - 1] }

        var lo = 0
        var hi = distances.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if distances[mid] < distance {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let i = max(lo, 1)
        let d0 = distances[i - 1]
        let d1 = distances[i]
        let t = d1 > d0 ? (distance - d0) / (d1 - d0) : 0
        let p0 = points[i - 1]
        let p1 = points[i]
        return CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
    }
}
