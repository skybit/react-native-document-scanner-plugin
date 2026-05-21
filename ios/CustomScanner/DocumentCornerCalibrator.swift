import CoreGraphics

struct DocumentCorners {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
}

enum DocumentCornerCalibrator {
    static let defaultPaddingRatio: CGFloat = 0.025

    static func calibrate(
        _ corners: DocumentCorners,
        paddingRatio: CGFloat = defaultPaddingRatio
    ) -> DocumentCorners {
        let center = CGPoint(
            x: (corners.topLeft.x + corners.topRight.x + corners.bottomRight.x + corners.bottomLeft.x) / 4,
            y: (corners.topLeft.y + corners.topRight.y + corners.bottomRight.y + corners.bottomLeft.y) / 4
        )

        return DocumentCorners(
            topLeft: expand(corners.topLeft, from: center, paddingRatio: paddingRatio),
            topRight: expand(corners.topRight, from: center, paddingRatio: paddingRatio),
            bottomRight: expand(corners.bottomRight, from: center, paddingRatio: paddingRatio),
            bottomLeft: expand(corners.bottomLeft, from: center, paddingRatio: paddingRatio)
        )
    }

    private static func expand(
        _ point: CGPoint,
        from center: CGPoint,
        paddingRatio: CGFloat
    ) -> CGPoint {
        let vector = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let length = max(sqrt(vector.x * vector.x + vector.y * vector.y), 0.0001)
        let unit = CGPoint(x: vector.x / length, y: vector.y / length)

        return CGPoint(
            x: clamp(point.x + unit.x * paddingRatio),
            y: clamp(point.y + unit.y * paddingRatio)
        )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
