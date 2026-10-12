/// One reading from the accelerometer or the gyroscope.
public struct MotionSample: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Acceleration including gravity, in g.
        ///
        /// Uses the same convention as Core Motion: lying flat and still, z reads about −1 g.
        case acceleration
        /// Angular velocity, in degrees per second.
        case rotationRate
    }

    public var kind: Kind
    public var value: Vector3
    /// Seconds on the host's monotonic clock (`mach_absolute_time`).
    public var timestamp: Double

    public init(kind: Kind, value: Vector3, timestamp: Double) {
        self.kind = kind
        self.value = value
        self.timestamp = timestamp
    }
}
