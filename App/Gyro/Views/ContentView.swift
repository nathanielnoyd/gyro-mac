import SwiftUI

struct ContentView: View {
    @Environment(SensorModel.self) private var sensors
    @Environment(HelperInstaller.self) private var helper
    @AppStorage("motionSource") private var motionSource = MotionSource.sensors
    @AppStorage("selectedPane") private var selection = Pane.overview

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: sidebarSelection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                StatusBadge()
                    .padding(12)
            }
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may have just approved the helper in System Settings.
            helper.refresh()
        }
    }

    /// The sidebar works with an optional selection; keep a pane selected at all times.
    private var sidebarSelection: Binding<Pane?> {
        Binding(get: { selection }, set: { selection = $0 ?? selection })
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview:
            OverviewView()
        case .motion:
            requiringMotion { MotionChartsView() }
        case .orientation:
            requiringMotion { OrientationView() }
        case .lid:
            LidView()
        }
    }

    /// Shows `content`, or a way to turn motion on when it isn't available yet.
    @ViewBuilder
    private func requiringMotion(@ViewBuilder _ content: () -> some View) -> some View {
        if motionSource == .sensors && !sensors.isMotionLive {
            HelperSetupView()
        } else {
            content()
        }
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case overview, motion, orientation, lid

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .motion: "Motion"
        case .orientation: "Orientation"
        case .lid: "Lid"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .motion: "waveform.path.ecg"
        case .orientation: "level"
        case .lid: "laptopcomputer"
        }
    }
}
