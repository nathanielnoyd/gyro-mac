import Foundation

/// A three-component vector in the MacBook's sensor frame.
public struct Vector3: Hashable, Sendable, Codable {
    /// The x component. The x axis points to the right, across the keyboard.
    public var x: Double
    /// The y component. The y axis points toward the hinge.
    public var y: Double
    /// The z component. The z axis points up out of the keyboard.
    public var z: Double

    /// Creates a vector.
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// The zero vector.
    public static let zero = Vector3(x: 0, y: 0, z: 0)

    /// The vector's length.
    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// The unit vector in the same direction, or `.zero` if the magnitude is zero.
    public var normalized: Vector3 {
        let length = magnitude
        return length > 0 ? self / length : .zero
    }

    /// The cross product of this vector and `other`.
    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    /// Adds two vectors component by component.
    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    /// Subtracts `rhs` from `lhs` component by component.
    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    /// Negates every component.
    public static prefix func - (vector: Vector3) -> Vector3 {
        Vector3(x: -vector.x, y: -vector.y, z: -vector.z)
    }

    /// Multiplies every component by `scalar`.
    public static func * (vector: Vector3, scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    /// Divides every component by `scalar`.
    public static func / (vector: Vector3, scalar: Double) -> Vector3 {
        Vector3(x: vector.x / scalar, y: vector.y / scalar, z: vector.z / scalar)
    }

    /// Adds `rhs` to `lhs` component by component.
    public static func += (lhs: inout Vector3, rhs: Vector3) {
        lhs = lhs + rhs
    }
}
