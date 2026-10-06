import GyroKit
import SwiftUI

/// The ranges a gesture's features must fall in, with the latest event plotted against them.
///
/// Each feature gets a track spanning every value it can take. The gesture's range is a bar,
/// its forgiving margin (from the sensitivity setting) a fainter bar, and the most recent
/// event a dot: green when it fits the range, orange when it doesn't.
struct SignatureView: View {
    let signature: GestureSignature
    let tolerance: Double
    let latest: MotionEvent?

    var body: some View {
        VStack(spacing: 10) {
            if signature.kind == .taps {
                countRow
            }
            ForEach(features, id: \.self) { feature in
                FeatureTrack(
                    feature: feature,
                    range: signature.ranges[feature],
                    tolerance: tolerance,
                    value: latest?[feature]
                )
            }
        }
    }

    /// Constrained features first, in their usual order, then the ones that can be anything.
    private var features: [MotionFeature] {
        let all = MotionFeature.allCases.filter { $0.kind == signature.kind }
        return all.filter { signature.ranges[$0] != nil } + all.filter { signature.ranges[$0] == nil }
    }

    private var countRow: some View {
        HStack {
            Text("Taps")
                .frame(width: FeatureTrack.titleWidth, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(1...4, id: \.self) { count in
                    Circle()
                        .fill(signature.count.map { count <= $0 } ?? true ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .overlay {
                            if latest?.count == count {
                                Circle().strokeBorder(latestMatches ? Color.green : .orange, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .frame(width: 16)
                }
            }
            Spacer()
            Text(signature.count.map { $0 == 1 ? "1 tap" : "\($0) taps" } ?? "Any number")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
    }

    private var latestMatches: Bool {
        latest.map { $0.count == signature.count || signature.count == nil } ?? false
    }
}

private struct FeatureTrack: View {
    static let titleWidth: CGFloat = 130

    let feature: MotionFeature
    let range: ClosedRange<Double>?
    let tolerance: Double
    let value: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text(feature.title)
                .foregroundStyle(range == nil ? .secondary : .primary)
                .frame(width: Self.titleWidth, alignment: .leading)
                .help(feature.explanation)
            track
                .frame(height: 14)
            Text(value.map(feature.format) ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feature.title)
        .accessibilityValue(accessibilityValue)
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 4)

                if let range {
                    bar(widened(range), width: width)
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(height: 10)
                    bar(range, width: width)
                        .fill(Color.accentColor)
                        .frame(height: 6)
                }

                if let value {
                    Circle()
                        .fill(fits ? Color.green : .orange)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                        .offset(x: position(value) * width - 6)
                        .animation(.easeOut(duration: 0.25), value: value)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func bar(_ range: ClosedRange<Double>, width: CGFloat) -> RangeShape {
        let start = position(range.lowerBound) * width
        let end = position(range.upperBound) * width
        return RangeShape(start: start, end: max(end, start + 4))
    }

    /// The range as the recognizer sees it, scaled by the tolerance.
    private func widened(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        let middle = (range.lowerBound + range.upperBound) / 2
        let halfWidth = (range.upperBound - range.lowerBound) / 2 * tolerance
        let domain = feature.domain
        let low = range.lowerBound <= domain.lowerBound ? domain.lowerBound : middle - halfWidth
        let high = range.upperBound >= domain.upperBound ? domain.upperBound : middle + halfWidth
        return max(low, domain.lowerBound)...min(high, domain.upperBound)
    }

    private var fits: Bool {
        guard let value else { return false }
        guard let range else { return true }
        return widened(range).contains(value)
    }

    private func position(_ value: Double) -> CGFloat {
        let domain = feature.domain
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return CGFloat(min(max(fraction, 0), 1))
    }

    private var accessibilityValue: String {
        let rangeText = range.map { "range \(feature.format($0.lowerBound)) to \(feature.format($0.upperBound))" } ?? "any value"
        let valueText = value.map { "latest \(feature.format($0))" } ?? "no reading yet"
        return "\(rangeText), \(valueText)"
    }
}

/// A capsule from `start` to `end` points along the track, centered vertically.
nonisolated private struct RangeShape: Shape {
    var start: CGFloat
    var end: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: CGRect(x: start, y: rect.minY, width: end - start, height: rect.height), cornerRadius: rect.height / 2)
    }
}

extension MotionFeature {
    /// What the feature measures, in plain words.
    var explanation: String {
        switch self {
        case .strength: "How hard the strongest tap jolted the Mac."
        case .spin: "How fast the tap made the Mac rotate."
        case .rockX: "Which way the Mac tipped front to back. Positive when the front edge went down."
        case .rockY: "Which way the Mac tipped side to side. Negative when the left side went down."
        case .pushX: "The direction of the first push, left (−) or right (+)."
        case .pushY: "The direction of the first push, toward you (−) or toward the hinge (+)."
        case .pushZ: "The direction of the first push, down (−) or up (+)."
        case .length: "How long the tap kept the chassis ringing."
        case .tone: "How quickly the chassis rang. Hard surfaces ring higher."
        case .impacts: "Jolts per second, like keystrokes."
        case .impactStrength: "How hard the average jolt was."
        case .vibration: "The overall amount of shaking."
        case .rumble: "How much of the shaking is slow, like a wobbling desk, rather than crisp."
        case .turning: "How much the Mac is rotating."
        }
    }
}
