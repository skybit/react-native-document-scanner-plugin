import CoreGraphics
import Vision

@available(iOS 13.0, *)
struct DocumentObservationSmoother {
    private let smoothingFactor: CGFloat = 0.22
    private var smoothedCorners: [CGPoint]?

    mutating func smooth(_ observation: VNRectangleObservation) -> VNRectangleObservation {
        let currentCorners = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft,
        ]

        guard let previousCorners = smoothedCorners, previousCorners.count == currentCorners.count else {
            smoothedCorners = currentCorners
            return observation
        }

        let nextCorners = zip(previousCorners, currentCorners).map { previous, current in
            CGPoint(
                x: previous.x + (current.x - previous.x) * smoothingFactor,
                y: previous.y + (current.y - previous.y) * smoothingFactor
            )
        }
        smoothedCorners = nextCorners

        return VNRectangleObservation(
            requestRevision: 1,
            topLeft: nextCorners[0],
            bottomLeft: nextCorners[3],
            bottomRight: nextCorners[2],
            topRight: nextCorners[1]
        )
    }

    mutating func reset() {
        smoothedCorners = nil
    }
}
