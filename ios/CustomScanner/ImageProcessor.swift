import UIKit
import Vision
import CoreImage

/// Processes captured images: perspective correction, quality compression, and saving
@available(iOS 13.0, *)
class ImageProcessor {
    private static let confidenceThreshold: Float = 0.5

    /// Detect document corners from the captured still image when the live preview
    /// observation is unavailable or stale.
    static func detectDocumentObservation(in image: UIImage) -> VNRectangleObservation? {
        let normalizedImage = normalizeOrientation(image)
        guard let ciImage = CIImage(image: normalizedImage) else { return nil }

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 4
        rectangleRequest.minimumConfidence = confidenceThreshold
        rectangleRequest.minimumSize = 0.12
        rectangleRequest.minimumAspectRatio = 0.35
        rectangleRequest.maximumAspectRatio = 2.8
        rectangleRequest.quadratureTolerance = 35

        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])
        do {
            try handler.perform([rectangleRequest])
            if let observation = bestObservation(from: rectangleRequest.results) {
                return observation
            }
        } catch {
            return nil
        }

        guard #available(iOS 15.0, *) else { return nil }

        let segmentationRequest = VNDetectDocumentSegmentationRequest()
        do {
            try handler.perform([segmentationRequest])
            return bestObservation(from: segmentationRequest.results)
        } catch {
            return nil
        }
    }

    private static func bestObservation(from observations: [VNRectangleObservation]?) -> VNRectangleObservation? {
        observations?
            .filter { $0.confidence >= confidenceThreshold }
            .sorted { observationArea($0) > observationArea($1) }
            .first
    }

    private static func observationArea(_ observation: VNRectangleObservation) -> CGFloat {
        let minX = min(observation.topLeft.x, observation.bottomLeft.x)
        let maxX = max(observation.topRight.x, observation.bottomRight.x)
        let minY = min(observation.bottomLeft.y, observation.bottomRight.y)
        let maxY = max(observation.topLeft.y, observation.topRight.y)
        return max(maxX - minX, 0) * max(maxY - minY, 0)
    }

    static func selectDocumentObservation(
        capturedObservation: VNRectangleObservation?,
        previewObservation: VNRectangleObservation?
    ) -> VNRectangleObservation? {
        guard let capturedObservation = capturedObservation else {
            return previewObservation
        }
        guard let previewObservation = previewObservation else {
            return capturedObservation
        }

        let capturedArea = observationArea(capturedObservation)
        let previewArea = observationArea(previewObservation)
        let minimumPlausibleArea: CGFloat = 0.12
        let oversizedArea: CGFloat = 0.88

        if previewArea < minimumPlausibleArea {
            return capturedObservation
        }
        if capturedArea < minimumPlausibleArea {
            return previewObservation
        }
        if capturedArea >= oversizedArea && previewArea < capturedArea {
            return previewObservation
        }
        if previewArea >= oversizedArea && capturedArea < previewArea {
            return capturedObservation
        }
        if capturedArea > previewArea * 1.18 {
            return previewObservation
        }

        return capturedObservation
    }
    
    /// Apply perspective correction to an image using the detected document corners
    ///
    /// - Parameters:
    ///   - image: The original captured image
    ///   - observation: The detected document rectangle with corner coordinates
    /// - Returns: The perspective-corrected image, or nil if processing fails
    static func applyPerspectiveCorrection(to image: UIImage, observation: VNRectangleObservation) -> UIImage? {
        let normalizedImage = normalizeOrientation(image)
        guard let ciImage = CIImage(image: normalizedImage) else { return nil }
        
        let imageSize = ciImage.extent.size
        let corners = DocumentCornerCalibrator.calibrate(
            DocumentCorners(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
        )
        
        // Convert Vision normalized coordinates (0-1) to image pixel coordinates
        // Vision coordinates have origin at bottom-left
        let topLeft = CGPoint(
            x: corners.topLeft.x * imageSize.width,
            y: corners.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: corners.topRight.x * imageSize.width,
            y: corners.topRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: corners.bottomLeft.x * imageSize.width,
            y: corners.bottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: corners.bottomRight.x * imageSize.width,
            y: corners.bottomRight.y * imageSize.height
        )
        
        // Apply CIPerspectiveCorrection filter
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    /// Apply mild scan-oriented enhancement while preserving handwriting and red-pen marks.
    static func enhanceScannedImage(_ image: UIImage) -> UIImage {
        let normalizedImage = normalizeOrientation(image)
        guard var output = CIImage(image: normalizedImage) else { return normalizedImage }
        let originalExtent = output.extent

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(output, forKey: kCIInputImageKey)
            colorControls.setValue(1.14, forKey: kCIInputContrastKey)
            colorControls.setValue(0.02, forKey: kCIInputBrightnessKey)
            colorControls.setValue(1.04, forKey: kCIInputSaturationKey)
            if let adjusted = colorControls.outputImage {
                output = adjusted
            }
        }

        if let highlightShadow = CIFilter(name: "CIHighlightShadowAdjust") {
            highlightShadow.setValue(output, forKey: kCIInputImageKey)
            highlightShadow.setValue(0.15, forKey: "inputShadowAmount")
            highlightShadow.setValue(0.95, forKey: "inputHighlightAmount")
            if let adjusted = highlightShadow.outputImage {
                output = adjusted
            }
        }

        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(0.35, forKey: kCIInputSharpnessKey)
            if let adjusted = sharpen.outputImage {
                output = adjusted
            }
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: originalExtent) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    /// Render the image pixels in their displayed orientation before writing JPEG data.
    /// Downstream consumers often ignore EXIF orientation, which can turn portrait scans sideways.
    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale

        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
    
    /// Process a captured image and return either a file path or base64 string
    ///
    /// - Parameters:
    ///   - image: The image to process
    ///   - observation: Optional document observation for perspective correction
    ///   - pageNumber: The page number (for file naming)
    ///   - responseType: "imageFilePath" or "base64"
    ///   - croppedImageQuality: JPEG quality 0-100
    /// - Returns: File path string or base64 string
    /// - Throws: RuntimeError if processing fails
    static func processImage(
        _ image: UIImage,
        observation: VNRectangleObservation?,
        pageNumber: Int,
        responseType: String,
        croppedImageQuality: Int
    ) throws -> String {
        let normalizedInput = normalizeOrientation(image)

        let documentObservation = selectDocumentObservation(
            capturedObservation: detectDocumentObservation(in: normalizedInput),
            previewObservation: observation
        )

        // Compare still-photo and preview detections: still detection can grab
        // the desk/background, while preview detection can be stale.
        let processedImage: UIImage
        if let obs = documentObservation {
            processedImage = applyPerspectiveCorrection(to: normalizedInput, observation: obs) ?? normalizedInput
        } else {
            processedImage = normalizedInput
        }
        let enhancedImage = enhanceScannedImage(processedImage)
        
        // Convert to JPEG data with specified quality
        let quality = CGFloat(croppedImageQuality) / 100.0
        guard let jpegData = enhancedImage.jpegData(compressionQuality: quality) else {
            throw RuntimeError.message("Unable to convert image to JPEG")
        }
        
        switch responseType {
        case ResponseType.base64:
            return jpegData.base64EncodedString()
            
        case ResponseType.imageFilePath:
            let filePath = FileUtil().createImageFile(pageNumber)
            try jpegData.write(to: filePath)
            return filePath.absoluteString
            
        default:
            throw RuntimeError.message("responseType must be \(ResponseType.base64) or \(ResponseType.imageFilePath)")
        }
    }
}
