import GyroKit
import SwiftUI

struct OverviewView: View {
    @Environment(SensorModel.self) private var sensors
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 20, alignment: .top)], spacing: 20) {
                    if showsMotion {
                        MetricCard(title: "Acceleration", systemImage: "move.3d", unit: "g") {
                            VectorReadout(vector: sensors.motion.acceleration, range: 1.5, fractionDigits: 3)
                        }
                        MetricCard(title: "Rotation", systemImage: "rotate.3d", unit: "°/s") {
                            VectorReadout(vector: sensors.motion.rotationRate, range: 200, fractionDigits: 1)
                        }
                        MetricCard(title: "Orientation", systemImage: "level") {
                            AttitudeReadout(attitude: sensors.motion.attitude)
                        }
                    }
                    MetricCard(title: "Lid", systemImage: "laptopcomputer") {
                        LidReadout(angle: sensors.lidAngle)
                    }
                }
            }
            .padding(24)
        }
    }

    private var showsMotion: Bool {
        motionSource == .simulated || sensors.isMotionLive
    }

    private var hero: some View {
        MacBookSceneView(
            orientation: sensors.motion.orientation,
            lidAngle: sensors.lidAngle ?? 110
        )
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .background(.fill.quinary, in: .rect(cornerRadius: 24))
        .overlay(alignment: .bottom) {
            if !showsMotion {
                HelperSetupPrompt()
                    .padding(16)
            }
        }
    }
}

/// Pitch, roll and yaw in a compact grid.
struct AttitudeReadout: View {
    let attitude: Attitude

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            row("Pitch", attitude.pitch)
            row("Roll", attitude.roll)
            row("Yaw", attitude.yaw)
        }
    }

    private func row(_ name: String, _ degrees: Double) -> some View {
        GridRow {
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            CenteredBar(value: degrees / 90, color: .accentColor)
            Text(degrees.signedFormatted(fractionDigits: 1) + "°")
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
        }
    }
}

/// The lid angle as a large number with a progress bar.
struct LidReadout: View {
    let angle: Double?

    var body: some View {
        if let angle {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(angle.formatted(.number.precision(.fractionLength(0))))°")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: angle))
                    Spacer()
                    Text(angle < 1 ? "Closed" : "Open")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(angle, 180), total: 180)
                    .tint(.accentColor)
            }
        } else {
            Text("This Mac has no lid angle sensor.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
