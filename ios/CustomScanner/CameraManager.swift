import AVFoundation
import UIKit

/// Protocol for receiving camera frame data
protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didCapturePhoto image: UIImage)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

/// Manages the AVCaptureSession for camera preview and photo capture
@available(iOS 13.0, *)
class CameraManager: NSObject {
    
    weak var delegate: CameraManagerDelegate?
    
    /// The capture session
    private let captureSession = AVCaptureSession()
    
    /// Photo output for high-quality captures
    private let photoOutput = AVCapturePhotoOutput()
    
    /// Video data output for real-time frame analysis
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    /// Background queue for video frame processing
    private let videoDataQueue = DispatchQueue(label: "com.documentscanner.videodata", qos: .userInitiated)
    
    /// Preview layer for displaying camera feed
    private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()
    
    /// Whether the camera is currently running
    private(set) var isRunning = false
    
    /// Flag to prevent multiple simultaneous captures
    private var isCapturing = false
    
    // MARK: - Setup
    
    /// Configure and start the camera session
    func startSession() {
        guard !isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
            self?.isRunning = true
        }
    }
    
    /// Stop the camera session
    func stopSession() {
        guard isRunning else { return }
        captureSession.stopRunning()
        isRunning = false
    }
    
    /// Configure the capture session with camera input, video output, and photo output
    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let error = NSError(domain: "CameraManager", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Unable to access camera"])
                self.delegate?.cameraManager(self, didFailWithError: error)
            }
            return
        }
        
        if captureSession.canAddInput(cameraInput) {
            captureSession.addInput(cameraInput)
        }
        
        // Configure auto-focus
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            try? camera.lockForConfiguration()
            camera.focusMode = .continuousAutoFocus
            camera.unlockForConfiguration()
        }
        
        // Add video data output for frame analysis
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            configurePortraitOrientation(for: videoDataOutput.connection(with: .video))
        }
        
        // Add photo output for high-quality capture
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            configurePortraitOrientation(for: photoOutput.connection(with: .video))
        }
        
        captureSession.commitConfiguration()
        configurePortraitOrientation(for: previewLayer.connection)
    }
    
    // MARK: - Capture
    
    /// Take a high-resolution photo
    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        configurePortraitOrientation(for: photoOutput.connection(with: .video))
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configurePortraitOrientation(for connection: AVCaptureConnection?) {
        guard let connection = connection else { return }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

@available(iOS 13.0, *)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

@available(iOS 13.0, *)
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        
        if let error = error {
            delegate?.cameraManager(self, didFailWithError: error)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            let error = NSError(domain: "CameraManager", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Unable to process captured photo"])
            delegate?.cameraManager(self, didFailWithError: error)
            return
        }
        
        delegate?.cameraManager(self, didCapturePhoto: image)
    }
}
