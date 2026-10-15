import AppKit
import GyroKit
import Observation

/// Recognizes gestures in the detected motion events, runs their actions and records new examples.
@Observable
final class GestureModel {
    /// A recognized gesture, or a group of taps that matched nothing.
    struct LogEntry: Identifiable {
        let id = UUID()
        var date: Date
        var event: MotionEvent
        /// The gesture recognized, if any.
        var gestureID: String?
        var phase: GestureRecognizer.Recognition.Phase?
    }

    private(set) var gestures: [Gesture]
    private(set) var log: [LogEntry] = []
    /// The ongoing activity gesture, if any.
    private(set) var activeActivity: String?
    /// The most recent group of taps and activity summary, recognized or not.
    private(set) var latestTaps: MotionEvent?
    private(set) var latestActivity: MotionEvent?
    /// When each gesture was last recognized.
    private(set) var lastRecognized: [String: Date] = [:]
    private(set) var session: RecordingSession?
    /// A guided calibration of several gestures, while one is running.
    private(set) var calibration: CalibrationSession?
    /// When the gestures were last calibrated, in the app or with `gyro calibrate`.
    private(set) var lastCalibrated: Date?
    /// Why the last save failed, until the user dismisses it.
    var saveError: String?

    /// Whether recognized gestures run their actions.
    var runsActions: Bool {
        didSet { UserDefaults.standard.set(runsActions, forKey: Self.runsActionsKey) }
    }

    /// Actions only run for real motion, not the simulation.
    var actionsAreLive: Bool {
        runsActions && sensors.source == .sensors
    }

    @ObservationIgnored private let sensors: SensorModel
    @ObservationIgnored private let store: GestureStore
    @ObservationIgnored private var recognizer = GestureRecognizer()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var appliedCalibrations: Set<String>
    /// A save waiting for edits to settle.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    private static let runsActionsKey = "runsGestureActions"
    private static let logLength = 60
    /// How long edits must pause before they're written, so typing doesn't save on every keystroke.
    private static let saveDelay = Duration.milliseconds(500)

