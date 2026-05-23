import CoreGraphics
import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func testPortraitToCaptureDeviceMapping() {
    // 1. Top-Left in portrait (x: 0, y: 1 in bottom-left origin coordinate space)
    // Should map to (x: 0, y: 0) in capture device space.
    let portraitTopLeft = CGPoint(x: 0.0, y: 1.0)
    let deviceTopLeft = CGPoint(x: 1.0 - portraitTopLeft.y, y: portraitTopLeft.x)
    assert(deviceTopLeft.x == 0.0 && deviceTopLeft.y == 0.0, "Top-left mapping failed: expected (0,0), got \(deviceTopLeft)")

    // 2. Top-Right in portrait (x: 1, y: 1)
    // Should map to (x: 0, y: 1) in capture device space.
    let portraitTopRight = CGPoint(x: 1.0, y: 1.0)
    let deviceTopRight = CGPoint(x: 1.0 - portraitTopRight.y, y: portraitTopRight.x)
    assert(deviceTopRight.x == 0.0 && deviceTopRight.y == 1.0, "Top-right mapping failed: expected (0,1), got \(deviceTopRight)")

    // 3. Bottom-Left in portrait (x: 0, y: 0)
    // Should map to (x: 1, y: 0) in capture device space.
    let portraitBottomLeft = CGPoint(x: 0.0, y: 0.0)
    let deviceBottomLeft = CGPoint(x: 1.0 - portraitBottomLeft.y, y: portraitBottomLeft.x)
    assert(deviceBottomLeft.x == 1.0 && deviceBottomLeft.y == 0.0, "Bottom-left mapping failed: expected (1,0), got \(deviceBottomLeft)")

    // 4. Bottom-Right in portrait (x: 1, y: 0)
    // Should map to (x: 1, y: 1) in capture device space.
    let portraitBottomRight = CGPoint(x: 1.0, y: 0.0)
    let deviceBottomRight = CGPoint(x: 1.0 - portraitBottomRight.y, y: portraitBottomRight.x)
    assert(deviceBottomRight.x == 1.0 && deviceBottomRight.y == 1.0, "Bottom-right mapping failed: expected (1,1), got \(deviceBottomRight)")
    
    print("Coordinate mapping tests passed successfully.")
}

testPortraitToCaptureDeviceMapping()
