import Foundation
import Testing
@testable import GyroKit

struct FusionTests {
    @Test func attitudeFromPitchQuaternion() {
        let attitude = Attitude(Quaternion(angle: 30.radians, axis: Vector3(x: 1, y: 0, z: 0)))
        #expect(abs(attitude.pitch - 30) < 1e-9)
        #expect(abs(attitude.roll) < 1e-9)
        #expect(abs(attitude.yaw) < 1e-9)
    }

    @Test func identityReportsLevel() {
        #expect(Attitude(.identity) == .zero)
    }

    @Test(arguments: [-60.0, -15, 0, 20, 45])
    func filterConvergesToPitchFromGravity(pitch: Double) {
        // A MacBook pitched by `pitch` around x sees "up" tilted toward +y.
        let up = Vector3(x: 0, y: sin(pitch.radians), z: cos(pitch.radians))
        var filter = MahonyFilter(proportionalGain: 2, integralGain: 0)
        for _ in 0..<5_000 {
            filter.update(rotationRate: .zero, acceleration: up, dt: 0.001)
        }
        #expect(abs(filter.attitude.pitch - pitch) < 0.5)
        #expect(abs(filter.attitude.roll) < 0.5)
    }

    @Test func filterIntegratesRotationRate() {
        // Rotating at 90°/s about z for one second, with gravity along z, should yield 90° of yaw.
        var filter = MahonyFilter()
        for _ in 0..<1_000 {
            filter.update(rotationRate: Vector3(x: 0, y: 0, z: 90.radians), acceleration: Vector3(x: 0, y: 0, z: 1), dt: 0.001)
        }
        #expect(abs(filter.attitude.yaw - 90) < 0.5)
    }

    /// Readings recorded from an M5 Pro MacBook Pro lying flat and still: gravity reads
    /// about −0.98 g on z and the gyroscope has a small bias. The estimate must stay level.
    @Test func trackerStaysLevelAtRest() {
        var tracker = MotionTracker()
        let gravity = Vector3(x: -0.008, y: -0.008, z: -0.98)
        let gyroBias = Vector3(x: 0.37, y: 0.1, z: 0.07)
        for step in 0..<(800 * 10) {
            let time = Double(step) / 800
            tracker.process(MotionSample(kind: .acceleration, value: gravity, timestamp: time))
            tracker.process(MotionSample(kind: .rotationRate, value: gyroBias, timestamp: time))
        }
        #expect(abs(tracker.snapshot.attitude.pitch) < 1)
        #expect(abs(tracker.snapshot.attitude.roll) < 1)
    }

    @Test func trackerIgnoresGapsAfterSleep() {
        var tracker = MotionTracker()
        tracker.process(MotionSample(kind: .acceleration, value: Vector3(x: 0, y: 0, z: 1), timestamp: 0))
        tracker.process(MotionSample(kind: .rotationRate, value: Vector3(x: 0, y: 0, z: 90), timestamp: 0))
        tracker.process(MotionSample(kind: .rotationRate, value: Vector3(x: 0, y: 0, z: 90), timestamp: 60))
        #expect(tracker.snapshot.attitude == .zero)
        #expect(tracker.snapshot.rotationRate.z == 90)
    }
}
