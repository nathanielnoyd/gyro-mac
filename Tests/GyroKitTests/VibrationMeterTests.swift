import Testing

@testable import GyroKit

struct VibrationMeterTests {
    @Test func restingMacReadsNearZero() {
        var meter = VibrationMeter()
        for _ in 0..<2_000 {
            meter.process(acceleration: Vector3(x: 0, y: 0, z: -0.98))
        }
        #expect(meter.takePeak() < 1e-9)
    }

    @Test func tapShowsAsSpikeThenClears() {
        var meter = VibrationMeter()
        for _ in 0..<2_000 {
            meter.process(acceleration: Vector3(x: 0, y: 0, z: -0.98))
        }
        meter.process(acceleration: Vector3(x: 0, y: 0, z: -1.08))
        #expect(abs(meter.takePeak() - 0.1) < 0.001)
        #expect(meter.peak == 0)
    }
}
