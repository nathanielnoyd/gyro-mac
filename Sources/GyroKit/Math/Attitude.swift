import Foundation

/// Orientation as Tait–Bryan angles, in degrees.
public struct Attitude: Hashable, Sendable, Codable {
    /// Rotation around the x axis (the hinge axis).
    public var roll: Double
    /// Rotation around the y axis.
    public var pitch: Double
    /// Rotation around the z axis. Without a magnetometer this drifts over time.
    public var yaw: Double

    public init(roll: Double, pitch: Double, yaw: Double) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }

    public static let zero = Attitude(roll: 0, pitch: 0, yaw: 0)

    public init(_ q: Quaternion) {
        let sinPitch = 2 * (q.w * q.y - q.z * q.x)
        self.init(
            roll: atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)).degrees,
            pitch: asin(min(max(sinPitch, -1), 1)).degrees,
            yaw: atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)).degrees
        )
    }
}

extension Double {
    var degrees: Double { self * 180 / .pi }
    var radians: Double { self * .pi / 180 }
}
