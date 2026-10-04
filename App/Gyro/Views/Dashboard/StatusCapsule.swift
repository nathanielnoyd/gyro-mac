import SwiftUI

/// A floating capsule at the bottom of the stage: where data comes from, how fast, and whether the Mac is moving.
struct StatusCapsule: View {
    @Environment(SensorModel.self) private var sensors
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.8), radius: 4)
                Text(title)
                    .fontWeight(.semibold)
            }

            if sensors.motionStatus == .streaming {
                divider
                if let rate = sensors.sampleRate {
                    Text("\(rate.formatted(.number.precision(.fractionLength(0)))) Hz")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    divider
                }
                Text(sensors.motion.isStill ? "At rest" : "Moving")
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: sensors.motion.isStill)
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 1, height: 14)
    }

    private var title: String {
        switch sensors.motionStatus {
        case .stopped: "Motion off"
        case .connecting: "Connecting…"
        case .streaming: motionSource == .simulated ? "Simulated" : "Live"
        case .failed: "Motion unavailable"
        }
    }

    private var color: Color {
        switch sensors.motionStatus {
        case .stopped: .secondary
        case .connecting: .yellow
        case .streaming: motionSource == .simulated ? .purple : .green
        case .failed: .red
        }
    }
}
