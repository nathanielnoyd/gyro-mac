/// The latest motion readings, plus the orientation estimated from them.
public struct MotionSnapshot: Hashable, Sendable, Codable {
    /// Acceleration including gravity, in g. Lying flat, z reads about −1 g.
    public var acceleration: Vector3 = .zero
    /// Angular velocity, in degrees per second.
    public var rotationRate: Vector3 = .zero
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
/// supply the gravity reference for the next gyroscope step.
public struct MotionTracker: Sendable {
    public private(set) var snapshot = MotionSnapshot()
    public var filter: MahonyFilter

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
            snapshot.rotationRate = sample.value
            defer { lastGyroTimestamp = sample.timestamp }
            guard hasAcceleration, let last = lastGyroTimestamp else { return }

            let dt = sample.timestamp - last
            guard dt > 0, dt < Self.maximumStep else { return }
            let radiansPerSecond = Vector3(x: sample.value.x.radians, y: sample.value.y.radians, z: sample.value.z.radians)
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
