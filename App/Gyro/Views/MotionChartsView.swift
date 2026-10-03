import Charts
import GyroKit
import SwiftUI

struct MotionChartsView: View {
    @Environment(SensorModel.self) private var sensors

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MetricCard(title: "Acceleration", systemImage: "move.3d", unit: "g") {
                    AxisChart(history: sensors.history, value: \.acceleration, domain: -1.5...1.5, fractionDigits: 3)
                }
                MetricCard(title: "Rotation Rate", systemImage: "rotate.3d", unit: "°/s") {
                    AxisChart(history: sensors.history, value: \.rotationRate, domain: -120...120, fractionDigits: 1)
                }
            }
            .padding(24)
        }
    }
}

/// A live strip chart of one vector's x, y and z over the last few seconds.
private struct AxisChart: View {
    let history: MotionHistory
    let value: KeyPath<MotionHistory.Point, Vector3>
    /// The y range to show. Readings beyond it widen the chart.
    let domain: ClosedRange<Double>
    let fractionDigits: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            legend
            Chart {
                ForEach(SensorAxis.allCases) { axis in
                    ForEach(history.points) { point in
                        LineMark(
                            x: .value("Seconds", point.time - end),
                            y: .value("Value", point[keyPath: value][axis]),
                            series: .value("Axis", axis.rawValue)
                        )
                        .foregroundStyle(axis.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .chartXScale(domain: -history.duration...0)
            .chartYScale(domain: visibleDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { mark in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = mark.as(Double.self) {
                            Text(seconds == 0 ? "now" : "\(Int(seconds))s")
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Last \(Int(history.duration)) seconds of readings")
        }
    }

    private var end: Double {
        history.points.last?.time ?? 0
    }

    private var latest: Vector3 {
        history.points.last.map { $0[keyPath: value] } ?? .zero
    }

    private var visibleDomain: ClosedRange<Double> {
        let peak = history.points.reduce(0) { peak, point in
            let v = point[keyPath: value]
            return max(peak, abs(v.x), abs(v.y), abs(v.z))
        }
        let limit = max(domain.upperBound, peak * 1.1)
        return -limit...limit
    }

    private var legend: some View {
        HStack(spacing: 18) {
            ForEach(SensorAxis.allCases) { axis in
                HStack(spacing: 6) {
                    Circle()
                        .fill(axis.color)
                        .frame(width: 7, height: 7)
                    Text(axis.rawValue)
                        .foregroundStyle(.secondary)
                    Text(latest[axis].signedFormatted(fractionDigits: fractionDigits))
                        .monospacedDigit()
                }
                .font(.callout)
            }
        }
    }
}
