import GyroKit
import SwiftUI

struct OrientationView: View {
    @Environment(SensorModel.self) private var sensors

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AttitudeIndicator(attitude: sensors.motion.attitude)
                    .frame(width: 320, height: 320)
                    .padding(.top, 12)

                HStack(spacing: 20) {
                    AngleCard(title: "Pitch", detail: "Front edge up is negative", degrees: sensors.motion.attitude.pitch)
                    AngleCard(title: "Roll", detail: "Left side up is positive", degrees: sensors.motion.attitude.roll)
                    AngleCard(title: "Yaw", detail: "Drifts without a compass", degrees: sensors.motion.attitude.yaw)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button("Zero Yaw", systemImage: "scope") {
                    sensors.resetAttitude()
                }
                .help("Reset the orientation estimate so the current heading becomes zero")
            }
        }
    }
}

private struct AngleCard: View {
    let title: String
    let detail: String
    let degrees: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(degrees.signedFormatted(fractionDigits: 1) + "°")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
    }
}

/// An aircraft-style artificial horizon.
///
/// Lifting the front edge moves the horizon down, and lifting one side tilts it the other way,
/// just as the real horizon would look from the keyboard.
struct AttitudeIndicator: View {
    let attitude: Attitude
    /// Degrees of pitch per indicator radius.
    var pitchRange: Double = 60

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let horizonOffset = -attitude.pitch / pitchRange * radius

            ZStack {
                // The world: sky over ground, moved and tilted opposite to the MacBook.
                VStack(spacing: 0) {
                    Rectangle().fill(Gradient(colors: [.blue.mix(with: .black, by: 0.3), .cyan.opacity(0.8)]))
                    Rectangle().fill(Gradient(colors: [.brown.opacity(0.9), .brown.mix(with: .black, by: 0.5)]))
                }
                .overlay {
                    Rectangle()
                        .fill(.white)
                        .frame(height: 1.5)
                }
                .overlay { pitchLadder(radius: radius) }
                .frame(width: size * 3, height: size * 3)
                .offset(y: horizonOffset)
                .rotationEffect(.degrees(-attitude.roll))

                reticle(width: size * 0.5)
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel("Artificial horizon")
        .accessibilityValue("Pitch \(Int(attitude.pitch)) degrees, roll \(Int(attitude.roll)) degrees")
    }

    private func pitchLadder(radius: Double) -> some View {
        ForEach([-40, -30, -20, -10, 10, 20, 30, 40], id: \.self) { degrees in
            Rectangle()
                .fill(.white.opacity(0.7))
                .frame(width: degrees.isMultiple(of: 20) ? 60 : 30, height: 1)
                .offset(y: Double(degrees) / pitchRange * radius)
        }
    }

    private func reticle(width: Double) -> some View {
        HStack(spacing: 0) {
            Capsule().frame(width: width * 0.35, height: 3)
            Spacer()
            Circle().frame(width: 7, height: 7)
            Spacer()
            Capsule().frame(width: width * 0.35, height: 3)
        }
        .frame(width: width)
        .foregroundStyle(.yellow)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }
}
