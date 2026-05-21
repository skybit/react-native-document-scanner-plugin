import Vision
import UIKit

/// Protocol for document detection events
protocol DocumentDetectorDelegate: AnyObject {
    /// Called when a document is detected in a frame (may not be stable yet)
    func documentDetector(_ detector: DocumentDetector, didDetectDocument observation: VNRectangleObservation)
    
    /// Called when the detected document has been stable for enough frames to auto-capture
    func documentDetector(_ detector: DocumentDetector, documentDidBecomeStable observation: VNRectangleObservation)
    
    /// Called when no document is detected in the current frame
    func documentDetectorDidLoseDocument(_ detector: DocumentDetector)
}

/// Detects documents in camera frames using VNDetectDocumentSegmentationRequest.
/// Tracks stability across consecutive frames and triggers auto-capture when
/// the document position is stable.
@available(iOS 13.0, *)
class DocumentDetector {
    
    weak var delegate: DocumentDetectorDelegate?
    
    // MARK: - Configuration
    
    /// Minimum confidence threshold for document detection
    private let confidenceThreshold: Float = 0.85
    
    /// Minimum IoU between consecutive frames to consider "stable"
    private let stabilityIoUThreshold: CGFloat = 0.88
    
    /// Number of consecutive stable frames required before triggering auto-capture
    private let requiredStableFrames: Int = 5
    
    // MARK: - State
    
    /// The last detected observation
    private var lastObservation: VNRectangleObservation?
    
    /// Count of consecutive stable frames
    private var stableFrameCount: Int = 0
    
    /// Whether auto-capture has been triggered for the current stable detection
    private var hasTriggeredCapture: Bool = false
    
    /// Whether detection is enabled
    var isEnabled: Bool = true
    
    /// Serial queue for Vision processing
    private let detectionQueue = DispatchQueue(label: "com.documentscanner.detection", qos: .userInitiated)
    
    // MARK: - Detection
    
    /// Process a camera frame for document detection
    func detectDocument(in sampleBuffer: CMSampleBuffer) {
        guard isEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        detectionQueue.async { [weak self] in
            self?.performDetection(on: pixelBuffer)
        }
    }
    
    /// Perform the Vision document detection request
    private func performDetection(on pixelBuffer: CVPixelBuffer) {
        let request: VNImageBasedRequest
        
        if #available(iOS 15.0, *) {
            // Use document segmentation (more accurate, ML-based) on iOS 15+
            request = VNDetectDocumentSegmentationRequest()
        } else {
            // Fall back to rectangle detection on older iOS
            let rectRequest = VNDetectRectanglesRequest()
            rectRequest.maximumObservations = 1
            rectRequest.minimumConfidence = confidenceThreshold
            rectRequest.minimumSize = 0.2
            request = rectRequest
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([request])
            
            var observation: VNRectangleObservation?
            
            if #available(iOS 15.0, *) {
                if let segRequest = request as? VNDetectDocumentSegmentationRequest {
                    observation = segRequest.results?.first
                }
            } else {
                if let rectRequest = request as? VNDetectRectanglesRequest {
                    observation = rectRequest.results?.first
                }
            }
            
            if let obs = observation, obs.confidence >= confidenceThreshold {
                handleDetectedDocument(obs)
            } else {
                handleNoDocument()
            }
        } catch {
            handleNoDocument()
        }
    }
    
    /// Handle a successfully detected document
    private func handleDetectedDocument(_ observation: VNRectangleObservation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.delegate?.documentDetector(self, didDetectDocument: observation)
            
            // Check stability against last observation
            if let last = self.lastObservation {
                let iou = self.calculateIoU(last, observation)
                
                if iou > self.stabilityIoUThreshold {
                    self.stableFrameCount += 1
                    
                    // Trigger auto-capture when stable for enough frames
                    if self.stableFrameCount >= self.requiredStableFrames && !self.hasTriggeredCapture {
                        self.hasTriggeredCapture = true
                        self.delegate?.documentDetector(self, documentDidBecomeStable: observation)
                    }
                } else {
                    // Document moved - reset stability counter
                    self.stableFrameCount = 1
                    self.hasTriggeredCapture = false
                }
            } else {
                self.stableFrameCount = 1
                self.hasTriggeredCapture = false
            }
            
            self.lastObservation = observation
        }
    }
    
    /// Handle no document detected
    private func handleNoDocument() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastObservation = nil
            self.stableFrameCount = 0
            self.hasTriggeredCapture = false
            self.delegate?.documentDetectorDidLoseDocument(self)
        }
    }
    
    /// Reset detection state (call after a successful capture)
    func resetStability() {
        lastObservation = nil
        stableFrameCount = 0
        hasTriggeredCapture = false
    }
    
    // MARK: - IoU Calculation
    
    /// Calculate Intersection over Union for two quadrilaterals
    /// Uses bounding box approximation for performance
    private func calculateIoU(_ obs1: VNRectangleObservation, _ obs2: VNRectangleObservation) -> CGFloat {
        let rect1 = boundingRect(for: obs1)
        let rect2 = boundingRect(for: obs2)
        
        let intersection = rect1.intersection(rect2)
        
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea
        
        guard unionArea > 0 else { return 0 }
        
        return intersectionArea / unionArea
    }
    
    /// Get the bounding rect from an observation's corner points
    private func boundingRect(for observation: VNRectangleObservation) -> CGRect {
        let points = [observation.topLeft, observation.topRight,
                      observation.bottomLeft, observation.bottomRight]
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
