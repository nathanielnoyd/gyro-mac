import GyroKit
import SwiftUI

/// One gesture: how it's recognized, its recorded examples, and what it does.
struct GestureDetailView: View {
    @Environment(GestureModel.self) private var gestures
    let id: String

    @State private var isConfirmingDelete = false

    var body: some View {
        if let gesture = gestures.gesture(id) {
            Form {
                header(gesture)
                recognition(gesture)
                examples(gesture)
                ActionsSection(gesture: binding(gesture))
            }
            .formStyle(.grouped)
            .navigationTitle(gesture.name)
            .confirmationDialog("Delete “\(gesture.name)”?", isPresented: $isConfirmingDelete) {
                Button("Delete Gesture", role: .destructive) { gestures.delete(id) }
            } message: {
                Text("Its examples and recordings are deleted too.")
            }
        }
    }

    private func binding(_ gesture: Gesture) -> Binding<Gesture> {
        Binding(
            get: { gestures.gesture(id) ?? gesture },
            set: { gestures.update($0) }
        )
    }

    private func header(_ gesture: Gesture) -> some View {
        let gesture = binding(gesture)
        return Section {
            HStack(spacing: 14) {
                GestureIcon(symbol: gesture.wrappedValue.symbol)
                VStack(alignment: .leading, spacing: 3) {
                    if gesture.wrappedValue.isCustom {
                        TextField("Name", text: gesture.name)
                            .textFieldStyle(.plain)
                            .font(.title2.weight(.semibold))
                    } else {
                        Text(gesture.wrappedValue.name)
                            .font(.title2.weight(.semibold))
                    }
                    Text(gesture.wrappedValue.kind == .taps ? "Tap gesture" : "Ongoing gesture")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RecognitionPulse(
                    date: gestures.lastRecognized[id],
                    isOngoing: gestures.activeActivity == id
                )
                Toggle("Enabled", isOn: gesture.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.vertical, 4)
        }
    }

    private func recognition(_ gesture: Gesture) -> some View {
        Section {
            SignatureView(
                signature: gesture.signature,
                tolerance: gesture.tolerance,
                latest: gesture.kind == .taps ? gestures.latestTaps : gestures.latestActivity
            )
            .padding(.vertical, 4)

            LabeledContent("Sensitivity") {
                HStack {
                    Text("Strict").font(.caption).foregroundStyle(.secondary)
                    Slider(value: binding(gesture).tolerance, in: 0.6...2)
                    Text("Forgiving").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320)
            }
        } header: {
            Text("Recognition")
        } footer: {
            Text(
                gesture.kind == .taps
                    ? "Bars show the range each measurement must fall in. The dot is the latest group of taps: green where it fits."
                    : "Bars show the range each measurement must fall in. The dot is the last moment of motion, updated four times a second."
            )
            .foregroundStyle(.secondary)
        }
    }

    private func examples(_ gesture: Gesture) -> some View {
        Section("Examples") {
            LabeledContent("Trained on") {
                if gesture.isTrained {
                    Text(
                        "\(gesture.examples.count) examples from \(gesture.recordings.count) \(gesture.recordings.count == 1 ? "recording" : "recordings")"
                    )
                } else {
                    Text(gesture.isCustom ? "Nothing yet" : "Built-in guesses")
                        .foregroundStyle(.secondary)
                }
            }
            Text(gesture.instructions)
                .foregroundStyle(.secondary)

            HStack {
                Button(gesture.isTrained ? "Record More Examples…" : "Record Examples…", systemImage: "record.circle") {
                    gestures.startRecording(for: id)
                }
                .buttonStyle(.borderedProminent)

                if gesture.isTrained, !gesture.isCustom {
                    Button("Forget Examples") { gestures.clearExamples(of: id) }
                        .help("Go back to the built-in guesses")
                }
                Spacer()
                if gesture.isCustom {
                    Button("Delete Gesture…", role: .destructive) { isConfirmingDelete = true }
                }
            }
        }
    }
}

/// The gesture's actions, each with its own editor.
private struct ActionsSection: View {
    @Environment(GestureModel.self) private var gestures
    @Binding var gesture: Gesture
    @State private var shortcuts: [String] = []

    var body: some View {
        Section {
            if gesture.actions.isEmpty {
                Text("Recognizing this gesture doesn't do anything yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach($gesture.actions) { $action in
                ActionEditor(action: $action, shortcuts: shortcuts) {
                    gesture.actions.removeAll { $0.id == action.id }
                }
            }
            HStack {
                Menu("Add Action", systemImage: "plus") {
                    ForEach(GestureAction.Kind.allCases) { kind in
                        Button(kind.title, systemImage: kind.symbol) {
                            gesture.actions.append(GestureAction(kind: kind))
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Test", systemImage: "play") { gestures.testActions(of: gesture.id) }
                    .disabled(gesture.actions.isEmpty)
            }
        } header: {
            Text("Actions")
        } footer: {
            Text(
                gesture.kind == .taps
                    ? "Run each time the gesture is recognized."
                    : "Run when the motion starts."
            )
            .foregroundStyle(.secondary)
        }
        .task {
            shortcuts = await ActionRunner.shortcuts()
        }
    }
}

private struct ActionEditor: View {
    @Binding var action: GestureAction
    let shortcuts: [String]
    let delete: () -> Void

    var body: some View {
        HStack(alignment: action.kind == .script ? .top : .center) {
            Label(action.kind.title, systemImage: action.kind.symbol)
                .frame(width: 170, alignment: .leading)
            editor
            Button("Remove", systemImage: "minus.circle.fill", action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch action.kind {
        case .sound:
            HStack {
                Picker("Sound", selection: $action.value) {
                    ForEach(ActionRunner.sounds, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Play", systemImage: "speaker.wave.2") { ActionRunner.play(action.value) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        case .notification:
            Text("Shows the gesture's name.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .shortcut:
            if shortcuts.isEmpty {
                TextField("Shortcut name", text: $action.value)
            } else {
                Picker("Shortcut", selection: $action.value) {
                    Text("Choose…").tag("")
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        case .openURL:
            TextField("URL", text: $action.value)
        case .script:
            VStack(alignment: .leading, spacing: 4) {
                TextField("Script", text: $action.value, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...6)
                Text("Runs with zsh. $GYRO_GESTURE, $GYRO_TAPS and $GYRO_STRENGTH_MG describe what happened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
