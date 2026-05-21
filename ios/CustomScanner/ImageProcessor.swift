import UIKit
import Vision
import CoreImage

/// Processes captured images: perspective correction, quality compression, and saving
@available(iOS 13.0, *)
class ImageProcessor {
    
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

        // Apply perspective correction if we have document corners
        let processedImage: UIImage
        if let obs = observation {
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
