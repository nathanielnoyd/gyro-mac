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

/// Streams raw readings from the MacBook's built-in IMU.
///
/// The IMU only reports to processes running as root. Each axis is sampled at
/// up to roughly 1 kHz, and accelerometer and gyroscope readings arrive interleaved.
public struct MotionSensor: Sendable {
    /// The requested time between reports from each sensor.
    public var reportInterval: Duration

    public init(reportInterval: Duration = .milliseconds(1)) {
        self.reportInterval = reportInterval
    }

    /// Whether this Mac has both an accelerometer and a gyroscope.
    public static var isPresent: Bool {
        SPUSensor.accelerometer.isPresent && SPUSensor.gyroscope.isPresent
    }

    /// Whether this process can read the IMU.
    public static var isReadable: Bool {
        isPresent && SPUSensor.isRunningAsRoot
    }

    /// Starts the sensors and returns their readings. The sensors stop when the stream terminates.
    public func samples() throws(GyroError) -> AsyncStream<MotionSample> {
        let sources: [(SPUSensor, MotionSample.Kind)] = [
            (.accelerometer, .acceleration),
            (.gyroscope, .rotationRate),
        ]
        let (stream, continuation) = AsyncStream.makeStream(
            of: MotionSample.self,
            bufferingPolicy: .bufferingNewest(4_096)
        )

        var devices: [HIDDevice] = []
        do {
            for (sensor, kind) in sources {
                let device = try sensor.makeDevice()
                try sensor.enableReporting(interval: reportInterval)
                try device.startInputReports(maxLength: IMUReport.length) { report, timestamp in
                    guard let value = IMUReport.decode(report) else { return }
                    continuation.yield(MotionSample(
                        kind: kind,
                        value: value,
                        timestamp: MachTime.seconds(fromTicks: timestamp)
                    ))
                }
                devices.append(device)
            }
        } catch {
            devices.forEach { $0.cancel() }
            throw error
        }

        continuation.onTermination = { [devices] _ in
            devices.forEach { $0.cancel() }
        }
        return stream
    }
}
