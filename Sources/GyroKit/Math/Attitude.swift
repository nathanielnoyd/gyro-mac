import Foundation

/// Orientation as Tait–Bryan angles, in degrees.
///
/// Uses Core Motion's naming for the sensor frame (x right, y toward the hinge, z up out of the keyboard).
public struct Attitude: Hashable, Sendable, Codable {
    /// Rotation around the x axis. Positive when the hinge side lifts, negative when the front edge lifts.
    public var pitch: Double
    /// Rotation around the y axis. Positive when the left side lifts.
    public var roll: Double
    /// Rotation around the z axis. Without a magnetometer this drifts over time.
    public var yaw: Double

    /// Creates an attitude from angles in degrees.
    public init(pitch: Double, roll: Double, yaw: Double) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
    }

    /// Level, with zero yaw.
    public static let zero = Attitude(pitch: 0, roll: 0, yaw: 0)

    /// The angles for a rotation from the sensor frame to the world. Roll stays within ±90°.
    public init(_ q: Quaternion) {
        let sinRoll = 2 * (q.w * q.y - q.z * q.x)
        self.init(
            pitch: atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)).degrees,
            roll: asin(min(max(sinRoll, -1), 1)).degrees,
            yaw: atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)).degrees
        )
    }
}

extension Double {
    var degrees: Double { self * 180 / .pi }
    var radians: Double { self * .pi / 180 }
}
