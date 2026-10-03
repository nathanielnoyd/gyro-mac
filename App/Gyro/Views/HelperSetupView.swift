import SwiftUI

/// Explains why motion needs a helper and walks through installing it.
struct HelperSetupView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gyroscope")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Turn On Motion Sensors")
                    .font(.title2.weight(.semibold))
                Text("macOS only shares the accelerometer and gyroscope with privileged software. Gyro includes a small helper that reads them and passes the data to this app. Nothing leaves your Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
            }
            HelperSetupPrompt()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The buttons for installing the helper, adapted to where the user is in the process.
struct HelperSetupPrompt: View {
    @Environment(HelperInstaller.self) private var helper
    @Environment(SensorModel.self) private var sensors
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors

    var body: some View {
        VStack(spacing: 12) {
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            }
            GlassEffectContainer {
                HStack(spacing: 10) {
                    primaryButton
                    Button("Use Simulated Motion") {
                        motionSource = .simulated
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch helper.state {
        case .awaitingApproval:
            Button("Approve in System Settings", systemImage: "gear") {
                helper.openLoginItemsSettings()
            }
            .buttonStyle(.glassProminent)
        case .notInstalled, .failed, .installed:
            Button("Install Helper", systemImage: "lock.shield") {
                helper.install()
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var message: String? {
        switch (helper.state, sensors.motionStatus) {
        case (.awaitingApproval, _):
            "Turn on Gyro under Login Items › Allow in the Background."
        case (.failed(let reason), _):
            reason
        case (.installed, .failed(let reason)):
            reason
        default:
            nil
        }
    }
}
