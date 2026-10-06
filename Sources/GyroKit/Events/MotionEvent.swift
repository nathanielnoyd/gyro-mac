import Foundation

/// Something ``MotionEventDetector`` noticed: a few quick taps, or a summary of ongoing motion.
public struct MotionEvent: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// One to a few quick taps or knocks, with quiet before and after.
        case taps
        /// A summary of the last moment of motion, such as typing or a shaking desk. Sent several times a second.
        case activity
    }

    public var kind: Kind
    /// Seconds on the sensor clock: when the first tap began, or when the summarized stretch ended.
    public var time: Double
    /// How many taps the group holds. Zero for activity.
    public var count: Int
    public var features: [MotionFeature: Double]

    public init(kind: Kind, time: Double, count: Int = 0, features: [MotionFeature: Double]) {
        self.kind = kind
        self.time = time
        self.count = count
        self.features = features
    }

    public subscript(feature: MotionFeature) -> Double? {
        features[feature]
    }

    /// A short description of the features, for logs.
    public var summary: String {
        MotionFeature.allCases
            .filter { $0.kind == kind }
            .compactMap { feature in features[feature].map { "\(feature.title.lowercased()) \(feature.format($0))" } }
            .joined(separator: ", ")
    }
}

/// One number describing an event. Gestures are recognized by the ranges these fall in.
///
/// Values that span orders of magnitude, like strength, are stored as base-10 logarithms
/// so that "twice as hard" is the same distance whether the tap was soft or hard.
public enum MotionFeature: String, Hashable, Sendable, Codable, CodingKeyRepresentable, CaseIterable {
    // Taps
    /// The biggest jolt, log₁₀ g.
    case strength
    /// The fastest rotation the jolt caused, log₁₀ °/s.
    case spin
    /// Which way the Mac first tips around its x axis, −1 to 1. Positive means the front edge went down.
    case rockX
    /// Which way the Mac first tips around its y axis, −1 to 1. Negative means the left side went down.
    case rockY
    /// The direction of the first push along x, −1 to 1. Positive is toward the right.
    case pushX
    /// The direction of the first push along y, −1 to 1. Positive is toward the hinge.
    case pushY
    /// The direction of the first push along z, −1 to 1. Positive is up.
    case pushZ
    /// How long the jolt rang, log₁₀ seconds.
    case length
    /// How quickly the jolt rang, log₁₀ Hz.
    case tone

    // Activity
    /// Jolts per second.
    case impacts
    /// The average jolt, log₁₀ g. At the bottom of its range when there were none.
    case impactStrength
    /// The overall shaking, root mean square, log₁₀ g.
    case vibration
    /// The share of the shaking below about 15 Hz, 0 to 1. Typing is crisp; a wobbling desk rumbles.
    case rumble
    /// How much the Mac is turning, root mean square, log₁₀ °/s.
    case turning

    public var kind: MotionEvent.Kind {
        switch self {
        case .strength, .spin, .rockX, .rockY, .pushX, .pushY, .pushZ, .length, .tone: .taps
        case .impacts, .impactStrength, .vibration, .rumble, .turning: .activity
        }
    }

    /// Every value this feature can take. A range reaching one end is open on that side.
    public var domain: ClosedRange<Double> {
        switch self {
        case .strength, .impactStrength: -3...1
        case .spin, .turning: -2...3
        case .rockX, .rockY, .pushX, .pushY, .pushZ: -1...1
        case .length: -3...0
        case .tone: 0...3
        case .impacts: 0...20
        case .vibration: -4...1
        case .rumble: 0...1
        }
    }

    /// How much room to leave around recorded examples, so a gesture isn't too picky.
    public var margin: Double {
        switch self {
        case .strength, .impactStrength, .vibration: 0.2
        case .spin, .turning: 0.3
        case .rockX, .rockY, .pushX, .pushY, .pushZ: 0.35
        case .length, .tone: 0.25
        case .impacts: 1.5
        case .rumble: 0.15
        }
    }

    public var title: String {
        switch self {
        case .strength: "Strength"
        case .spin: "Spin"
        case .rockX: "Rock front–back"
        case .rockY: "Rock left–right"
        case .pushX: "Push x"
        case .pushY: "Push y"
        case .pushZ: "Push z"
        case .length: "Length"
        case .tone: "Tone"
        case .impacts: "Impacts"
        case .impactStrength: "Impact strength"
        case .vibration: "Vibration"
        case .rumble: "Rumble"
        case .turning: "Turning"
        }
    }

    /// The value in everyday units.
    public func format(_ value: Double) -> String {
        switch self {
        case .strength, .impactStrength, .vibration:
            let milliG = pow(10, value) * 1_000
            return "\(milliG.formatted(.number.precision(.significantDigits(1...2)))) mg"
        case .spin, .turning:
            return "\(pow(10, value).formatted(.number.precision(.significantDigits(1...2)))) °/s"
        case .rockX, .rockY, .pushX, .pushY, .pushZ:
            return value.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        case .length:
            return "\((pow(10, value) * 1_000).formatted(.number.precision(.fractionLength(0)))) ms"
        case .tone:
            return "\(pow(10, value).formatted(.number.precision(.fractionLength(0)))) Hz"
        case .impacts:
            return "\(value.formatted(.number.precision(.fractionLength(1)))) /s"
        case .rumble:
            return value.formatted(.percent.precision(.fractionLength(0)))
        }
    }
}
