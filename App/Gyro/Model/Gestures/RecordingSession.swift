import Foundation
import GyroKit

extension GestureModel {
    /// Examples being recorded for a new or existing gesture.
    struct RecordingSession {
        enum Phase: Equatable {
            /// Activity recordings give the user a moment to start.
            case countdown(until: Date)
            case recording(until: Date?)
            case finished
        }

        /// The gesture being trained, or `nil` for a new one.
        var gestureID: String?
        var kind: MotionEvent.Kind
        var name: String
        var instructions: String
        var phase: Phase
        /// When examples started counting, on the sensor clock.
        var start: Double?
        var end: Double?
        var examples: [MotionEvent] = []

        /// Examples needed before the recording can be saved.
        var minimumExamples: Int { kind == .taps ? 3 : 4 }
        /// Taps the user is asked for.
        static let suggestedTaps = GestureCalibration.repetitions + 1
        /// How long activity is recorded, in seconds.
        static let activityDuration = GestureCalibration.activityDuration
        static let countdown: TimeInterval = 3

        var canSave: Bool {
            examples.count >= minimumExamples && !name.trimmingCharacters(in: .whitespaces).isEmpty
                && (kind == .taps || phase == .finished)
        }
    }
}
