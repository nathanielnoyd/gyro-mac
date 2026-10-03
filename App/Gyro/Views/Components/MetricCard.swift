import GyroKit
import SwiftUI

/// A titled card holding one group of readings.
///
/// Cards sit in the content layer, so they use a quiet fill rather than Liquid Glass,
/// which is reserved for controls floating above content.
struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    var unit: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
    }
}

/// x, y and z values with a centered bar for each.
struct VectorReadout: View {
    let vector: Vector3
    /// The magnitude that fills a bar completely.
    let range: Double
    let fractionDigits: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(SensorAxis.allCases) { axis in
                GridRow {
                    Text(axis.rawValue)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(axis.color)
                    CenteredBar(value: vector[axis] / range, color: axis.color)
                    Text(vector[axis].signedFormatted(fractionDigits: fractionDigits))
                        .font(.callout)
                        .monospacedDigit()
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
    }
}

/// A bar that grows left or right from a center mark. `value` runs from -1 to 1.
struct CenteredBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let length = half * min(abs(value), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(length, 0))
                    .offset(x: value < 0 ? half - length : half)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1)
                    .offset(x: half)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
