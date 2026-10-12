import GyroKit
import Synchronization

/// Collects IMU readings in the background and hands the render loop one frame at a time.
final class MotionFeed: Sendable {
    struct Frame {
        var snapshot: MotionSnapshot
        /// Gyroscope readings received since the previous frame.
        var sampleCount: Int
        /// Largest change in total acceleration, relative to its recent average, since the previous frame.
        var vibration: Double
        /// Tap groups detected since the previous frame, recognized or not.
        var taps: [MotionEvent]
        /// Built-in gestures recognized since the previous frame.
        var recognitions: [GestureRecognizer.Recognition]
        /// The ongoing gesture, such as typing, if one is happening.
        var activeActivity: String?
    }

    private struct State {
        var tracker = MotionTracker()
        var vibration = VibrationMeter()
        var detector = MotionEventDetector()
        var recognizer = GestureRecognizer(
            candidates: GesturePreset.all.map {
                GestureRecognizer.Candidate(id: $0.id, signature: $0.signature)
            })
        var sampleCount = 0
        var taps: [MotionEvent] = []
        var recognitions: [GestureRecognizer.Recognition] = []
    }

    private let samples: AsyncStream<MotionSample>
    private let state = Mutex(State())

    init(samples: AsyncStream<MotionSample>) {
        self.samples = samples
    }

    convenience init() throws {
        self.init(samples: try MotionSensor().samples())
    }

    func run() async {
        for await sample in samples {
            state.withLock { state in
                state.tracker.process(sample)
                switch sample.kind {
                case .rotationRate:
                    state.sampleCount += 1
                case .acceleration:
                    state.vibration.process(acceleration: sample.value)
                }
                for event in state.detector.process(sample) {
                    if event.kind == .taps {
                        state.taps.append(event)
                    }
                    state.recognitions += state.recognizer.recognize(event)
                }
            }
        }
    }

    func takeFrame() -> Frame {
        state.withLock { state in
            defer {
                state.sampleCount = 0
                state.taps.removeAll()
                state.recognitions.removeAll()
            }
            return Frame(
                snapshot: state.tracker.snapshot,
                sampleCount: state.sampleCount,
                vibration: state.vibration.takePeak(),
                taps: state.taps,
                recognitions: state.recognitions,
                activeActivity: state.recognizer.activeActivity
            )
        }
    }

    func zeroYaw() {
        state.withLock { $0.tracker.resetAttitude() }
    }
}
