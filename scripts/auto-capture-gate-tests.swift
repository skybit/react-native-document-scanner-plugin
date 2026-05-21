import CoreGraphics
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func makeCandidate(
    x: CGFloat = 0.2,
    y: CGFloat = 0.2,
    width: CGFloat = 0.6,
    height: CGFloat = 0.5
) -> DocumentDetectionCandidate {
    DocumentDetectionCandidate(
        boundingRect: CGRect(x: x, y: y, width: width, height: height),
        corners: [
            CGPoint(x: x, y: y + height),
            CGPoint(x: x + width, y: y + height),
            CGPoint(x: x + width, y: y),
            CGPoint(x: x, y: y),
        ]
    )
}

func testDoesNotTriggerImmediately() throws {
    var gate = DocumentAutoCaptureGate()
    let candidate = makeCandidate()

    for frame in 0..<8 {
        let result = gate.evaluate(candidate, timestamp: Double(frame) * 0.08)
        try expect(!result.shouldCapture, "Gate triggered before minimum stable duration")
    }
}

func testResetsWhenDocumentMoves() throws {
    var gate = DocumentAutoCaptureGate()
    let first = makeCandidate(x: 0.18)
    let moved = makeCandidate(x: 0.3)

    for frame in 0..<10 {
        _ = gate.evaluate(first, timestamp: Double(frame) * 0.1)
    }

    let movedResult = gate.evaluate(moved, timestamp: 1.05)
    try expect(!movedResult.shouldCapture, "Gate triggered on a moved document")

    for frame in 0..<8 {
        let result = gate.evaluate(moved, timestamp: 1.15 + Double(frame) * 0.1)
        try expect(!result.shouldCapture, "Gate triggered before moved document became stable")
    }
}

func testTriggersAfterSustainedStableDetection() throws {
    var gate = DocumentAutoCaptureGate()
    let candidate = makeCandidate()
    var didTrigger = false

    for frame in 0..<20 {
        let result = gate.evaluate(candidate, timestamp: Double(frame) * 0.1)
        if result.shouldCapture {
            didTrigger = true
            break
        }
    }

    try expect(didTrigger, "Gate did not trigger after sustained stable detection")
}

func testRejectsFullFrameWhiteSurface() throws {
    var gate = DocumentAutoCaptureGate()
    let candidate = makeCandidate(x: 0.01, y: 0.01, width: 0.98, height: 0.98)

    for frame in 0..<25 {
        let result = gate.evaluate(candidate, timestamp: Double(frame) * 0.1)
        try expect(!result.shouldCapture, "Gate triggered on an almost full-frame surface")
    }
}

@main
struct AutoCaptureGateTestRunner {
    static func main() {
        let tests = [
            testDoesNotTriggerImmediately,
            testResetsWhenDocumentMoves,
            testTriggersAfterSustainedStableDetection,
            testRejectsFullFrameWhiteSurface,
        ]

        do {
            for test in tests {
                try test()
            }
            print("Auto-capture gate tests passed")
        } catch {
            print(error)
            exit(1)
        }
    }
}
