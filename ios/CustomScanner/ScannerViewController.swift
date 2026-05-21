import UIKit
import AVFoundation
import Vision

/// Protocol for scanner result callbacks
protocol ScannerViewControllerDelegate: AnyObject {
    func scannerViewController(_ controller: ScannerViewController, didFinishWithImages images: [String])
    func scannerViewControllerDidCancel(_ controller: ScannerViewController)
    func scannerViewController(_ controller: ScannerViewController, didFailWithError errorMessage: String)
}

/// Custom document scanner view controller with auto-capture and page limit support.
/// Uses AVFoundation for camera, Vision for document detection, and CoreImage for
/// perspective correction.
@available(iOS 13.0, *)
class ScannerViewController: UIViewController {
    
    // MARK: - Configuration
    
    weak var delegate: ScannerViewControllerDelegate?
    
    /// Maximum number of documents to scan
    var maxNumDocuments: Int = 1
    
    /// Auto-close after reaching maxNumDocuments
    var autoConfirm: Bool = true
    
    /// Response format: "imageFilePath" or "base64"
    var responseType: String = ResponseType.imageFilePath
    
    /// JPEG quality 0-100
    var croppedImageQuality: Int = 100
    
    // MARK: - Components
    
    private let cameraManager = CameraManager()
    private let documentDetector = DocumentDetector()
    
    // MARK: - State
    
    /// Scanned image results (file paths or base64 strings)
    private var scannedResults: [String] = []
    
    /// The last detected document observation (for perspective correction on capture)
    private var currentObservation: VNRectangleObservation?
    
    /// Whether scanning is complete (reached maxNumDocuments)
    private var isScanComplete: Bool = false
    
    // MARK: - UI Elements
    
    /// Camera preview view
    private var previewView: UIView!
    
    /// Overlay for drawing document edges
    private var overlayLayer: CAShapeLayer!
    
    /// Bottom toolbar
    private var bottomBar: UIView!
    
    /// Capture button
    private var captureButton: UIButton!
    
    /// Done button (shown when autoConfirm=false and scan is complete)
    private var doneButton: UIButton!
    
    /// Page counter label
    private var pageCounterLabel: UILabel!
    
    /// Cancel button
    private var cancelButton: UIButton!
    
    /// Status label for user guidance
    private var statusLabel: UILabel!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        setupDetector()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraManager.startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager.stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraManager.previewLayer.frame = previewView.bounds
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Camera preview
        previewView = UIView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        // Document edge overlay
        overlayLayer = CAShapeLayer()
        overlayLayer.strokeColor = UIColor.systemBlue.cgColor
        overlayLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        overlayLayer.lineWidth = 3.0
        overlayLayer.lineJoin = .round
        
        // Bottom bar
        bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.addSubview(bottomBar)
        
        // Capture button - white circle
        captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        bottomBar.addSubview(captureButton)
        
        // Done button (initially hidden)
        doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = UIColor.systemBlue
        doneButton.layer.cornerRadius = 25
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        doneButton.isHidden = true
        bottomBar.addSubview(doneButton)
        
        // Page counter
        pageCounterLabel = UILabel()
        pageCounterLabel.translatesAutoresizingMaskIntoConstraints = false
        pageCounterLabel.textColor = .white
        pageCounterLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        pageCounterLabel.textAlignment = .center
        bottomBar.addSubview(pageCounterLabel)
        
        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // Status label
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textAlignment = .center
        statusLabel.text = "Position document in view"
        view.addSubview(statusLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Preview fills the screen
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Bottom bar
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 140),
            
