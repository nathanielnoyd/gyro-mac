import Foundation

/// Estimates orientation by fusing gyroscope and accelerometer readings.
///
/// The gyroscope is integrated to track fast rotation, and gravity measured by
/// the accelerometer slowly pulls the estimate back to correct the gyro's drift.
/// This fixes roll and pitch; yaw has no absolute reference and will drift.
///
/// Based on R. Mahony, T. Hamel, J.-M. Pflimlin, "Nonlinear Complementary
/// Filters on the Special Orthogonal Group", IEEE TAC, 2008.
public struct MahonyFilter: Sendable {
    /// How strongly the accelerometer corrects the estimate. Higher responds
    /// faster but lets more vibration through.
    public var proportionalGain: Double
    /// How quickly the filter learns and removes a constant gyro bias.
    public var integralGain: Double

    public private(set) var orientation: Quaternion = .identity
    private var integralError: Vector3 = .zero

    public init(proportionalGain: Double = 1.0, integralGain: Double = 0.05) {
        self.proportionalGain = proportionalGain
        self.integralGain = integralGain
    }

    public var attitude: Attitude { Attitude(orientation) }

    /// Advances the estimate by one step.
    ///
    /// - Parameters:
    ///   - rotationRate: Angular velocity, in radians per second.
    ///   - acceleration: Specific force in any unit. At rest it points up.
    ///   - dt: Seconds since the previous update.
    public mutating func update(rotationRate: Vector3, acceleration: Vector3, dt: Double) {
        guard dt > 0 else { return }
        var correctedRate = rotationRate

        let measuredUp = acceleration.normalized
        if measuredUp != .zero {
            let error = measuredUp.cross(orientation.up)
            if integralGain > 0 {
                integralError += error * (integralGain * dt)
                correctedRate += integralError
            }
            correctedRate += error * proportionalGain
        }

        orientation = orientation.integrated(rate: correctedRate, dt: dt)
    }

    public mutating func reset() {
        orientation = .identity
        integralError = .zero
    }
}
