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
    
    /// Minimum confidence threshold for document detection.
    private let confidenceThreshold: Float = 0.7
    
    // MARK: - State
    
    /// Guards auto-capture so a transient white surface is not captured immediately.
    private var autoCaptureGate = DocumentAutoCaptureGate()

    /// Smooths frame-to-frame Vision jitter before updating the overlay and stability gate.
    private var observationSmoother = DocumentObservationSmoother()
    
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            let rectangleRequest = makeRectangleDetectionRequest()
            try handler.perform([rectangleRequest])

            let observation = bestObservation(from: rectangleRequest.results) ?? detectSegmentedDocument(on: pixelBuffer)
            
            if let obs = observation, obs.confidence >= confidenceThreshold {
                handleDetectedDocument(obs)
            } else {
                handleNoDocument()
            }
        } catch {
            handleNoDocument()
        }
    }

    private func makeRectangleDetectionRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4
        request.minimumConfidence = confidenceThreshold
        request.minimumSize = 0.18
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 2.6
        request.quadratureTolerance = 25
        return request
    }

    private func detectSegmentedDocument(on pixelBuffer: CVPixelBuffer) -> VNRectangleObservation? {
        guard #available(iOS 15.0, *) else { return nil }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            return bestObservation(from: request.results)
        } catch {
            return nil
        }
    }

    private func bestObservation(from observations: [VNRectangleObservation]?) -> VNRectangleObservation? {
        observations?
            .filter { $0.confidence >= confidenceThreshold }
            .sorted { observationArea($0) > observationArea($1) }
            .first
    }

    private func observationArea(_ observation: VNRectangleObservation) -> CGFloat {
        let rect = boundingRect(for: observation)
        return rect.width * rect.height
    }
    
    /// Handle a successfully detected document
    private func handleDetectedDocument(_ observation: VNRectangleObservation) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let smoothedObservation = self.observationSmoother.smooth(observation)
            
            self.delegate?.documentDetector(self, didDetectDocument: smoothedObservation)

            let result = self.autoCaptureGate.evaluate(
                self.makeCandidate(from: smoothedObservation),
                timestamp: CACurrentMediaTime()
            )

            if result.shouldCapture {
                self.delegate?.documentDetector(self, documentDidBecomeStable: smoothedObservation)
            }
        }
    }
    
    /// Handle no document detected
    private func handleNoDocument() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.autoCaptureGate.reset()
            self.observationSmoother.reset()
            self.delegate?.documentDetectorDidLoseDocument(self)
        }
    }
    
    /// Reset detection state (call after a successful capture)
    func resetStability() {
        autoCaptureGate.reset()
        observationSmoother.reset()
    }

    private func makeCandidate(from observation: VNRectangleObservation) -> DocumentDetectionCandidate {
        DocumentDetectionCandidate(
            boundingRect: boundingRect(for: observation),
            corners: [
                observation.topLeft,
                observation.topRight,
                observation.bottomRight,
                observation.bottomLeft,
            ]
        )
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
