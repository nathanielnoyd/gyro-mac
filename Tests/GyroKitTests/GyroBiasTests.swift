import Testing
@testable import GyroKit

struct GyroBiasTests {
    /// Measured on an M5 Pro MacBook Pro at rest (see the tilt recording fixture).
    private let restingBias = Vector3(x: 0.383, y: 0.12, z: 0.056)
    private let restingGravity = Vector3(x: -0.008, y: -0.008, z: -0.979)

    @Test func yawHoldsSteadyAtRest() {
        var tracker = MotionTracker()
        var sensor = SimulatedIMU(bias: restingBias, gravity: restingGravity)
        sensor.run(seconds: 120, into: &tracker)

        #expect(abs(tracker.snapshot.attitude.yaw) < 0.2)
        #expect(tracker.snapshot.isStill)
        #expect((tracker.biasEstimator.bias - restingBias).magnitude < 0.03)
        #expect(tracker.snapshot.rotationRate.magnitude < 0.5)
    }

    /// The same scenario with bias learning switched off, to show the test above can fail.
    @Test func yawDriftsWithoutBiasEstimation() {
        var tracker = MotionTracker()
        tracker.biasEstimator.settleTime = .infinity
        var sensor = SimulatedIMU(bias: restingBias, gravity: restingGravity)
        sensor.run(seconds: 120, into: &tracker)

        #expect(abs(tracker.snapshot.attitude.yaw) > 5)
    }

    @Test func realRotationIsNotAbsorbedIntoBias() {
        var tracker = MotionTracker()
        var sensor = SimulatedIMU(bias: restingBias, gravity: restingGravity)
        sensor.run(seconds: 3, into: &tracker)
        let learnedBias = tracker.biasEstimator.bias

        // Spin 90° around the vertical axis over two seconds, then rest again.
        sensor.rotation = Vector3(x: 0, y: 0, z: 45)
        sensor.run(seconds: 2, into: &tracker)
        #expect(!tracker.snapshot.isStill)
        sensor.rotation = .zero
        sensor.run(seconds: 3, into: &tracker)

        #expect(abs(tracker.snapshot.attitude.yaw - 90) < 1)
        #expect((tracker.biasEstimator.bias - learnedBias).magnitude < 0.05)
    }

    @Test func vibrationIsNotMistakenForStillness() {
        var estimator = GyroBiasEstimator()
        var random = SplitMix64(seed: 7)
        for step in 0..<8_000 {
            // A 0.1 g buzz with no rotation, like a laptop on a running washing machine.
            let buzz = 0.1 * (step.isMultiple(of: 2) ? 1.0 : -1.0)
            let acceleration = Vector3(x: 0, y: 0, z: -1 + buzz + random.noise(0.01))
            estimator.update(rotationRate: restingBias, acceleration: acceleration, dt: 1.0 / 800)
        }
        #expect(!estimator.isStill)
        #expect(estimator.bias == .zero)
    }
}

/// Generates noisy IMU readings for a MacBook with the given bias, rotating at `rotation`.
private struct SimulatedIMU {
    var bias: Vector3
    var gravity: Vector3
    /// True rotation rate, in degrees per second.
    var rotation: Vector3 = .zero
    var rate = 800.0

    private var time = 0.0
    private var random = SplitMix64(seed: 42)

    init(bias: Vector3, gravity: Vector3) {
        self.bias = bias
        self.gravity = gravity
    }

    mutating func run(seconds: Double, into tracker: inout MotionTracker) {
        for _ in 0..<Int(seconds * rate) {
            let accelerationNoise = Vector3(x: random.noise(0.008), y: random.noise(0.008), z: random.noise(0.008))
            let gyroNoise = Vector3(x: random.noise(0.3), y: random.noise(0.3), z: random.noise(0.3))
            tracker.process(MotionSample(kind: .acceleration, value: gravity + accelerationNoise, timestamp: time))
            tracker.process(MotionSample(kind: .rotationRate, value: rotation + bias + gyroNoise, timestamp: time))
            time += 1 / rate
        }
    }
}

/// A small, seedable random number generator, so tests are repeatable.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value in `-amplitude...amplitude`.
    mutating func noise(_ amplitude: Double) -> Double {
        (Double(next() >> 11) / Double(1 << 53) * 2 - 1) * amplitude
    }
}
