import Charts
import GyroKit
import SwiftUI

/// A live strip chart of one axis over the recent history.
///
/// The y range follows the data with a floor of `minimumSpan`, so at rest the
/// sensor's real noise shows as a fine trace, like a seismograph, instead of a flat line.
struct AxisSparkline: View {
    let points: [MotionHistory.Point]
    let window: ClosedRange<Double>
    let value: KeyPath<MotionHistory.Point, Vector3>
    let axis: SensorAxis
    let minimumSpan: Double

    var body: some View {
        let domain = yDomain
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.time),
                yStart: .value("Floor", domain.lowerBound),
                yEnd: .value("Value", point[keyPath: value][axis])
            )
            .foregroundStyle(
                LinearGradient(colors: [axis.color.opacity(0.32), axis.color.opacity(0)], startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", point.time),
                y: .value("Value", point[keyPath: value][axis])
            )
            .foregroundStyle(axis.color)
            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartXScale(domain: window)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map { $0[keyPath: value][axis] }
        guard let low = values.min(), let high = values.max() else {
            return -minimumSpan / 2...minimumSpan / 2
        }
        let center = (low + high) / 2
        let half = max((high - low) / 2 * 1.3, minimumSpan / 2)
        return (center - half)...(center + half)
    }
}
