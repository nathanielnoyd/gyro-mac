import Foundation
import Testing

@testable import GyroKit

struct SimulatedGestureTests {
    /// The simulation acts out the built-in gestures, so the app can show them without sensors.
    @Test func simulationPerformsBuiltInGestures() {
        var detector = MotionEventDetector()
        var recognizer = MotionEventDetectorTests.presets
        var recognized: [String] = []
        let rate = 800.0
        for step in 0..<Int(SimulatedMotion.period * rate) {
            let time = Double(step) / rate
            let (acceleration, rotationRate) = SimulatedMotion.reading(at: time)
            let events =
                detector.process(MotionSample(kind: .acceleration, value: acceleration, timestamp: time))
                + detector.process(MotionSample(kind: .rotationRate, value: rotationRate, timestamp: time))
            for event in events {
                for recognition in recognizer.recognize(event) {
                    recognized.append((recognition.phase == .ended ? "-" : "") + recognition.id)
                }
            }
        }
        #expect(recognized == ["tap-left", "tap-right", "double-tap", "hard-typing", "-hard-typing"])
    }
}
