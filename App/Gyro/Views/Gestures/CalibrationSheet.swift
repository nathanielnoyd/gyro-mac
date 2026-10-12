import GyroKit
import SwiftUI

/// Walks through each gesture in turn, recording examples, then shows how well they're told apart.
struct CalibrationSheet: View {
    @Environment(GestureModel.self) private var gestures
    @Environment(SensorModel.self) private var sensors
    let session: CalibrationSession

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding([.horizontal, .top], 24)
                .padding(.bottom, 16)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Calibrate Gestures")
                .font(.title2.weight(.semibold))
            Spacer()
            if !session.steps.isEmpty, session.phase != .intro, session.phase != .summary {
                Text("\(session.index + 1) of \(session.steps.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { gestures.finishCalibration(save: false) }
                .keyboardShortcut(.cancelAction)
            Spacer()
            switch session.phase {
            case .intro:
                Button("Begin") { session.begin() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.selected.isEmpty)
            case .ready:
                Button("Skip") { session.skipStep() }
                Button("Start") { session.startStep() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!sensors.isMotionLive)
            case .recording where session.current?.kind == .taps:
                Button("Done") { session.finishStepEarly() }
                    .disabled(session.examples.isEmpty)
            case .summary:
                Button("Save Calibration") { gestures.finishCalibration(save: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.calibration.sections.isEmpty)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .intro:
            intro
        case .ready:
            if let gesture = session.current {
                ready(gesture)
            }
        case .countdown(let until):
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                VStack(spacing: 18) {
                    if let gesture = session.current {
                        GestureTitle(gesture: gesture)
                    }
                    Countdown(until: until, now: context.date)
                }
            }
        case .recording(let until):
            if let gesture = session.current {
                recording(gesture, until: until)
            }
        case .settling:
            VStack(spacing: 14) {
                Image(systemName: "hand.raised.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Hands off for a moment…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        case .summary:
            summary
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "Put the Mac where you usually use it. Gyro will ask for each gesture in turn: read the instructions, press Start, and perform it when the countdown ends. Between gestures, keep your hands off the Mac and the desk."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(session.available) { gesture in
                    Toggle(isOn: selection(gesture.id)) {
                        Label(gesture.name, systemImage: gesture.symbol)
                    }
                }
            }
            .listStyle(.bordered)
            .frame(maxHeight: .infinity)

            if !sensors.isMotionLive {
                MotionOffWarning()
            }
        }
    }

    private func ready(_ gesture: Gesture) -> some View {
        VStack(spacing: 18) {
            GestureTitle(gesture: gesture)
            Text(gesture.instructions)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                gesture.kind == .taps
                    ? "Do it \(GestureCalibration.repetitions) times, waiting about 2 seconds between each."
                    : "Keep it up for \(Int(GestureCalibration.activityDuration)) seconds, until the bar fills."
            )
            .foregroundStyle(.secondary)
            if !sensors.isMotionLive {
                MotionOffWarning()
            }
        }
    }

    private func recording(_ gesture: Gesture, until: Date?) -> some View {
        VStack(spacing: 22) {
            GestureTitle(gesture: gesture)
            Text("Go!")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            switch gesture.kind {
            case .taps:
                TapProgress(
                    examples: session.examples, target: GestureCalibration.repetitions,
                    discardLast: session.discardLastExample)
            case .activity:
                ActivityProgress(
                    stage: .recording(until: until), count: session.examples.count,
                    duration: GestureCalibration.activityDuration)
            }
            LevelMeter(vibration: sensors.history.points.last?.vibration ?? 0)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.calibration.sections.isEmpty {
                ContentUnavailableView(
                    "Nothing Recorded", systemImage: "hand.raised.slash",
                    description: Text("Every gesture was skipped or no examples were detected."))
            } else {
                Text("Once each gesture is fitted to its examples, they're recognized like this:")
                    .foregroundStyle(.secondary)
                List(session.calibration.sections, id: \.gesture) { section in
                    SummaryRow(
                        gesture: gestures.gesture(section.gesture),
                        examples: section.examples.count,
                        recognizedAs: session.results[section.gesture] ?? [],
                        name: { gestures.gesture($0)?.name ?? "nothing" }
                    )
                }
                .listStyle(.bordered)
                Text("Saving replaces each calibrated gesture's examples.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(session.failures, id: \.self) { failure in
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selection(_ id: String) -> Binding<Bool> {
        Binding(
            get: { session.selected.contains(id) },
            set: { isOn in
                if isOn { session.selected.insert(id) } else { session.selected.remove(id) }
            }
        )
    }
}

private struct GestureTitle: View {
    let gesture: Gesture

    var body: some View {
        VStack(spacing: 8) {
            GestureIcon(symbol: gesture.symbol, size: 60)
            Text(gesture.name)
                .font(.title2.weight(.semibold))
        }
    }
}

/// One gesture in the summary: how many of its examples were recognized as itself, and what else.
private struct SummaryRow: View {
    let gesture: Gesture?
    let examples: Int
    let recognizedAs: [String?]
    let name: (String?) -> String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGood ? .green : .orange)
            Label(gesture?.name ?? "Gesture", systemImage: gesture?.symbol ?? "questionmark")
                .frame(width: 170, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(correct) of \(recognizedAs.count) recognized")
                    .monospacedDigit()
                if !others.isEmpty {
                    Text(others)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var correct: Int {
        recognizedAs.filter { $0 == gesture?.id }.count
    }

    private var isGood: Bool {
        !recognizedAs.isEmpty && correct * 10 >= recognizedAs.count * 8
    }

    /// The other gestures examples were taken for, most often first.
    private var others: String {
        Dictionary(grouping: recognizedAs.filter { $0 != gesture?.id }) { $0 }
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count) as \(name($0.key))" }
            .joined(separator: ", ")
    }
}
