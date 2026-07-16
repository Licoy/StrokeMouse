import CoreGraphics
import Foundation

enum GesturePreviewGeometry {
    /// Aspect-fit a stored Y-up path into a centered Y-down preview canvas.
    static func aspectFit(points: [CGPoint], in size: CGSize, padding: CGFloat) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return [] }

        let width = maxX - minX
        let height = maxY - minY
        let availableWidth = max(size.width - padding * 2, 0)
        let availableHeight = max(size.height - padding * 2, 0)
        let scale = fitScale(
            for: CGSize(width: width, height: height),
            in: CGSize(width: availableWidth, height: availableHeight)
        )
        let originX = padding + (availableWidth - width * scale) / 2
        let originY = padding + (availableHeight - height * scale) / 2

        return points.map { point in
            CGPoint(
                x: originX + (point.x - minX) * scale,
                y: originY + (maxY - point.y) * scale
            )
        }
    }

    private static func fitScale(for extent: CGSize, in availableSize: CGSize) -> CGFloat {
        var candidates: [CGFloat] = []
        if extent.width > 1e-6 { candidates.append(availableSize.width / extent.width) }
        if extent.height > 1e-6 { candidates.append(availableSize.height / extent.height) }
        return candidates.min() ?? 0
    }
}