            // Capture button (center of bottom bar)
            captureButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            captureButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: -15),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            // Done button (same position as capture button)
            doneButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            doneButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor, constant: -15),
            doneButton.widthAnchor.constraint(equalToConstant: 120),
            doneButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Page counter (below capture button)
            pageCounterLabel.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            pageCounterLabel.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 8),
            
            // Cancel button (top left)
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            // Status label (top center)
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        
        updatePageCounter()
    }
    
    private func setupCamera() {
        cameraManager.delegate = self
        previewView.layer.insertSublayer(cameraManager.previewLayer, at: 0)
        previewView.layer.addSublayer(overlayLayer)
    }
    
    private func setupDetector() {
        documentDetector.delegate = self
    }
    
    // MARK: - UI Updates
    
    private func updatePageCounter() {
        pageCounterLabel.text = "\(scannedResults.count)/\(maxNumDocuments)"
    }
    
    /// Update the document edge overlay on screen
    private func updateOverlay(with observation: VNRectangleObservation?) {
        guard let obs = observation else {
            overlayLayer.path = nil
            return
        }
        
        let previewBounds = previewView.bounds
        
        // Convert Vision coordinates (normalized, bottom-left origin) to UIKit coordinates
        let topLeft = CGPoint(x: obs.topLeft.x * previewBounds.width,
                              y: (1 - obs.topLeft.y) * previewBounds.height)
        let topRight = CGPoint(x: obs.topRight.x * previewBounds.width,
                               y: (1 - obs.topRight.y) * previewBounds.height)
        let bottomRight = CGPoint(x: obs.bottomRight.x * previewBounds.width,
                                  y: (1 - obs.bottomRight.y) * previewBounds.height)
        let bottomLeft = CGPoint(x: obs.bottomLeft.x * previewBounds.width,
                                 y: (1 - obs.bottomLeft.y) * previewBounds.height)
        
        let path = UIBezierPath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()
        
        overlayLayer.path = path.cgPath
    }
    
    // MARK: - Actions
    
    @objc private func captureButtonTapped() {
        guard !isScanComplete else { return }
        performCapture()
    }
    
    @objc private func doneButtonTapped() {
        finishScanning()
    }
    
    @objc private func cancelButtonTapped() {
        cameraManager.stopSession()
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.scannerViewControllerDidCancel(self)
        }
    }
    
    // MARK: - Capture Logic
    
    /// Perform a document capture
    private func performCapture() {
        // Temporarily disable detection during capture
        documentDetector.isEnabled = false
        statusLabel.text = "Capturing..."
        
        // Briefly flash the screen to indicate capture
        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0
        view.addSubview(flashView)
        
        UIView.animate(withDuration: 0.1, animations: {
            flashView.alpha = 0.5
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                flashView.alpha = 0
            }) { _ in
                flashView.removeFromSuperview()
            }
        }
        
        cameraManager.capturePhoto()
    }
    
    /// Process a captured image
    private func processCapturedImage(_ image: UIImage) {
        let pageNumber = scannedResults.count
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let result = try ImageProcessor.processImage(
                    image,
                    observation: self.currentObservation,
                    pageNumber: pageNumber,
                    responseType: self.responseType,
                    croppedImageQuality: self.croppedImageQuality
                )
                
                DispatchQueue.main.async {
                    self.scannedResults.append(result)
                    self.updatePageCounter()
                    
                    if self.scannedResults.count >= self.maxNumDocuments {
                        self.handleScanComplete()
                    } else {
                        // Continue scanning
                        self.documentDetector.resetStability()
                        self.documentDetector.isEnabled = true
                        self.statusLabel.text = "Position next document"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.scannerViewController(self, didFailWithError: error.localizedDescription)
                }
            }
        }
    }
    
    /// Handle when all required documents have been scanned
    private func handleScanComplete() {
        isScanComplete = true
        documentDetector.isEnabled = false
        
        if autoConfirm {
            // Auto-close and return results
            finishScanning()
        } else {
            // Show done button, hide capture button
            captureButton.isHidden = true
            doneButton.isHidden = false
            statusLabel.text = "Scan complete. Tap Done to confirm."
        }
    }
    
    /// Finish scanning and return results
    private func finishScanning() {
        cameraManager.stopSession()
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.delegate?.scannerViewController(self, didFinishWithImages: self.scannedResults)
        }
    }
}

// MARK: - CameraManagerDelegate

@available(iOS 13.0, *)
extension ScannerViewController: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        documentDetector.detectDocument(in: sampleBuffer)
    }
    
    func cameraManager(_ manager: CameraManager, didCapturePhoto image: UIImage) {
        processCapturedImage(image)
    }
    
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        delegate?.scannerViewController(self, didFailWithError: error.localizedDescription)
    }
}

// MARK: - DocumentDetectorDelegate

@available(iOS 13.0, *)
extension ScannerViewController: DocumentDetectorDelegate {
    func documentDetector(_ detector: DocumentDetector, didDetectDocument observation: VNRectangleObservation) {
        currentObservation = observation
        updateOverlay(with: observation)
        statusLabel.text = "Hold steady..."
    }
    
    func documentDetector(_ detector: DocumentDetector, documentDidBecomeStable observation: VNRectangleObservation) {
        guard !isScanComplete else { return }
        currentObservation = observation
        statusLabel.text = "Auto-capturing..."
        performCapture()
    }
    
    func documentDetectorDidLoseDocument(_ detector: DocumentDetector) {
        currentObservation = nil
        updateOverlay(with: nil)
        if !isScanComplete {
            statusLabel.text = "Position document in view"
        }
    }
}
