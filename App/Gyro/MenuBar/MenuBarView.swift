import SwiftUI

/// A glanceable level and lid angle in the menu bar.
struct MenuBarView: View {
    @Environment(SensorModel.self) private var sensors
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            if sensors.isMotionLive {
                AttitudeIndicator(attitude: sensors.motion.attitude)
                    .frame(width: 140, height: 140)
                HStack(spacing: 24) {
                    reading("Pitch", sensors.motion.attitude.pitch.signedFormatted(fractionDigits: 1) + "°")
                    reading("Roll", sensors.motion.attitude.roll.signedFormatted(fractionDigits: 1) + "°")
                    if let lid = sensors.lidAngle {
                        reading("Lid", lid.formatted(.number.precision(.fractionLength(0))) + "°")
                    }
                }
            } else if let lid = sensors.lidAngle {
                reading("Lid", lid.formatted(.number.precision(.fractionLength(0))) + "°")
                Text("Open Gyro to turn on motion sensors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Open Gyro") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func reading(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
