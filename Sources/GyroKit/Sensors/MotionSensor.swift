/// Streams raw readings from the MacBook's built-in IMU.
///
/// The IMU only reports to processes running as root. Each axis is sampled at
/// up to roughly 1 kHz, and accelerometer and gyroscope readings arrive interleaved.
public struct MotionSensor: Sendable {
    /// The requested time between reports from each sensor.
    public var reportInterval: Duration

    /// Creates a sensor that requests a report every `reportInterval`. Nothing starts until ``samples()``.
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
                    continuation.yield(
                        MotionSample(
                            kind: kind,
                            value: value,
                            timestamp: MachTime.seconds(fromTicks: timestamp)
                        ))
                }
                devices.append(device)
            }
        } catch {
            for device in devices { device.cancel() }
            throw error
        }

        continuation.onTermination = { [devices] _ in
            for device in devices { device.cancel() }
        }
        return stream
    }
}
