import Testing

@testable import GyroKit

struct SampleRateMeterTests {
    @Test func reportsNothingUntilAWindowCompletes() {
        var meter = SampleRateMeter()
        meter.record(10, at: 0)
        meter.record(10, at: 0.5)
        #expect(meter.hertz == nil)
    }

    @Test func measuresReadingsPerSecond() throws {
        var meter = SampleRateMeter()
        // Frames every 1/40 s, each carrying the 20 readings that arrived at 800 Hz since the last.
        for frame in 0...80 {
            meter.record(frame == 0 ? 0 : 20, at: Double(frame) / 40)
        }
        let hertz = try #require(meter.hertz)
        #expect(abs(hertz - 800) < 1)
    }

    @Test func resetForgetsTheMeasurement() {
        var meter = SampleRateMeter()
        meter.record(0, at: 0)
        meter.record(100, at: 1)
        #expect(meter.hertz == 100)
        meter.reset()
        #expect(meter.hertz == nil)
    }
}
