import SwiftUI

/// Explains why motion needs a helper and walks through installing it.
struct SetupPanel: View {
    @Environment(HelperInstaller.self) private var helper
    @Environment(SensorModel.self) private var sensors
    @AppStorage(MotionSource.storageKey) private var motionSource = MotionSource.sensors

    var body: some View {
        GlassPanel(title: "Motion Sensors", systemImage: "gyroscope") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Turn on the accelerometer and gyroscope")
                    .font(.title3.weight(.semibold))
                Text("macOS only shares them with privileged software, so Gyro includes a small helper that reads them and passes the data to this app. Nothing leaves your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    primaryButton
                        .buttonStyle(.glassProminent)
                    Button("Use Simulated Motion", systemImage: "wand.and.sparkles") {
                        motionSource = .simulated
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch helper.state {
        case .awaitingApproval:
            Button("Approve in System Settings", systemImage: "gear") {
                helper.openLoginItemsSettings()
            }
        case .installed where sensors.motionStatus == .unreachable && helper.repair < .unloaded:
            Button("Repair Helper", systemImage: "wrench.and.screwdriver") {
                Task { await helper.repairWithAdministratorPrivileges() }
            }
        case .installed:
            // The helper is in place but motion didn't start, so try connecting again.
            Button("Try Again", systemImage: "arrow.clockwise") {
                sensors.startMotion(from: .sensors)
            }
        case .repairing:
            Button("Repairing Helper…", systemImage: "wrench.and.screwdriver") {}
                .disabled(true)
        case .notInstalled, .failed:
            Button("Install Helper", systemImage: "lock.shield") {
                helper.install()
            }
        }
    }

    private var message: String? {
        switch (helper.state, sensors.motionStatus) {
        case (.awaitingApproval, _): "Turn on Gyro under Login Items › Allow in the Background."
        case (.failed(let reason), _): reason
        case (.installed, .failed(let reason)): reason
        case (.installed, .unreachable) where helper.repair < .unloaded:
            "Gyro's helper is installed but won't start. Repairing it asks for an administrator password."
        case (.installed, .unreachable):
            "Gyro's helper still won't start. If restarting your Mac doesn't help, run “sudo sfltool resetbtm” in Terminal, restart and install the helper again. That also asks you to approve other apps' background items again."
        default: nil
        }
    }
}
