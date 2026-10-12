/// What a gesture looks like to the sensors: the range each feature falls in, and for taps, how many.
///
/// A range that reaches the end of its feature's ``MotionFeature/domain`` is open on that side,
/// so "at least 20 mg" is a range from 20 mg to the top of the strength domain.
public struct GestureSignature: Hashable, Sendable, Codable {
    public var kind: MotionEvent.Kind
    /// How many taps the gesture has. `nil` accepts any number, and is always `nil` for activity.
    public var count: Int?
    public var ranges: [MotionFeature: ClosedRange<Double>]

    public init(kind: MotionEvent.Kind, count: Int? = nil, ranges: [MotionFeature: ClosedRange<Double>]) {
        self.kind = kind
        self.count = count
        self.ranges = ranges
    }

    /// How far `event` sits from the middle of every range: 0 in the middle (or anywhere past an
    /// open end), 1 at an edge. `nil` when the event falls outside.
    ///
    /// - Parameter tolerance: Scales every range around its middle. Above 1 is more forgiving.
    public func distance(to event: MotionEvent, tolerance: Double = 1) -> Double? {
        guard event.kind == kind, count.map({ $0 == event.count }) ?? true else { return nil }
        var sumOfSquares = 0.0
        for (feature, range) in ranges {
            guard let value = event.features[feature] else { return nil }
            let distance = Self.distance(of: value, from: range, in: feature.domain, tolerance: tolerance)
            guard distance <= 1 else { return nil }
            sumOfSquares += distance * distance
        }
        return ranges.isEmpty ? 0 : (sumOfSquares / Double(ranges.count)).squareRoot()
    }

    static func distance(
        of value: Double, from range: ClosedRange<Double>, in domain: ClosedRange<Double>, tolerance: Double
    ) -> Double {
        let middle = (range.lowerBound + range.upperBound) / 2
        let halfWidth = max((range.upperBound - range.lowerBound) / 2 * tolerance, 1e-6)
        if value < middle {
            return range.lowerBound <= domain.lowerBound ? 0 : (middle - value) / halfWidth
        } else {
            return range.upperBound >= domain.upperBound ? 0 : (value - middle) / halfWidth
        }
    }

    /// A signature that accepts every example, with some room to spare.
    ///
    /// Each range spans the examples plus the feature's ``MotionFeature/margin`` and a quarter of
    /// their spread on each side. Features that vary across the whole domain are left out.
    /// Returns `nil` without examples, or if they're of different kinds.
    public init?(fitting examples: [MotionEvent]) {
        guard let kind = examples.first?.kind, examples.allSatisfy({ $0.kind == kind }) else { return nil }

        var ranges: [MotionFeature: ClosedRange<Double>] = [:]
        for feature in MotionFeature.allCases where feature.kind == kind {
            let values = examples.compactMap { $0.features[feature] }
            guard let low = values.min(), let high = values.max() else { continue }
            let room = feature.margin + (high - low) / 4
            let domain = feature.domain
            let range = max(low - room, domain.lowerBound)...min(high + room, domain.upperBound)
            if range != domain {
                ranges[feature] = range
            }
        }

        var count: Int?
        if kind == .taps {
            let counts = Dictionary(grouping: examples, by: \.count)
            // The most common count; on a tie, the smaller one.
            count = counts.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
        }
        self.init(kind: kind, count: count, ranges: ranges)
    }
}