    init(sensors: SensorModel, store: GestureStore = .standard) {
        self.sensors = sensors
        self.store = store
        let saved = store.load()
        gestures = saved.gestures
        appliedCalibrations = saved.appliedCalibrations ?? []
        runsActions = UserDefaults.standard.object(forKey: Self.runsActionsKey) as? Bool ?? true
        updateRecognizer()
        importCalibrations()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        }
    }

    isolated deinit {
        flushPendingSave()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func gesture(_ id: String?) -> Gesture? {
        gestures.first { $0.id == id }
    }

    // MARK: - Recognition

    func handle(_ events: [MotionEvent]) {
        for event in events {
            switch event.kind {
            case .taps: latestTaps = event
            case .activity: latestActivity = event
            }

            if let calibration {
                calibration.collect(event)
                continue
            }
            if session != nil {
                collectExample(event)
                continue
            }

            let recognitions = recognizer.recognize(event)
            for recognition in recognitions {
                record(recognition)
            }
            if event.kind == .taps, recognitions.isEmpty {
                append(LogEntry(date: .now, event: event))
            }
        }
    }

    private func record(_ recognition: GestureRecognizer.Recognition) {
        append(LogEntry(date: .now, event: recognition.event, gestureID: recognition.id, phase: recognition.phase))
        switch recognition.phase {
        case .tapped, .began:
            lastRecognized[recognition.id] = .now
            if recognition.phase == .began {
                activeActivity = recognition.id
            }
            if actionsAreLive, let gesture = gesture(recognition.id) {
                ActionRunner.run(gesture, event: recognition.event)
            }
        case .ended:
            if activeActivity == recognition.id {
                activeActivity = nil
            }
        }
    }

    private func append(_ entry: LogEntry) {
        log.insert(entry, at: 0)
        if log.count > Self.logLength {
            log.removeLast(log.count - Self.logLength)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Editing

    /// Applies an edit right away, and saves it once edits pause.
    func update(_ gesture: Gesture) {
        guard let index = gestures.firstIndex(where: { $0.id == gesture.id }) else { return }
        guard gestures[index] != gesture else { return }
        gestures[index] = gesture
        updateRecognizer()
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes edits still waiting to be saved.
    func flushPendingSave() {
        guard pendingSave != nil else { return }
        save()
    }

    /// Forgets a gesture's examples, restoring a built-in gesture's starting signature.
    func clearExamples(of id: String) {
        guard var gesture = gesture(id) else { return }
        let recordings = gesture.recordings
        gesture.examples.removeAll()
        gesture.recordings.removeAll()
        gesture.refit()
        update(gesture)
        // The saved gestures must stop using the recordings before they're deleted.
        flushPendingSave()
        store.delete(recordings, keepingThoseUsedBy: gestures)
    }

    func delete(_ id: String) {
        guard let gesture = gesture(id), gesture.isCustom else { return }
        gestures.removeAll { $0.id == id }
        save()
        store.delete(gesture.recordings, keepingThoseUsedBy: gestures)
    }

    /// Runs a gesture's actions now, as if it had been recognized.
    func testActions(of id: String) {
        guard let gesture = gesture(id) else { return }
        let event =
            gesture.kind == .taps
            ? MotionEvent(
                kind: .taps, time: sensors.motion.timestamp, count: gesture.signature.count ?? 1, features: [:])
            : MotionEvent(kind: .activity, time: sensors.motion.timestamp, features: [:])
        ActionRunner.run(gesture, event: event)
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        updateRecognizer()
        do {
            try store.save(GestureStore.Contents(gestures: gestures, appliedCalibrations: appliedCalibrations))
        } catch {
            saveError =
                "Your changes are kept while Gyro is open, but couldn't be written to disk. \(error.localizedDescription)"
        }
    }

    private func updateRecognizer() {
        recognizer.candidates = gestures.filter(\.isEnabled).map(\.candidate)
        if let activeActivity, recognizer.activeActivity != activeActivity {
            self.activeActivity = nil
        }
    }

    // MARK: - Recording examples

    /// Starts recording more examples of an existing gesture.
    func startRecording(for id: String) {
        guard let gesture = gesture(id) else { return }
        startSession(
            RecordingSession(
                gestureID: id, kind: gesture.kind, name: gesture.name, instructions: gesture.instructions,
                phase: .finished))
    }

    /// Starts recording examples of a new gesture.
    func startRecordingNewGesture(of kind: MotionEvent.Kind) {
        startSession(
            RecordingSession(
                gestureID: nil, kind: kind, name: "", instructions: Gesture.instructions(for: kind), phase: .finished))
    }

    private func startSession(_ session: RecordingSession) {
        cancelRecording()
        var session = session
        sensors.startCapture()

        switch session.kind {
        case .taps:
            session.phase = .recording(until: nil)
            session.start = sensors.motion.timestamp
        case .activity:
            session.phase = .countdown(until: .now + RecordingSession.countdown)
            sessionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(RecordingSession.countdown))
                guard !Task.isCancelled, let self else { return }
                self.session?.start = self.sensors.motion.timestamp
                self.session?.phase = .recording(until: .now + RecordingSession.activityDuration)

                try? await Task.sleep(for: .seconds(RecordingSession.activityDuration))
                guard !Task.isCancelled else { return }
                self.session?.end = self.sensors.motion.timestamp
                self.session?.phase = .finished
            }
        }
        self.session = session
    }

    private func collectExample(_ event: MotionEvent) {
        guard let session, event.kind == session.kind, let start = session.start, session.phase != .finished else {
            return
        }
        if GestureCalibration.isExample(event, of: session.kind, from: start) {
            self.session?.examples.append(event)
        }
    }

    /// Removes the most recent example, for a tap that went wrong.
    func discardLastExample() {
        guard session?.examples.isEmpty == false else { return }
        session?.examples.removeLast()
    }

    func renameSession(_ name: String) {
        session?.name = name
    }

    func cancelRecording() {
        sessionTask?.cancel()
        sessionTask = nil
        if session != nil {
            _ = sensors.finishCapture()
            session = nil
        }
    }

    /// Saves the examples and the raw recording, and fits the gesture to them. Returns the gesture's id.
    @discardableResult
    func saveRecording() -> String? {
        guard let session, session.canSave, let start = session.start else { return nil }
        sessionTask?.cancel()
        sessionTask = nil
        let raw = sensors.finishCapture()
        let end = session.end ?? raw.samples.last?.timestamp ?? sensors.motion.timestamp
        self.session = nil

        var gesture: Gesture
        if let id = session.gestureID, let existing = self.gesture(id) {
            gesture = existing
        } else {
            let signature =
                GestureSignature(fitting: session.examples) ?? GestureSignature(kind: session.kind, ranges: [:])
            gesture = Gesture(
                name: session.name.trimmingCharacters(in: .whitespaces), kind: session.kind, examples: [],
                signature: signature)
            gestures.append(gesture)
        }

        gesture.examples += session.examples
        do {
            let file = try store.save(raw, for: gesture.presetID ?? "custom")
            gesture.recordings.append(GestureRecording(file: file, examplesFrom: start, examplesUntil: end))
        } catch {
            saveError =
                "The examples were saved, but not the raw recording, so they can't be measured again if Gyro's detector changes. \(error.localizedDescription)"
        }
        gesture.refit()
        if let index = gestures.firstIndex(where: { $0.id == gesture.id }) {
            gestures[index] = gesture
        }
        save()
        return gesture.id
    }

    // MARK: - Calibration

    /// Starts a guided calibration of the enabled gestures.
    func startCalibration() {
        cancelRecording()
        calibration = CalibrationSession(gestures: gestures.filter(\.isEnabled), sensors: sensors, store: store)
    }

    /// Ends the guided calibration, applying it if `save` is true.
    func finishCalibration(save: Bool) {
        guard let calibration else { return }
        self.calibration = nil
        let result = calibration.finish()
        guard save, !result.sections.isEmpty else {
            store.delete(result.sections.map(GestureRecording.init), keepingThoseUsedBy: gestures)
            return
        }
        do {
            try result.save(in: store.directory)
        } catch {
            // The gestures are still fitted below; only the calibration's record is lost.
            saveError =
                "The gestures were calibrated, but the calibration's record couldn't be saved. \(error.localizedDescription)"
        }
        apply(result)
    }

    /// Applies calibrations saved by `gyro calibrate` since the last time.
    func importCalibrations() {
        let calibrations = GestureCalibration.all(in: store.directory)
        for calibration in calibrations where !appliedCalibrations.contains(calibration.id) {
            apply(calibration)
        }
        lastCalibrated = calibrations.filter { appliedCalibrations.contains($0.id) }.map(\.date).max()
    }

    /// Replaces each calibrated gesture's examples with the calibration's, and refits it.
    private func apply(_ calibration: GestureCalibration) {
        let previous = gestures.flatMap(\.recordings)
        for section in calibration.sections {
            guard let index = gestures.firstIndex(where: { $0.id == section.gesture }) else { continue }
            gestures[index].examples = section.examples
            gestures[index].recordings = [GestureRecording(section)]
            if calibration.detectorVersion == MotionEventDetector.version {
                gestures[index].refit()
            } else {
                gestures[index] = store.remeasured(gestures[index])
            }
        }
        appliedCalibrations.insert(calibration.id)
        lastCalibrated = max(lastCalibrated ?? calibration.date, calibration.date)
        save()
        store.delete(previous, keepingThoseUsedBy: gestures)
    }
}
