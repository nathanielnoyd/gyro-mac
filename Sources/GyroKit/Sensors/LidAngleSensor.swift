/// Reads the angle between the display and the keyboard deck.
///
/// Available on MacBooks with a hinge sensor (2019 and later). It does not require root.
public final class LidAngleSensor: Sendable {
    private let device: HIDDevice

    public init() throws(GyroError) {
        device = try SPUSensor.lidAngle.makeDevice()
        try device.open()
    }

    /// The current lid angle in degrees, where 0 is closed.
    public func angle() throws(GyroError) -> Double {
        // Feature report 1: [report ID, angle low byte, angle high byte].
        let report = try device.featureReport(id: 1, length: 3)
        guard report.count >= 3 else { throw .malformedReport(.lidAngle) }
        return Double(UInt16(report[1]) | UInt16(report[2]) << 8)
    }
}
