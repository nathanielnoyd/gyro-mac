import Foundation

/// A three-component vector in the MacBook's sensor frame.
public struct Vector3: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// The unit vector in the same direction, or `.zero` if the magnitude is zero.
    public var normalized: Vector3 {
        let length = magnitude
        return length > 0 ? self / length : .zero
    }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static prefix func - (vector: Vector3) -> Vector3 {
        Vector3(x: -vector.x, y: -vector.y, z: -vector.z)
    }

    public static func * (vector: Vector3, scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    public static func / (vector: Vector3, scalar: Double) -> Vector3 {
        Vector3(x: vector.x / scalar, y: vector.y / scalar, z: vector.z / scalar)
    }

    public static func += (lhs: inout Vector3, rhs: Vector3) {
        lhs = lhs + rhs
    }
}
