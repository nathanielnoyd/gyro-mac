/// One reading from the accelerometer or the gyroscope.
public struct MotionSample: Hashable, Sendable, Codable {
    /// Which sensor a reading came from, and so what its value means.
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Acceleration including gravity, in g.
        ///
        /// Uses the same convention as Core Motion: lying flat and still, z reads about −1 g.
        case acceleration
        /// Angular velocity, in degrees per second.
        case rotationRate
    }

    /// Which sensor the reading came from.
    public var kind: Kind
    /// The reading on each axis, in the unit ``kind`` describes.
    public var value: Vector3
    /// Seconds on the host's monotonic clock (`mach_absolute_time`).
    public var timestamp: Double

    /// Creates a sample.
    public init(kind: Kind, value: Vector3, timestamp: Double) {
        self.kind = kind
        self.value = value
        self.timestamp = timestamp
    }
}
