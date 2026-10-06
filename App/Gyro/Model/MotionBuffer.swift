import GyroKit
import Synchronization

/// Absorbs ~1,600 readings a second off the main thread and hands the UI one frame at a time.
nonisolated final class MotionBuffer: Sendable {
    struct Frame {
        var snapshot: MotionSnapshot
        /// Gyroscope readings received since the previous frame.
        var sampleCount: Int
        /// The strongest vibration, in g, since the previous frame.
        var vibration: Double
        /// Taps and activity summaries detected since the previous frame, oldest first.
        var events: [MotionEvent]
    }

    /// How many seconds of raw readings to keep, so a capture can include the moments before it began.
    private static let preRollDuration = 2.0
    /// Readings per second from both sensors together, roughly.
    private static let readingsPerSecond = 1_600.0
    /// The longest capture kept, in seconds. Later readings are dropped.
    private static let maximumCaptureDuration = 120.0
    /// Events kept if the UI falls behind.
    private static let maximumPendingEvents = 64

    private struct State {
        var tracker = MotionTracker()
        var vibration = VibrationMeter()
        var detector = MotionEventDetector()
        var sampleCount = 0
        var events: [MotionEvent] = []
        var recent: [MotionSample] = []
        var capture: [MotionSample]?
    }

    private let state = Mutex(State())

    func process(_ sample: MotionSample) {
        state.withLock { state in
            state.tracker.process(sample)
            switch sample.kind {
            case .acceleration: state.vibration.process(acceleration: sample.value)
            case .rotationRate: state.sampleCount += 1
            }

            state.events += state.detector.process(sample)
            if state.events.count > Self.maximumPendingEvents {
                state.events.removeFirst(state.events.count - Self.maximumPendingEvents)
            }

            if let count = state.capture?.count {
                if Double(count) < Self.maximumCaptureDuration * Self.readingsPerSecond {
                    state.capture?.append(sample)
                }
            } else {
                state.recent.append(sample)
                let keep = Int(Self.preRollDuration * Self.readingsPerSecond)
                if state.recent.count > 2 * keep {
                    state.recent.removeFirst(state.recent.count - keep)
                }
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer {
                state.sampleCount = 0
                state.events.removeAll(keepingCapacity: true)
            }
            return Frame(
                snapshot: state.tracker.snapshot,
                sampleCount: state.sampleCount,
                vibration: state.vibration.takePeak(),
                events: state.events
            )
        }
    }

    func resetAttitude() {
        state.withLock { $0.tracker.resetAttitude() }
    }

    /// Starts keeping every raw reading, beginning with the last couple of seconds.
    func startCapture() {
        state.withLock { state in
            let keep = Int(Self.preRollDuration * Self.readingsPerSecond)
            state.capture = Array(state.recent.suffix(keep))
            state.recent.removeAll()
        }
    }

    /// Stops capturing and returns the readings, oldest first.
    func finishCapture() -> [MotionSample] {
        state.withLock { state in
            defer { state.capture = nil }
            return state.capture ?? []
        }
    }

    /// Forgets everything, for example when switching to a different source.
    func reset() {
        state.withLock { $0 = State() }
    }
}
