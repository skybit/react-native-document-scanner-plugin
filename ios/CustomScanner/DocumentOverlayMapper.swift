import AVFoundation
import CoreGraphics
import Vision

@available(iOS 13.0, *)
enum DocumentOverlayMapper {
    static func path(
        for observation: VNRectangleObservation,
        in previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPath {
        let corners = DocumentCornerCalibrator.calibrate(
            DocumentCorners(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
        )
        let points = [
            layerPoint(for: corners.topLeft, in: previewLayer),
            layerPoint(for: corners.topRight, in: previewLayer),
            layerPoint(for: corners.bottomRight, in: previewLayer),
            layerPoint(for: corners.bottomLeft, in: previewLayer),
        ]

        let path = CGMutablePath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func layerPoint(
        for visionPoint: CGPoint,
        in previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPoint {
        let capturePoint = CGPoint(x: visionPoint.x, y: 1 - visionPoint.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: capturePoint)
    }
}
