import GyroKit

/// An error whose message is shown to the user as is.
struct CLIError: Error, CustomStringConvertible {
    let description: String
}

extension MotionSensor {
    /// Starts the IMU, turning the common "not root" failure into a hint for `subcommand`.
    func samples(orExplain subcommand: String) throws -> AsyncStream<MotionSample> {
        do {
            return try samples()
        } catch .requiresRoot {
            throw CLIError(description: """
                The accelerometer and gyroscope only report to root. Run:
                  sudo gyro \(subcommand)
                """)
        }
    }
}
