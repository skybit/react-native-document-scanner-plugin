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
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let imageSize = ciImage.extent.size
        
        // Convert Vision normalized coordinates (0-1) to image pixel coordinates
        // Vision coordinates have origin at bottom-left
        let topLeft = CGPoint(
            x: observation.topLeft.x * imageSize.width,
            y: observation.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: observation.topRight.x * imageSize.width,
            y: observation.topRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * imageSize.width,
            y: observation.bottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * imageSize.width,
            y: observation.bottomRight.y * imageSize.height
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
        
        return UIImage(cgImage: cgImage)
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
        // Apply perspective correction if we have document corners
        let processedImage: UIImage
        if let obs = observation {
            processedImage = applyPerspectiveCorrection(to: image, observation: obs) ?? image
        } else {
            processedImage = image
        }
        
        // Convert to JPEG data with specified quality
        let quality = CGFloat(croppedImageQuality) / 100.0
        guard let jpegData = processedImage.jpegData(compressionQuality: quality) else {
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
