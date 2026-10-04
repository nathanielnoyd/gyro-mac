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
    }

    private struct State {
        var tracker = MotionTracker()
        var vibration = VibrationMeter()
        var sampleCount = 0
    }

    private let state = Mutex(State())

    func process(_ sample: MotionSample) {
        state.withLock { state in
            state.tracker.process(sample)
            switch sample.kind {
            case .acceleration: state.vibration.process(acceleration: sample.value)
            case .rotationRate: state.sampleCount += 1
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer { state.sampleCount = 0 }
            return Frame(snapshot: state.tracker.snapshot, sampleCount: state.sampleCount, vibration: state.vibration.takePeak())
        }
    }

    func resetAttitude() {
        state.withLock { $0.tracker.resetAttitude() }
    }

    /// Forgets everything, for example when switching to a different source.
    func reset() {
        state.withLock { $0 = State() }
    }
}
