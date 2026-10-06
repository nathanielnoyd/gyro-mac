/// Learns the gyroscope's bias whenever the Mac is sitting still.
///
/// MEMS gyroscopes report a small constant rotation even at rest (about 0.4 °/s
/// on an M5 Pro MacBook Pro). Integrated over time that becomes drift, and for yaw
/// nothing else corrects it. While the Mac is still, every reading is bias plus
/// noise, so averaging those readings gives the bias.
///
/// Stillness means the bias-corrected rotation, smoothed over about 50 ms, stays
/// under ``rotationThreshold`` and the total acceleration stays steady, both for
/// at least ``settleTime``. Rotation slower than the threshold is indistinguishable
/// from rest, so it is ignored.
public struct GyroBiasEstimator: Sendable {
    /// Smoothed rotation, in degrees per second, below which the Mac may be still.
    public var rotationThreshold = 0.75
    /// How far, in g, the total acceleration may stray from its recent average while still.
    public var accelerationTolerance = 0.04
    /// How long, in seconds, both conditions must hold before the Mac counts as still.
    public var settleTime = 0.5
    /// After this many seconds of stillness, older readings fade out of the bias estimate.
    public var memory = 4.0

    /// The estimated bias, in degrees per second.
    public private(set) var bias: Vector3 = .zero
    /// Whether the Mac is currently still.
    public private(set) var isStill = false

    private static let smoothingTime = 0.05
    private static let restingMagnitudeTime = 1.0

    private var smoothedRate: Vector3 = .zero
    private var restingMagnitude: Double?
    private var stillDuration = 0.0
    private var learningDuration = 0.0

    public init() {}

    /// Feeds one gyroscope reading, the latest acceleration, and the seconds since the previous reading.
    public mutating func update(rotationRate: Vector3, acceleration: Vector3, dt: Double) {
        guard dt > 0 else { return }

        let corrected = rotationRate - bias
        smoothedRate += (corrected - smoothedRate) * min(dt / Self.smoothingTime, 1)

        let magnitude = acceleration.magnitude
        let resting = restingMagnitude.map { $0 + (magnitude - $0) * min(dt / Self.restingMagnitudeTime, 1) } ?? magnitude
        restingMagnitude = resting

        let calm = smoothedRate.magnitude < rotationThreshold && abs(magnitude - resting) < accelerationTolerance
        stillDuration = calm ? stillDuration + dt : 0
        isStill = stillDuration >= settleTime
        guard isStill else { return }

        // A plain running average at first, so the first calibration is quick,
        // then an exponential average so the estimate follows temperature changes.
        learningDuration += dt
        bias += corrected * (dt / min(learningDuration, memory))
    }

    /// Forgets the learned bias and stillness, keeping the thresholds.
    public mutating func reset() {
        var fresh = GyroBiasEstimator()
        fresh.rotationThreshold = rotationThreshold
        fresh.accelerationTolerance = accelerationTolerance
        fresh.settleTime = settleTime
        fresh.memory = memory
        self = fresh
    }
}
