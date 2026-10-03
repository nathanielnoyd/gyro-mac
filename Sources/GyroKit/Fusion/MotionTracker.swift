/// The latest motion readings, plus the orientation estimated from them.
public struct MotionSnapshot: Hashable, Sendable, Codable {
    /// Acceleration including gravity, in g. Lying flat, z reads about −1 g.
    public var acceleration: Vector3 = .zero
    /// Angular velocity, in degrees per second, with the learned gyroscope bias removed.
    public var rotationRate: Vector3 = .zero
    /// Whether the Mac is sitting still. While it is, the orientation estimate holds steady.
    public var isStill = false
    public var attitude: Attitude = .zero
    /// The same orientation as ``attitude``, as a quaternion from the sensor frame to the world.
    public var orientation: Quaternion = .identity
    /// Timestamp of the newest reading, in seconds.
    public var timestamp: Double = 0

    public init() {}
}

/// Turns a stream of ``MotionSample`` values into ``MotionSnapshot`` updates.
///
/// Gyroscope samples drive the orientation filter; accelerometer samples
/// supply the gravity reference for the next gyroscope step. The gyroscope's
/// bias is learned whenever the Mac is still, which keeps yaw from drifting.
public struct MotionTracker: Sendable {
    public private(set) var snapshot = MotionSnapshot()
    public var filter: MahonyFilter
    public var biasEstimator = GyroBiasEstimator()

    private var lastGyroTimestamp: Double?
    private var hasAcceleration = false

    /// Gaps longer than this (for example after sleep) restart integration instead of
    /// applying one huge step.
    private static let maximumStep = 0.1

    public init(filter: MahonyFilter = MahonyFilter()) {
        self.filter = filter
    }

    public mutating func process(_ sample: MotionSample) {
        snapshot.timestamp = sample.timestamp

        switch sample.kind {
        case .acceleration:
            snapshot.acceleration = sample.value
            hasAcceleration = true

        case .rotationRate:
            defer { lastGyroTimestamp = sample.timestamp }
            let dt = lastGyroTimestamp.map { sample.timestamp - $0 } ?? 0
            guard hasAcceleration, dt > 0, dt < Self.maximumStep else {
                snapshot.rotationRate = sample.value - biasEstimator.bias
                return
            }

            biasEstimator.update(rotationRate: sample.value, acceleration: snapshot.acceleration, dt: dt)
            snapshot.rotationRate = sample.value - biasEstimator.bias
            snapshot.isStill = biasEstimator.isStill

            // At rest, any measured rotation is noise. Holding the estimate stops it from wandering.
            let rate = snapshot.isStill ? .zero : snapshot.rotationRate
            let radiansPerSecond = Vector3(x: rate.x.radians, y: rate.y.radians, z: rate.z.radians)
            // The accelerometer reports gravity pointing down; the filter wants "up".
            filter.update(rotationRate: radiansPerSecond, acceleration: -snapshot.acceleration, dt: dt)
            snapshot.orientation = filter.orientation
            snapshot.attitude = filter.attitude
        }
    }

    /// Clears the orientation estimate, for example to re-zero yaw.
    public mutating func resetAttitude() {
        filter.reset()
        snapshot.orientation = .identity
        snapshot.attitude = .zero
    }
}
