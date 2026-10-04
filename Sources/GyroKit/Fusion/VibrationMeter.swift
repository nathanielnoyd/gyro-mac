/// Measures how much the Mac is shaking.
///
/// Vibration is the change in total acceleration from its slowly moving average,
/// so gravity and the accelerometer's small offset don't count. A tap on the desk
/// shows up as a short spike; a laptop at rest reads a few thousandths of a g.
public struct VibrationMeter: Sendable {
    /// The largest vibration, in g, since the last call to ``takePeak()``.
    public private(set) var peak = 0.0

    /// How quickly the resting average follows the readings, per sample.
    /// At about 800 samples a second this averages over roughly half a second.
    private static let smoothing = 0.002

    private var restingMagnitude: Double?

    public init() {}

    public mutating func process(acceleration: Vector3) {
        let magnitude = acceleration.magnitude
        let resting = restingMagnitude.map { $0 + (magnitude - $0) * Self.smoothing } ?? magnitude
        restingMagnitude = resting
        peak = max(peak, abs(magnitude - resting))
    }

    /// Returns the peak since the previous call and starts a new measurement.
    public mutating func takePeak() -> Double {
        defer { peak = 0 }
        return peak
    }
}
