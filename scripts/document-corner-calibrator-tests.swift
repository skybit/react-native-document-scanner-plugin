import CoreGraphics
import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertApproximatelyEqual(_ actual: CGFloat, _ expected: CGFloat, tolerance: CGFloat = 0.0001, _ message: String) {
    assert(abs(actual - expected) <= tolerance, "\(message): expected \(expected), got \(actual)")
}

func center(of corners: DocumentCorners) -> CGPoint {
    CGPoint(
        x: (corners.topLeft.x + corners.topRight.x + corners.bottomRight.x + corners.bottomLeft.x) / 4,
        y: (corners.topLeft.y + corners.topRight.y + corners.bottomRight.y + corners.bottomLeft.y) / 4
    )
}

func testExpandsCornersOutwardAndPreservesCenter() {
    let rectangle = DocumentCorners(
        topLeft: CGPoint(x: 0.25, y: 0.75),
        topRight: CGPoint(x: 0.75, y: 0.75),
        bottomRight: CGPoint(x: 0.75, y: 0.25),
        bottomLeft: CGPoint(x: 0.25, y: 0.25)
    )

    let expanded = DocumentCornerCalibrator.calibrate(rectangle, paddingRatio: 0.04)
    assert(expanded.topLeft.x < rectangle.topLeft.x, "top-left x should expand outward")
    assert(expanded.topLeft.y > rectangle.topLeft.y, "top-left y should expand outward")
    assert(expanded.topRight.x > rectangle.topRight.x, "top-right x should expand outward")
    assert(expanded.topRight.y > rectangle.topRight.y, "top-right y should expand outward")
    assert(expanded.bottomRight.x > rectangle.bottomRight.x, "bottom-right x should expand outward")
    assert(expanded.bottomRight.y < rectangle.bottomRight.y, "bottom-right y should expand outward")
    assert(expanded.bottomLeft.x < rectangle.bottomLeft.x, "bottom-left x should expand outward")
    assert(expanded.bottomLeft.y < rectangle.bottomLeft.y, "bottom-left y should expand outward")

    let originalCenter = center(of: rectangle)
    let expandedCenter = center(of: expanded)
    assertApproximatelyEqual(expandedCenter.x, originalCenter.x, "calibration should preserve center x")
    assertApproximatelyEqual(expandedCenter.y, originalCenter.y, "calibration should preserve center y")
}

func testClampsCornersToNormalizedBounds() {
    let nearEdge = DocumentCorners(
        topLeft: CGPoint(x: 0.01, y: 0.99),
        topRight: CGPoint(x: 0.99, y: 0.99),
        bottomRight: CGPoint(x: 0.99, y: 0.01),
        bottomLeft: CGPoint(x: 0.01, y: 0.01)
    )

    let clamped = DocumentCornerCalibrator.calibrate(nearEdge, paddingRatio: 0.08)
    let clampedPoints = [clamped.topLeft, clamped.topRight, clamped.bottomRight, clamped.bottomLeft]
    for point in clampedPoints {
        assert(point.x >= 0 && point.x <= 1, "calibrated x should be clamped")
        assert(point.y >= 0 && point.y <= 1, "calibrated y should be clamped")
    }
    assertApproximatelyEqual(clamped.topLeft.x, 0, "top-left x should clamp to zero")
    assertApproximatelyEqual(clamped.topLeft.y, 1, "top-left y should clamp to one")
    assertApproximatelyEqual(clamped.bottomRight.x, 1, "bottom-right x should clamp to one")
    assertApproximatelyEqual(clamped.bottomRight.y, 0, "bottom-right y should clamp to zero")
}

@main
struct DocumentCornerCalibratorTestRunner {
    static func main() {
        testExpandsCornersOutwardAndPreservesCenter()
        testClampsCornersToNormalizedBounds()
        print("DocumentCornerCalibrator tests passed")
    }
}
