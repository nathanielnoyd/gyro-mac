import Foundation

/// A unit quaternion describing the rotation from the sensor frame to the world frame.
public struct Quaternion: Hashable, Sendable, Codable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)

    /// A rotation of `angle` radians around `axis`.
    public init(angle: Double, axis: Vector3) {
        let unit = axis.normalized
        let half = angle / 2
        let s = sin(half)
        self.init(w: cos(half), x: unit.x * s, y: unit.y * s, z: unit.z * s)
    }

    public var normalized: Quaternion {
        let length = (w * w + x * x + y * y + z * z).squareRoot()
        guard length > 0 else { return .identity }
        return Quaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    /// The world's up axis expressed in the sensor frame.
    var up: Vector3 {
        Vector3(
            x: 2 * (x * z - w * y),
            y: 2 * (w * x + y * z),
            z: w * w - x * x - y * y + z * z
        )
    }

    /// Advances the rotation by `rate` (radians per second, sensor frame) over `dt` seconds.
    func integrated(rate: Vector3, dt: Double) -> Quaternion {
        let h = 0.5 * dt
        return Quaternion(
            w: w + (-x * rate.x - y * rate.y - z * rate.z) * h,
            x: x + (w * rate.x + y * rate.z - z * rate.y) * h,
            y: y + (w * rate.y - x * rate.z + z * rate.x) * h,
            z: z + (w * rate.z + x * rate.y - y * rate.x) * h
        ).normalized
    }
}
