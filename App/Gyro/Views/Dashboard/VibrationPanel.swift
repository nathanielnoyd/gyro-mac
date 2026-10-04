import Charts
import SwiftUI

/// A wide seismograph of how much the Mac is shaking. Tap the desk to see it spike.
struct VibrationPanel: View {
    let history: MotionHistory

    /// The smallest full-scale range, in g, so resting noise stays low on the chart.
    private static let minimumScale = 0.008

    var body: some View {
        GlassPanel(title: "Vibration", systemImage: "waveform.path") {
            Text("peak \(milliG(peak))")
        } content: {
            HStack(alignment: .center, spacing: 18) {
                Chart(history.points) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Vibration", point.vibration)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Self.color.opacity(0.55), Self.color.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Vibration", point.vibration)
                    )
                    .foregroundStyle(Self.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
                .chartXScale(domain: history.window)
                .chartYScale(domain: 0...max(Self.minimumScale, peak * 1.15))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .accessibilityHidden(true)

                Reading(value: milliG(latest), unit: "", size: 26)
                    .frame(width: 92, alignment: .trailing)
                    .accessibilityLabel("Vibration")
                    .accessibilityValue(milliG(latest))
            }
            .frame(height: 64)
        }
    }

    /// The gold of the app icon's rotor.
    private static let color = Color(red: 1.0, green: 0.77, blue: 0.24)

    private var peak: Double {
        history.points.map(\.vibration).max() ?? 0
    }

    private var latest: Double {
        history.points.last?.vibration ?? 0
    }

    private func milliG(_ g: Double) -> String {
        "\((g * 1_000).formatted(.number.precision(.fractionLength(0)))) mg"
    }
}
