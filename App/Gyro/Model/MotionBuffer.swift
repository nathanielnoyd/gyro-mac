import GyroKit
import Synchronization

/// Absorbs ~1,600 readings a second off the main thread and hands the UI one frame at a time.
nonisolated final class MotionBuffer: Sendable {
    struct Frame {
        var snapshot: MotionSnapshot
        /// Gyroscope readings received since the previous frame.
        var sampleCount: Int
    }

    private struct State {
        var tracker = MotionTracker()
        var sampleCount = 0
    }

    private let state = Mutex(State())

    func process(_ sample: MotionSample) {
        state.withLock { state in
            state.tracker.process(sample)
            if sample.kind == .rotationRate {
                state.sampleCount += 1
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer { state.sampleCount = 0 }
            return Frame(snapshot: state.tracker.snapshot, sampleCount: state.sampleCount)
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
