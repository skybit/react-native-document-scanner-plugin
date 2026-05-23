import Foundation
import UIKit
import Vision

private func fail(_ message: String) -> Never {
    fputs("ImageProcessor photo test failed: \(message)\n", stderr)
    exit(1)
}

private func imageFromBase64(_ base64: String) -> UIImage {
    guard let data = Data(base64Encoded: base64),
          let image = UIImage(data: data) else {
        fail("Unable to decode processed base64 image")
    }
    return image
}

private func process(_ image: UIImage, observation: VNRectangleObservation?) -> UIImage {
    let processedBase64: String
    do {
        processedBase64 = try ImageProcessor.processImage(
            image,
            observation: observation,
            pageNumber: 0,
            responseType: ResponseType.base64,
            croppedImageQuality: 90
        )
    } catch {
        fail("processImage threw \(error)")
    }

    return imageFromBase64(processedBase64)
}

private func rectangle(
    topLeft: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    topRight: CGPoint
) -> VNRectangleObservation {
    VNRectangleObservation(
        requestRevision: 1,
        topLeft: topLeft,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        topRight: topRight
    )
}

private func assertSameObservation(
    _ actual: VNRectangleObservation?,
    _ expected: VNRectangleObservation,
    message: String
) {
    guard let actual = actual else {
        fail("\(message): expected an observation")
    }

    if actual !== expected {
        fail(message)
    }
}

private func assertProcessedScan(_ processedImage: UIImage, differsFrom sourceImage: UIImage) {
    if Int(processedImage.size.width.rounded()) == Int(sourceImage.size.width.rounded()),
       Int(processedImage.size.height.rounded()) == Int(sourceImage.size.height.rounded()) {
        fail("Expected photo processing to detect and crop the document instead of returning original dimensions \(sourceImage.size)")
    }

    let sourceLuma = averageLuma(sourceImage)
    let processedLuma = averageLuma(processedImage)

    if processedLuma <= sourceLuma + 1.0 {
        fail("Expected processed scan to be brighter than the source photo; source=\(sourceLuma), processed=\(processedLuma)")
    }
}

private func averageLuma(_ image: UIImage) -> Double {
    guard let cgImage = image.cgImage,
          let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
        fail("Unable to read image pixels")
    }

    let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
    let sampleStride = max(cgImage.width * cgImage.height / 10_000, 1)
    var total = 0.0
    var count = 0

    for index in stride(from: 0, to: cgImage.width * cgImage.height, by: sampleStride) {
        let offset = index * bytesPerPixel
        let r = Double(bytes[offset])
        let g = Double(bytes[offset + min(1, bytesPerPixel - 1)])
        let b = Double(bytes[offset + min(2, bytesPerPixel - 1)])
        total += 0.299 * r + 0.587 * g + 0.114 * b
        count += 1
    }

    return total / Double(max(count, 1))
}

@main
struct ImageProcessorPhotoTestRunner {
    static func main() {
        let fixturePath = CommandLine.arguments.dropFirst().first
            ?? "/Users/yeyanbo/Projects/error-pilot/apps/server/test-fixtures/llm-eval/biology-genetics.jpg"

        guard let sourceImage = UIImage(contentsOfFile: fixturePath) else {
            fail("Unable to load fixture at \(fixturePath)")
        }

        let tightPreviewObservation = rectangle(
            topLeft: CGPoint(x: 0.18, y: 0.86),
            bottomLeft: CGPoint(x: 0.16, y: 0.16),
            bottomRight: CGPoint(x: 0.84, y: 0.14),
            topRight: CGPoint(x: 0.82, y: 0.88)
        )
        let largeStillObservation = rectangle(
            topLeft: CGPoint(x: 0.02, y: 0.98),
            bottomLeft: CGPoint(x: 0.02, y: 0.02),
            bottomRight: CGPoint(x: 0.98, y: 0.02),
            topRight: CGPoint(x: 0.98, y: 0.98)
        )

        assertSameObservation(
            ImageProcessor.selectDocumentObservation(
                capturedObservation: largeStillObservation,
                previewObservation: tightPreviewObservation
            ),
            tightPreviewObservation,
            message: "Expected tighter preview paper bounds when still-photo detection includes too much background"
        )

        assertSameObservation(
            ImageProcessor.selectDocumentObservation(
                capturedObservation: tightPreviewObservation,
                previewObservation: largeStillObservation
            ),
            tightPreviewObservation,
            message: "Expected still-photo paper bounds when preview observation is stale full-frame"
        )

        assertProcessedScan(process(sourceImage, observation: nil), differsFrom: sourceImage)

        let staleFullFrameObservation = rectangle(
            topLeft: CGPoint(x: 0, y: 1),
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 1, y: 0),
            topRight: CGPoint(x: 1, y: 1)
        )

        assertProcessedScan(
            process(sourceImage, observation: staleFullFrameObservation),
            differsFrom: sourceImage
        )

        print("ImageProcessor photo tests passed")
    }
}
