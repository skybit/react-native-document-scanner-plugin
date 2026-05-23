import CoreGraphics
import Foundation
import Vision

struct ObservationSmootherTestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ObservationSmootherTestFailure(description: message)
    }
}

func observation(
    x: CGFloat,
    y: CGFloat,
    width: CGFloat = 0.62,
    height: CGFloat = 0.58
) -> VNRectangleObservation {
    VNRectangleObservation(
        requestRevision: 1,
        topLeft: CGPoint(x: x, y: y + height),
        bottomLeft: CGPoint(x: x, y: y),
        bottomRight: CGPoint(x: x + width, y: y),
        topRight: CGPoint(x: x + width, y: y + height)
    )
}

func boundingRect(_ observation: VNRectangleObservation) -> CGRect {
    let points = [
        observation.topLeft,
        observation.topRight,
        observation.bottomRight,
        observation.bottomLeft,
    ]
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    return CGRect(
        x: xs.min() ?? 0,
        y: ys.min() ?? 0,
        width: (xs.max() ?? 0) - (xs.min() ?? 0),
        height: (ys.max() ?? 0) - (ys.min() ?? 0)
    )
}

func iou(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let intersection = first.intersection(second)
    guard !intersection.isNull else { return 0 }

    let intersectionArea = intersection.width * intersection.height
    let unionArea = first.width * first.height + second.width * second.height - intersectionArea
    return unionArea > 0 ? intersectionArea / unionArea : 0
}

func testSmoothsJitteryDetections() throws {
    var smoother = DocumentObservationSmoother()
    let jittered = [
        observation(x: 0.18, y: 0.20),
        observation(x: 0.205, y: 0.185),
        observation(x: 0.175, y: 0.21),
        observation(x: 0.202, y: 0.19),
        observation(x: 0.182, y: 0.205),
        observation(x: 0.198, y: 0.192),
    ]

    var previous = smoother.smooth(jittered[0])
    var minimumSmoothedIoU: CGFloat = 1

    for observation in jittered.dropFirst() {
        let smoothed = smoother.smooth(observation)
        minimumSmoothedIoU = min(minimumSmoothedIoU, iou(boundingRect(previous), boundingRect(smoothed)))
        previous = smoothed
    }

    try expect(
        minimumSmoothedIoU >= 0.96,
        "Expected smoothed document bounds to stay visually stable; minimum IoU was \(minimumSmoothedIoU)"
    )
}

@main
struct ObservationSmootherTestRunner {
    static func main() {
        do {
            try testSmoothsJitteryDetections()
            print("Observation smoother tests passed")
        } catch {
            print(error)
            exit(1)
        }
    }
}
