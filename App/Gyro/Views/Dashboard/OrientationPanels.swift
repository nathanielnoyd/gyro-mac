import GyroKit
import SwiftUI

/// An artificial horizon beside pitch, roll and yaw.
struct OrientationPanel: View {
    let attitude: Attitude
    let resetYaw: () -> Void

    var body: some View {
        GlassPanel(title: "Orientation", systemImage: "level") {
            Button("Zero Yaw", systemImage: "scope", action: resetYaw)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Make the current heading zero")
        } content: {
            HStack(spacing: 18) {
                AttitudeIndicator(attitude: attitude)
                    .frame(width: 112, height: 112)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Pitch", attitude.pitch)
                    row("Roll", attitude.roll)
                    row("Yaw", attitude.yaw)
                }
            }
        }
    }

    private func row(_ name: String, _ degrees: Double) -> some View {
        GridRow {
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
            Reading(value: degrees.signedFormatted(fractionDigits: 1) + "°", size: 20)
                .gridColumnAlignment(.trailing)
        }
    }
}

/// The hinge angle as a dial and a number.
struct LidPanel: View {
    let angle: Double?

    var body: some View {
        GlassPanel(title: "Lid", systemImage: "laptopcomputer") {
            if let angle {
                Text(LidPosition(angle: angle).description)
            }
        } content: {
            if let angle {
                HStack(alignment: .bottom, spacing: 16) {
                    LidDial(angle: angle)
                        .frame(width: 128, height: 76)
                    Spacer(minLength: 0)
                    Reading(value: angle.formatted(.number.precision(.fractionLength(0))) + "°", size: 40)
                        .contentTransition(.numericText(value: angle))
                        .animation(.snappy, value: angle)
                }
            } else {
                Text("This Mac doesn't report its lid angle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
