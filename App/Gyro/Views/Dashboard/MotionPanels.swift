import GyroKit
import SwiftUI

/// Acceleration on each axis, with its live trace and the total magnitude.
struct AccelerationPanel: View {
    let snapshot: MotionSnapshot
    let history: MotionHistory

    var body: some View {
        GlassPanel(title: "Acceleration", systemImage: "move.3d") {
            Text(snapshot.acceleration.magnitude.formatted(.number.precision(.fractionLength(3))) + " g")
        } content: {
            VectorTraces(
                vector: snapshot.acceleration,
                history: history,
                value: \.acceleration,
                minimumSpan: 0.02,
                format: { $0.signedFormatted(fractionDigits: 3) },
                unit: "g"
            )
        }
    }
}

/// Rotation rate on each axis, with its live trace and whether the Mac is at rest.
struct RotationPanel: View {
    let snapshot: MotionSnapshot
    let history: MotionHistory

    var body: some View {
        GlassPanel(title: "Rotation", systemImage: "rotate.3d") {
            Label(snapshot.isStill ? "At rest" : "Moving", systemImage: snapshot.isStill ? "pause.circle" : "waveform")
                .labelStyle(.titleAndIcon)
        } content: {
            VectorTraces(
                vector: snapshot.rotationRate,
                history: history,
                value: \.rotationRate,
                minimumSpan: 1.5,
                format: { $0.signedFormatted(fractionDigits: 1) },
                unit: "°/s"
            )
        }
    }
}

/// One row per axis: its name, a sparkline and the current value.
private struct VectorTraces: View {
    let vector: Vector3
    let history: MotionHistory
    let value: KeyPath<MotionHistory.Point, Vector3>
    let minimumSpan: Double
    let format: (Double) -> String
    let unit: String

    var body: some View {
        VStack(spacing: 10) {
            ForEach(SensorAxis.allCases) { axis in
                HStack(spacing: 12) {
                    Text(axis.rawValue)
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(axis.color)
                        .frame(width: 12)
                    AxisSparkline(
                        points: history.points,
                        window: history.window,
                        value: value,
                        axis: axis,
                        minimumSpan: minimumSpan
                    )
                    .frame(height: 34)
                    Reading(value: format(vector[axis]), unit: unit, size: 19)
                        .frame(width: 96, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(axis.rawValue) axis")
                .accessibilityValue("\(format(vector[axis])) \(unit)")
            }
        }
    }
}
