import CoreGraphics

enum GestureTargetScreenGeometry {
    static func appKitWindowFrame(
        axOrigin: CGPoint,
        windowSize: CGSize,
        zeroScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: axOrigin.x,
            y: zeroScreenFrame.maxY - axOrigin.y - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    static func targetScreenIndex(
        for windowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        let overlapping = screenFrames.enumerated().map { index, frame in
            let intersection = windowFrame.intersection(frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (index, area)
        }
        if let best = overlapping.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return best.0
        }
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screenFrames.indices.min { lhs, rhs in
            squaredDistance(center, to: screenFrames[lhs])
                < squaredDistance(center, to: screenFrames[rhs])
        }
    }

    static func centeredAXOrigin(
        windowSize: CGSize,
        visibleFrame: CGRect,
        zeroScreenFrame: CGRect
    ) -> CGPoint {
        let appKitOrigin = CGPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
        return CGPoint(
            x: appKitOrigin.x,
            y: zeroScreenFrame.maxY - appKitOrigin.y - windowSize.height
        )
    }

    private static func squaredDistance(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
