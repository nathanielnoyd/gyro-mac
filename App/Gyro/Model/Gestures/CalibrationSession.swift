import Foundation
import GyroKit
import Observation

/// Walks through several gestures one at a time, recording examples of each, like `gyro calibrate`.
///
/// Each step shows the gesture's instructions and waits for the user to start. After a countdown,
/// tap gestures record until they've been performed ``GestureCalibration/repetitions`` times;
/// ongoing gestures record for ``GestureCalibration/activityDuration`` seconds. Then the user keeps
/// their hands off for a moment before the next step. At the end, the summary shows how each
/// gesture's examples are recognized once every gesture is fitted to them.
@Observable
final class CalibrationSession {
    enum Phase: Equatable {
        /// Choosing which gestures to calibrate.
        case intro
        /// Showing the current gesture's instructions.
        case ready
        case countdown(until: Date)
        case recording(until: Date?)
        /// Hands off before the next gesture.
        case settling
        case summary
    }

    /// Every gesture that can be calibrated.
    let available: [Gesture]
    /// The ones the user chose.
    var selected: Set<String>

    private(set) var steps: [Gesture] = []
    private(set) var index = 0
    private(set) var phase = Phase.intro
    /// The current step's examples.
    private(set) var examples: [MotionEvent] = []
    /// What each gesture's examples are recognized as, once fitted. Filled in for the summary.
    private(set) var results: [String: [String?]] = [:]
    private(set) var calibration = GestureCalibration()
    /// Steps left out of the calibration because their recording couldn't be saved.
    private(set) var failures: [String] = []

    var current: Gesture? { steps.indices.contains(index) ? steps[index] : nil }

    @ObservationIgnored private let sensors: SensorModel
    @ObservationIgnored private let store: GestureStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var start = 0.0

    private static let countdown = 3.0
    private static let settleTime = 2.0

    init(gestures: [Gesture], sensors: SensorModel, store: GestureStore) {
        available = gestures
        selected = Set(gestures.map(\.id))
        self.sensors = sensors
        self.store = store
    }

    func begin() {
        steps = available.filter { selected.contains($0.id) }
        index = 0
        phase = steps.isEmpty ? .summary : .ready
    }

    /// Counts down, then records the current gesture.
    func startStep() {
        guard phase == .ready, let gesture = current else { return }
        examples = []
        sensors.startCapture()
        phase = .countdown(until: .now + Self.countdown)

        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.countdown))
            guard let self, !Task.isCancelled else { return }
            self.start = self.sensors.motion.timestamp

            switch gesture.kind {
            case .taps:
                self.phase = .recording(until: nil)
                let deadline = Date.now + GestureCalibration.tapTimeout()
                var finishedAt: Date?
                while !Task.isCancelled, Date.now < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                    if self.examples.count >= GestureCalibration.repetitions {
                        // Leave a moment in case the last tap belonged to a group.
                        let done = finishedAt ?? .now
                        finishedAt = done
                        if Date.now.timeIntervalSince(done) > 1 { break }
                    }
                }
            case .activity:
                self.phase = .recording(until: .now + GestureCalibration.activityDuration)
                try? await Task.sleep(for: .seconds(GestureCalibration.activityDuration))
            }
            guard !Task.isCancelled else { return }
            await self.endStep()
        }
    }

    /// Ends the current tap gesture early, with the examples so far.
    func finishStepEarly() {
        guard case .recording = phase else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.endStep() }
    }

    func skipStep() {
        guard phase == .ready else { return }
        advance()
    }

    func discardLastExample() {
        if !examples.isEmpty {
            examples.removeLast()
        }
    }

    func collect(_ event: MotionEvent) {
        guard case .recording = phase, let gesture = current,
              GestureCalibration.isExample(event, of: gesture.kind, from: start)
        else { return }
        examples.append(event)
    }

    private func endStep() async {
        guard let gesture = current else { return }
        let end = sensors.motion.timestamp
        let raw = sensors.finishCapture()
        if !examples.isEmpty {
            do {
                let file = try store.save(raw, for: gesture.presetID ?? "custom")
                calibration.sections.append(.init(gesture: gesture.id, recording: file, start: start, end: end, examples: examples))
            } catch {
                failures.append("\(gesture.name) wasn't calibrated: its recording couldn't be saved. \(error.localizedDescription)")
            }
        }

        phase = .settling
        try? await Task.sleep(for: .seconds(Self.settleTime))
        guard !Task.isCancelled else { return }
        advance()
    }

    private func advance() {
        index += 1
        examples = []
        if index < steps.count {
            phase = .ready
        } else {
            results = calibration.check(against: available.map(\.candidate))
            phase = .summary
        }
    }

    /// Stops whatever is in progress and returns the calibration so far.
    func finish() -> GestureCalibration {
        task?.cancel()
        task = nil
        switch phase {
        case .countdown, .recording: _ = sensors.finishCapture()
        default: break
        }
        return calibration
    }
}
