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

private func makeSyntheticSkewedPaperImage() -> (image: UIImage, observation: VNRectangleObservation) {
    let size = CGSize(width: 900, height: 1200)
    let paperTopLeft = CGPoint(x: 150, y: 150)
    let paperTopRight = CGPoint(x: 765, y: 210)
    let paperBottomRight = CGPoint(x: 810, y: 1060)
    let paperBottomLeft = CGPoint(x: 105, y: 1030)

    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
        UIColor(white: 0.52, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let paper = UIBezierPath()
        paper.move(to: paperTopLeft)
        paper.addLine(to: paperTopRight)
        paper.addLine(to: paperBottomRight)
        paper.addLine(to: paperBottomLeft)
        paper.close()
        UIColor(white: 0.72, alpha: 1).setFill()
        paper.fill()

        UIColor(white: 0.18, alpha: 1).setStroke()
        for index in 0..<18 {
            let y = 285 + CGFloat(index) * 34
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 205, y: y))
            path.addLine(to: CGPoint(x: 705, y: y + CGFloat(index % 3) * 3))
            path.lineWidth = 5
            path.stroke()
        }

        UIColor(red: 0.82, green: 0.08, blue: 0.06, alpha: 1).setStroke()
        let redPath = UIBezierPath()
        redPath.move(to: CGPoint(x: 560, y: 390))
        redPath.addLine(to: CGPoint(x: 680, y: 485))
        redPath.lineWidth = 8
        redPath.stroke()
    }

    let observation = rectangle(
        topLeft: CGPoint(x: paperTopLeft.x / size.width, y: 1 - paperTopLeft.y / size.height),
        bottomLeft: CGPoint(x: paperBottomLeft.x / size.width, y: 1 - paperBottomLeft.y / size.height),
        bottomRight: CGPoint(x: paperBottomRight.x / size.width, y: 1 - paperBottomRight.y / size.height),
        topRight: CGPoint(x: paperTopRight.x / size.width, y: 1 - paperTopRight.y / size.height)
    )

    return (image, observation)
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

private func averageLuma(
    _ image: UIImage,
    xRange: ClosedRange<Int>,
    yRange: ClosedRange<Int>
) -> Double {
    guard let cgImage = image.cgImage,
          let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
        fail("Unable to read image pixels")
    }

    let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
    let minX = cgImage.width * xRange.lowerBound / 100
    let maxX = cgImage.width * xRange.upperBound / 100
    let minY = cgImage.height * yRange.lowerBound / 100
    let maxY = cgImage.height * yRange.upperBound / 100
    var total = 0.0
    var count = 0

    for y in stride(from: minY, to: maxY, by: 4) {
        for x in stride(from: minX, to: maxX, by: 4) {
            let offset = (y * cgImage.width + x) * bytesPerPixel
            let r = Double(bytes[offset])
            let g = Double(bytes[offset + min(1, bytesPerPixel - 1)])
            let b = Double(bytes[offset + min(2, bytesPerPixel - 1)])
            total += 0.299 * r + 0.587 * g + 0.114 * b
            count += 1
        }
    }

    return total / Double(max(count, 1))
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

        let synthetic = makeSyntheticSkewedPaperImage()
        let syntheticProcessed = process(synthetic.image, observation: synthetic.observation)
        let processedPaperLuma = averageLuma(
            syntheticProcessed,
            xRange: 35...65,
            yRange: 7...14
        )
        if processedPaperLuma < 238 {
            fail("Expected gray paper background to be whitened like a scanned page; paper luma=\(processedPaperLuma)")
        }

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
