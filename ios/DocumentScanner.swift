import Foundation
import React

@objc(RNDocumentScanner)
public class RNDocumentScanner: NSObject {
    
    /** @property  documentScanner the native VisionKit document scanner */
    private var documentScanner: DocScanner?
    
    /** @property  scannerViewController the custom scanner for page-limited scanning */
    private var scannerViewController: ScannerViewController?

    @objc(scanDocument:resolve:reject:)
    public func scanDocument(
      _ options: NSDictionary,
      resolve: @escaping RCTPromiseResolveBlock,
      reject: @escaping RCTPromiseRejectBlock
    ) -> Void {
        let maxNumDocuments = options["maxNumDocuments"] as? Int
        let autoConfirm = options["autoConfirm"] as? Bool ?? true
        let responseType = options["responseType"] as? String ?? "imageFilePath"
        let croppedImageQuality = options["croppedImageQuality"] as? Int ?? 100
        
        DispatchQueue.main.async {
            if let maxNum = maxNumDocuments, maxNum > 0 {
                // Use custom scanner when maxNumDocuments is set
                self.presentCustomScanner(
                    maxNumDocuments: maxNum,
                    autoConfirm: autoConfirm,
                    responseType: responseType,
                    croppedImageQuality: croppedImageQuality,
                    resolve: resolve,
                    reject: reject
                )
            } else {
                // Use native VisionKit scanner (existing behavior)
                self.presentNativeScanner(
                    options: options,
                    resolve: resolve,
                    reject: reject
                )
            }
        }
    }
    
    // MARK: - Custom Scanner (with page limit + autoConfirm)
    
    private func presentCustomScanner(
        maxNumDocuments: Int,
        autoConfirm: Bool,
        responseType: String,
        croppedImageQuality: Int,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        if #available(iOS 13.0, *) {
            let scanner = ScannerViewController()
            scanner.maxNumDocuments = maxNumDocuments
            scanner.autoConfirm = autoConfirm
            scanner.responseType = responseType
            scanner.croppedImageQuality = croppedImageQuality
            scanner.delegate = ScannerDelegateHandler(resolve: resolve, reject: reject, cleanup: { [weak self] in
                self?.scannerViewController = nil
            })
            scanner.modalPresentationStyle = .fullScreen
            
            self.scannerViewController = scanner
            
            guard let currentViewController = RCTPresentedViewController() else {
                reject("error", "Unable to get the current view controller", nil)
                return
            }
            currentViewController.present(scanner, animated: true)
        } else {
            reject("error", "Custom scanner requires iOS 13.0+", nil)
        }
    }
    
    // MARK: - Native VisionKit Scanner (existing behavior)
    
    private func presentNativeScanner(
        options: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        self.documentScanner = DocScanner()
        
        self.documentScanner?.startScan(
            RCTPresentedViewController(),
            successHandler: { (scannedDocumentImages: [String]) in
                resolve([
                    "status": "success",
                    "scannedImages": scannedDocumentImages
                ])
                self.documentScanner = nil
            },
            errorHandler: { (errorMessage: String) in
                reject("document scan error", errorMessage, nil)
                self.documentScanner = nil
            },
            cancelHandler: {
                resolve([
                    "status": "cancel"
                ])
                self.documentScanner = nil
            },
            responseType: options["responseType"] as? String,
            croppedImageQuality: options["croppedImageQuality"] as? Int
        )
    }
}

// MARK: - Scanner Delegate Handler

/// Handles ScannerViewController delegate callbacks and resolves/rejects the React Native promise
@available(iOS 13.0, *)
private class ScannerDelegateHandler: NSObject, ScannerViewControllerDelegate {
    private let resolve: RCTPromiseResolveBlock
    private let reject: RCTPromiseRejectBlock
    private let cleanup: () -> Void
    
    init(resolve: @escaping RCTPromiseResolveBlock,
         reject: @escaping RCTPromiseRejectBlock,
         cleanup: @escaping () -> Void) {
        self.resolve = resolve
        self.reject = reject
        self.cleanup = cleanup
    }
    
    func scannerViewController(_ controller: ScannerViewController, didFinishWithImages images: [String]) {
        resolve([
            "status": "success",
            "scannedImages": images
        ])
        cleanup()
    }
    
    func scannerViewControllerDidCancel(_ controller: ScannerViewController) {
        resolve([
            "status": "cancel"
        ])
        cleanup()
    }
    
    func scannerViewController(_ controller: ScannerViewController, didFailWithError errorMessage: String) {
        reject("document scan error", errorMessage, nil)
        cleanup()
    }
}
