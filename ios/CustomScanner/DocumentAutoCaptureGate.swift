import CoreGraphics
import Foundation

struct DocumentDetectionCandidate {
    let boundingRect: CGRect
    let corners: [CGPoint]
}

struct DocumentAutoCaptureResult {
    let shouldCapture: Bool
    let stableFrameCount: Int
}

struct DocumentAutoCaptureGate {
    private let minimumAreaRatio: CGFloat = 0.16
    private let maximumAreaRatio: CGFloat = 0.90
    private let minimumSideRatio: CGFloat = 0.25
    private let minimumAspectRatio: CGFloat = 0.45
    private let maximumAspectRatio: CGFloat = 2.4
    private let stabilityIoUThreshold: CGFloat = 0.94
    private let requiredStableFrames: Int = 12
    private let minimumStableDuration: TimeInterval = 1.2

    private var lastCandidate: DocumentDetectionCandidate?
    private var stableFrameCount = 0
    private var stableSince: TimeInterval?
    private var hasTriggeredCapture = false

    mutating func evaluate(
        _ candidate: DocumentDetectionCandidate,
        timestamp: TimeInterval
    ) -> DocumentAutoCaptureResult {
        guard isPlausibleDocument(candidate) else {
            reset()
            return DocumentAutoCaptureResult(shouldCapture: false, stableFrameCount: 0)
        }

        if let last = lastCandidate, calculateIoU(last.boundingRect, candidate.boundingRect) >= stabilityIoUThreshold {
            stableFrameCount += 1
            if stableSince == nil {
                stableSince = timestamp
            }
        } else {
            stableFrameCount = 1
            stableSince = timestamp
            hasTriggeredCapture = false
        }

        lastCandidate = candidate

        let stableDuration = timestamp - (stableSince ?? timestamp)
        let shouldCapture = !hasTriggeredCapture &&
            stableFrameCount >= requiredStableFrames &&
            stableDuration >= minimumStableDuration

        if shouldCapture {
            hasTriggeredCapture = true
        }

        return DocumentAutoCaptureResult(
            shouldCapture: shouldCapture,
            stableFrameCount: stableFrameCount
        )
    }

    mutating func reset() {
        lastCandidate = nil
        stableFrameCount = 0
        stableSince = nil
        hasTriggeredCapture = false
    }

    private func isPlausibleDocument(_ candidate: DocumentDetectionCandidate) -> Bool {
        let rect = candidate.boundingRect.standardized
        guard rect.width > 0, rect.height > 0 else { return false }

        let areaRatio = rect.width * rect.height
        guard areaRatio >= minimumAreaRatio, areaRatio <= maximumAreaRatio else {
            return false
        }

        guard rect.width >= minimumSideRatio, rect.height >= minimumSideRatio else {
            return false
        }

        let aspectRatio = rect.width / rect.height
        guard aspectRatio >= minimumAspectRatio, aspectRatio <= maximumAspectRatio else {
            return false
        }

        return hasUsableCorners(candidate.corners)
    }

    private func hasUsableCorners(_ corners: [CGPoint]) -> Bool {
        guard corners.count == 4 else { return false }

        let sideLengths = (0..<4).map { index -> CGFloat in
            let current = corners[index]
            let next = corners[(index + 1) % 4]
            return hypot(current.x - next.x, current.y - next.y)
        }

        guard let shortest = sideLengths.min(), let longest = sideLengths.max() else {
            return false
        }

        guard shortest >= minimumSideRatio * 0.75, longest / shortest <= 3.0 else {
            return false
        }

        return polygonArea(corners) >= minimumAreaRatio
    }

    private func polygonArea(_ corners: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0

        for index in corners.indices {
            let current = corners[index]
            let next = corners[(index + 1) % corners.count]
            area += current.x * next.y - next.x * current.y
        }

        return abs(area) / 2
    }

    private func calculateIoU(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea

        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
