const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

function assertContains(source, needle, message) {
  if (!source.includes(needle)) {
    throw new Error(message);
  }
}

function assertOrder(source, first, second, message) {
  const firstIndex = source.indexOf(first);
  const secondIndex = source.indexOf(second);
  if (firstIndex === -1 || secondIndex === -1 || firstIndex >= secondIndex) {
    throw new Error(message);
  }
}

const documentScanner = read('ios/DocumentScanner.swift');
const documentScannerModule = read('ios/DocumentScanner.mm');
const scannerViewController = read(
  'ios/CustomScanner/ScannerViewController.swift'
);
const cameraManager = read('ios/CustomScanner/CameraManager.swift');
const imageProcessor = read('ios/CustomScanner/ImageProcessor.swift');
const documentDetector = read('ios/CustomScanner/DocumentDetector.swift');
const overlayMapper = read('ios/CustomScanner/DocumentOverlayMapper.swift');

assertContains(
  documentScannerModule,
  '@property (nonatomic, strong) RNDocumentScanner *activeDocumentScanner;',
  'The Objective-C++ module must retain RNDocumentScanner while an async scan is in progress'
);
assertContains(
  documentScannerModule,
  'self.activeDocumentScanner = [RNDocumentScanner new];',
  'The Objective-C++ module must assign the active RNDocumentScanner before presenting UI'
);
assertContains(
  documentScannerModule,
  '__weak DocumentScanner *weakSelf = self;',
  'The Objective-C++ module must use ObjC++-compatible weak self capture syntax'
);
assertContains(
  documentScannerModule,
  'weakSelf.activeDocumentScanner = nil;',
  'The Objective-C++ module must release RNDocumentScanner after resolving or rejecting the promise'
);

const finishScanning = scannerViewController.slice(
  scannerViewController.indexOf('private func finishScanning()'),
  scannerViewController.indexOf('// MARK: - CameraManagerDelegate')
);

assertContains(
  documentScanner,
  'private var scannerDelegateHandler: ScannerDelegateHandler?',
  'RNDocumentScanner must strongly retain ScannerDelegateHandler while the custom scanner is presented'
);
assertContains(
  documentScanner,
  'self.scannerDelegateHandler = delegateHandler',
  'RNDocumentScanner must assign the retained custom scanner delegate handler'
);
assertContains(
  documentScanner,
  'self?.scannerDelegateHandler = nil',
  'RNDocumentScanner must release the retained delegate handler during cleanup'
);

assertContains(
  finishScanning,
  'guard !scannedResults.isEmpty else',
  'Custom scanner must not resolve success with an empty scannedImages array'
);
assertOrder(
  finishScanning,
  'callbackDelegate?.scannerViewController(self, didFinishWithImages: results)',
  'dismiss(animated: true)',
  'Custom scanner should resolve the JS promise before dismissing the controller'
);

assertContains(
  overlayMapper,
  'layerPointConverted(fromCaptureDevicePoint:',
  'Overlay mapping must use AVCaptureVideoPreviewLayer coordinate conversion'
);
assertContains(
  overlayMapper,
  'DocumentCornerCalibrator.calibrate',
  'Overlay mapping must use calibrated document corners'
);

assertContains(
  cameraManager,
  'connection.videoOrientation = .portrait',
  'Camera capture and preview connections must be locked to portrait orientation'
);
assertContains(
  cameraManager,
  'configurePortraitOrientation(for: photoOutput.connection(with: .video))',
  'Photo capture must configure portrait orientation immediately before capture'
);
assertContains(
  imageProcessor,
  'static func normalizeOrientation(_ image: UIImage) -> UIImage',
  'ImageProcessor must normalize UIImage orientation before writing JPEG data'
);
assertContains(
  imageProcessor,
  'orientation: .up',
  'Perspective-corrected images must be returned with .up orientation'
);
assertContains(
  imageProcessor,
  'DocumentCornerCalibrator.calibrate',
  'Perspective correction must use the same calibrated document corners as the overlay'
);
assertContains(
  imageProcessor,
  'static func enhanceScannedImage(_ image: UIImage) -> UIImage',
  'ImageProcessor must expose a scan enhancement step'
);
assertContains(
  imageProcessor,
  'CIColorControls',
  'Scan enhancement must adjust color controls mildly'
);
assertContains(
  imageProcessor,
  'CISharpenLuminance',
  'Scan enhancement must apply mild luminance sharpening'
);

assertOrder(
  documentDetector,
  'let rectangleRequest = makeRectangleDetectionRequest()',
  'detectSegmentedDocument(on: pixelBuffer)',
  'Document detection must prefer rectangle edge detection before segmentation fallback'
);
assertContains(
  documentDetector,
  'request.quadratureTolerance = 25',
  'Rectangle detection should constrain quadrature to avoid loose segmentation-like boxes'
);

console.log('iOS custom scanner invariant checks passed');
