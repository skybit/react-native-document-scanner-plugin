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
const scannerViewController = read(
  'ios/CustomScanner/ScannerViewController.swift'
);
const documentDetector = read('ios/CustomScanner/DocumentDetector.swift');
const overlayMapper = read('ios/CustomScanner/DocumentOverlayMapper.swift');

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
