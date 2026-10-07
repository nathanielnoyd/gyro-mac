import SwiftUI

/// Gyro's single window: the MacBook on a full-bleed stage, with live readings
/// floating over it in Liquid Glass panels.
struct DashboardView: View {
    @Environment(SensorModel.self) private var sensors
    @Environment(GestureModel.self) private var gestures
    @AppStorage(MotionSource.storageKey) private var motionSource = MotionSource.sensors

    private static let panelWidth: CGFloat = 330

    var body: some View {
        ZStack {
            StageBackground()

            MacBookSceneView(
                orientation: sensors.motion.orientation,
                lidAngle: sensors.lidAngle ?? 110
            )
            .ignoresSafeArea()

            HStack(alignment: .top) {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        if showsMotion {
                            AccelerationPanel(snapshot: sensors.motion, history: sensors.history)
                            RotationPanel(snapshot: sensors.motion, history: sensors.history)
                        } else {
                            SetupPanel()
                        }
                    }
                }
                .frame(width: Self.panelWidth)

                Spacer(minLength: 24)

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        if showsMotion {
                            OrientationPanel(attitude: sensors.motion.attitude, resetYaw: sensors.resetAttitude)
                        }
                        LidPanel(angle: sensors.lidAngle)
                    }
                }
                .frame(width: Self.panelWidth)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(spacing: 14) {
                if showsMotion {
                    GestureToast()
                    VibrationPanel(history: sensors.history, markers: markers)
                }
                HStack(spacing: 12) {
                    StatusCapsule()
                    if showsMotion {
                        GesturesButton()
                    }
                }
            }
            .padding([.horizontal, .bottom], 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(minWidth: 1040, minHeight: 640)
        .environment(\.colorScheme, .dark)
    }

    /// Taps and gestures from the log, to mark on the vibration trace.
    private var markers: [VibrationPanel.Marker] {
        gestures.log.compactMap { entry in
            guard entry.event.kind == .taps || entry.phase == .began else { return nil }
            return VibrationPanel.Marker(id: entry.id, time: entry.event.time, symbol: gestures.gesture(entry.gestureID)?.symbol)
        }
    }

    private var showsMotion: Bool {
        motionSource == .simulated || sensors.isMotionLive
    }
}
