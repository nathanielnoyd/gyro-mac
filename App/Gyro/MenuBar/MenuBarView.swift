import SwiftUI

/// A glanceable level and lid angle in the menu bar.
struct MenuBarView: View {
    @Environment(SensorModel.self) private var sensors
    @Environment(GestureModel.self) private var gestures
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var gestures = gestures

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

            if sensors.isMotionLive {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Run gesture actions", isOn: $gestures.runsActions)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if let entry = gestures.log.first(where: { $0.gestureID != nil && $0.phase != .ended }),
                       let gesture = gestures.gesture(entry.gestureID) {
                        Label {
                            Text("\(gesture.name), \(entry.date, format: .relative(presentation: .named))")
                        } icon: {
                            Image(systemName: gesture.symbol)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Gestures") {
                    openWindow(id: "gestures")
                    NSApp.activate()
                }
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
