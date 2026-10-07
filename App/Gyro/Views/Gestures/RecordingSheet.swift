import GyroKit
import SwiftUI

/// Records examples of a gesture: a few performances of a tap gesture, or a few seconds of ongoing motion.
struct RecordingSheet: View {
    @Environment(GestureModel.self) private var gestures
    @Environment(SensorModel.self) private var sensors
    /// Called after saving, with the gesture's id.
    let onSave: (String?) -> Void

    var body: some View {
        if let session = gestures.session {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title(session))
                        .font(.title2.weight(.semibold))
                    Text(session.instructions)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if session.gestureID == nil {
                    TextField("Name", text: Binding(get: { session.name }, set: { gestures.renameSession($0) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                switch session.kind {
                case .taps:
                    TapProgress(
                        examples: session.examples,
                        target: GestureModel.RecordingSession.suggestedTaps,
                        minimum: session.minimumExamples,
                        discardLast: gestures.discardLastExample
                    )
                case .activity:
                    ActivityProgress(stage: stage(session.phase), count: session.examples.count, duration: GestureModel.RecordingSession.activityDuration)
                }

                LevelMeter(vibration: sensors.history.points.last?.vibration ?? 0)

                if !sensors.isMotionLive {
                    MotionOffWarning()
                }

                HStack {
                    Button("Cancel", role: .cancel) { gestures.cancelRecording() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") { onSave(gestures.saveRecording()) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!session.canSave)
                }
            }
            .padding(28)
            .frame(width: 480)
        }
    }

    private func stage(_ phase: GestureModel.RecordingSession.Phase) -> ActivityProgress.Stage {
        switch phase {
        case .countdown(let until): .countdown(until: until)
        case .recording(let until): .recording(until: until)
        case .finished: .finished
        }
    }

    private func title(_ session: GestureModel.RecordingSession) -> String {
        if session.gestureID != nil { return "Record \(session.name)" }
        return session.kind == .taps ? "New Tap Gesture" : "New Ongoing Gesture"
    }
}

/// Shown while recording if there's no motion to record.
struct MotionOffWarning: View {
    var body: some View {
        Label("Motion sensors are off. Turn them on in the main window.", systemImage: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
            .font(.callout)
    }
}

/// A gesture's symbol on an accent-colored tile.
struct GestureIcon: View {
    let symbol: String
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size / 2, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: size / 4))
    }
}

/// One slot per performance, filling as each is detected.
struct TapProgress: View {
    let examples: [MotionEvent]
    /// Slots shown before any examples arrive.
    let target: Int
    /// Examples needed before saving, or `nil` to just count.
    var minimum: Int?
    var discardLast: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(0..<max(target, examples.count), id: \.self) { index in
                    slot(index < examples.count ? examples[index] : nil)
                }
            }
            .animation(.spring(duration: 0.3), value: examples.count)

            HStack(spacing: 10) {
                Text(status)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !examples.isEmpty, let discardLast {
                    Button("Discard Last", action: discardLast)
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
        }
    }

    private var status: String {
        let count = examples.count
        if let minimum, count < minimum {
            return "\(count) of at least \(minimum)"
        }
        return minimum == nil ? "\(count) of \(target)" : "\(count) recorded"
    }

    private func slot(_ example: MotionEvent?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if let example {
                    Circle().fill(Color.accentColor.gradient)
                    Text(example.count == 1 ? "1" : "×\(example.count)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            .frame(width: 34, height: 34)
            .transition(.scale.combined(with: .opacity))

            Text(example?[.strength].map(MotionFeature.strength.format) ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// A countdown, then a progress bar while ongoing motion is recorded.
struct ActivityProgress: View {
    enum Stage: Equatable {
        case countdown(until: Date)
        case recording(until: Date?)
        case finished
    }

    let stage: Stage
    /// Moments recorded so far.
    let count: Int
    /// Seconds the recording lasts.
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Group {
                switch stage {
                case .countdown(let until):
                    Countdown(until: until, now: context.date)
                case .recording(let until):
                    VStack(spacing: 8) {
                        ProgressView(value: progress(until: until, now: context.date))
                            .frame(maxWidth: 300)
                        Text("Keep going…  \(count) moments so far")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                case .finished:
                    Label("Recorded \(count) moments", systemImage: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }
            .frame(height: 80)
        }
    }

    private func progress(until: Date?, now: Date) -> Double {
        guard let until else { return 0 }
        return min(max(1 - until.timeIntervalSince(now) / duration, 0), 1)
    }
}

/// A big 3, 2, 1.
struct Countdown: View {
    let until: Date
    let now: Date

    var body: some View {
        VStack(spacing: 4) {
            Text("\(max(Int(until.timeIntervalSince(now).rounded(.up)), 1))")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("Get ready")
                .foregroundStyle(.secondary)
        }
    }
}

/// How much the Mac is shaking right now, on a log scale, so it's clear Gyro is listening.
struct LevelMeter: View {
    let vibration: Double
    /// Shaking above this, in g, is more than a Mac at rest.
    private static let threshold = 0.004

    /// The meter spans 0.5 mg to 500 mg.
    private static let range = log10(0.0005)...log10(0.5)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(vibration > Self.threshold ? Color.accentColor : Color.secondary)
                        .frame(width: max(position(vibration) * geometry.size.width, 6))
                        .animation(.easeOut(duration: 0.1), value: vibration)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: 300)
        .accessibilityHidden(true)
    }

    private func position(_ g: Double) -> CGFloat {
        let value = log10(max(g, 1e-6))
        return CGFloat(min(max((value - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound), 0), 1))
    }
}
