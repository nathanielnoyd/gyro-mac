import GyroKit

/// The contract between the Gyro app and its privileged helper.
///
/// The helper runs as a launchd daemon because the IMU only reports to root.
/// The app connects to its Mach service, sends ``HelperRequest`` messages and
/// receives ``HelperEvent`` messages in return.
public enum HelperService {
    /// The Mach service the helper listens on. Must match `MachServices` in its launchd plist.
    public static let machServiceName = "io.github.nathanielnoyd.gyro.helper"

    /// The bundle identifier of the app allowed to connect.
    public static let appBundleIdentifier = "io.github.nathanielnoyd.gyro"

    /// The file name of the helper's launchd plist inside `Contents/Library/LaunchDaemons`.
    public static let launchDaemonPlistName = "\(machServiceName).plist"
}

/// A message from the app to the helper.
public enum HelperRequest: Codable, Sendable {
    /// Start streaming IMU readings to this client.
    case startMotion
    /// Stop streaming IMU readings to this client.
    case stopMotion
}

/// A message from the helper to the app.
public enum HelperEvent: Codable, Sendable {
    /// A batch of readings, oldest first.
    case motion([MotionSample])
    /// The helper could not start the sensors.
    case failure(String)
}
