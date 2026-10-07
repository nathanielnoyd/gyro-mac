import SwiftUI

struct SettingsView: View {
    @Environment(HelperInstaller.self) private var helper
    @AppStorage(MotionSource.storageKey) private var motionSource = MotionSource.sensors

    var body: some View {
        Form {
            Picker("Motion source", selection: $motionSource) {
                ForEach(MotionSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }

            LabeledContent("Helper") {
                HStack {
                    Text(helperStatus)
                        .foregroundStyle(.secondary)
                    switch helper.state {
                    case .installed:
                        Button("Uninstall") {
                            Task { await helper.uninstall() }
                        }
                    case .awaitingApproval:
                        Button("Open Login Items") { helper.openLoginItemsSettings() }
                    case .notInstalled, .failed:
                        Button("Install") { helper.install() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onAppear { helper.refresh() }
    }

    private var helperStatus: String {
        switch helper.state {
        case .installed: "Installed"
        case .awaitingApproval: "Waiting for approval"
        case .notInstalled: "Not installed"
        case .failed(let reason): reason
        }
    }
}
