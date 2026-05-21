import UIKit
import VisionKit

/**
 This class uses VisionKit to start a document scan. It either returns the
 cropped images in base64 or as file paths depending on the configuration.
 */
@available(iOS 13.0, *)
public class DocScanner: NSObject, VNDocumentCameraViewControllerDelegate {
    /** @property viewController the document scanner gets called from this view controller */
    private var viewController: UIViewController?

    /** @property successHandler a callback triggered when the user completes the document scan successfully */
    private var successHandler: ([String]) -> Void

    /** @property errorHandler a callback triggered when there's an error */
    private var errorHandler: (String) -> Void

    /** @property cancelHandler a callback triggered when the user cancels the document scan */
    private var cancelHandler: () -> Void

    /** @property responseType determines the format response (base64 or file paths) */
    private var responseType: String

    /** @property croppedImageQuality the 0 - 100 quality of the cropped image */
    private var croppedImageQuality: Int

    public init(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String = ResponseType.imageFilePath,
        croppedImageQuality: Int = 100
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType
        self.croppedImageQuality = croppedImageQuality
    }

    public convenience override init() {
        self.init(nil)
    }

    public func startScan() {
        if !VNDocumentCameraViewController.isSupported {
            self.errorHandler("Document scanning is not supported on this device")
            return
        }

        DispatchQueue.main.async {
            let documentCameraViewController = VNDocumentCameraViewController()
            documentCameraViewController.delegate = self
            self.viewController?.present(documentCameraViewController, animated: true)
        }
    }

    public func startScan(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String? = ResponseType.imageFilePath,
        croppedImageQuality: Int? = 100
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType ?? ResponseType.imageFilePath
        self.croppedImageQuality = croppedImageQuality ?? 100

        self.startScan()
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        var results: [String] = []

        for pageNumber in 0 ..< scan.pageCount {
            guard let scannedDocumentImage = scan
                .imageOfPage(at: pageNumber)
                .jpegData(compressionQuality: CGFloat(self.croppedImageQuality) / CGFloat(100))
            else {
                goBackToPreviousView(controller)
                self.errorHandler("Unable to get scanned document in jpeg format")
                return
            }

            switch responseType {
            case ResponseType.base64:
                results.append(scannedDocumentImage.base64EncodedString())
            case ResponseType.imageFilePath:
                do {
                    let croppedImageFilePath = FileUtil().createImageFile(pageNumber)
                    try scannedDocumentImage.write(to: croppedImageFilePath)
                    results.append(croppedImageFilePath.absoluteString)
                } catch {
                    goBackToPreviousView(controller)
                    self.errorHandler("Unable to save scanned image: \(error.localizedDescription)")
                    return
                }
            default:
                self.errorHandler(
                    "responseType must be \(ResponseType.base64) or \(ResponseType.imageFilePath)"
                )
            }
        }

        goBackToPreviousView(controller)
        self.successHandler(results)
    }

    public func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        goBackToPreviousView(controller)
        self.cancelHandler()
    }

    public func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        goBackToPreviousView(controller)
        self.errorHandler(error.localizedDescription)
    }

    private func goBackToPreviousView(_ controller: VNDocumentCameraViewController) {
        DispatchQueue.main.async {
            controller.dismiss(animated: true)
        }
    }
}
