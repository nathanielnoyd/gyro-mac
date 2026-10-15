import Foundation
import Testing

@testable import GyroKit

struct GestureCalibrationTests {
    private func tap(_ rockY: Double, count: Int = 1, time: Double = 1) -> MotionEvent {
        MotionEvent(kind: .taps, time: time, count: count, features: [.strength: -1.5, .rockY: rockY])
    }

    @Test func savesAndLoadsInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = GestureCalibration(
            date: Date(timeIntervalSince1970: 1_000),
            sections: [
                .init(gesture: "tap-left", recording: "a.csv", start: 0, end: 5, examples: [tap(-0.6)])
            ])
        let newer = GestureCalibration(date: Date(timeIntervalSince1970: 2_000))
        try newer.save(in: directory)
        try older.save(in: directory)

        let loaded = GestureCalibration.all(in: directory)
        #expect(loaded.map(\.id) == [older.id, newer.id])
        #expect(loaded.first == older)
    }

    @Test func checkFitsEachGestureToItsExamples() {
        let calibration = GestureCalibration(sections: [
            .init(gesture: "left", recording: "r.csv", start: 0, end: 10, examples: [tap(-0.9), tap(-0.7), tap(-0.8)]),
            .init(gesture: "right", recording: "r.csv", start: 10, end: 20, examples: [tap(0.4), tap(0.3), tap(0.5)]),
        ])
        // Before calibrating, both gestures accept anything.
        let candidates = ["left", "right"].map {
            GestureRecognizer.Candidate(id: $0, signature: GestureSignature(kind: .taps, ranges: [:]))
        }
        let results = calibration.check(against: candidates)
        #expect(results["left"] == ["left", "left", "left"])
        #expect(results["right"] == ["right", "right", "right"])
    }

    @Test func activityExamplesWaitForTheWindowToFill() {
        let activity = { (time: Double) in MotionEvent(kind: .activity, time: time, features: [:]) }
        #expect(!GestureCalibration.isExample(activity(10.5), of: .activity, from: 10))
        #expect(GestureCalibration.isExample(activity(11.6), of: .activity, from: 10))
        #expect(GestureCalibration.isExample(tap(0, time: 10.1), of: .taps, from: 10))
        #expect(!GestureCalibration.isExample(tap(0, time: 10.1), of: .activity, from: 10))
    }
}
