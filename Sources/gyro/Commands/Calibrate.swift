import ArgumentParser
import Foundation
import GyroKit
import Synchronization

struct Calibrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Walk through each gesture and record labeled examples. Requires sudo.",
        discussion: """
            Prompts for one gesture at a time and waits for you before recording it.
            Tap gestures record until you've done them --repetitions times; ongoing
            gestures, like typing, record for --duration seconds.

            The calibration is saved where the Gyro app keeps gestures,
            ~/Library/Application Support/Gyro, and the app fits its gestures to it the
            next time it opens or comes to the front. The raw readings go in the
            Recordings folder there; replay them with: gyro events --replay <file> -v

            Example: sudo gyro calibrate --only tap-left tap-right
            """
    )

    @Option(name: .long, help: "Save in this folder instead of the Gyro app's.")
    var directory: String?

    @Option(
        name: .long, parsing: .upToNextOption,
        help: "Only these gestures: \(GesturePreset.all.map(\.id).joined(separator: ", ")).")
    var only: [String] = []

    @Option(name: .shortAndLong, help: "How many times to perform each tap gesture.")
    var repetitions = 5

    @Option(name: .shortAndLong, help: "Seconds to record each ongoing gesture.")
    var duration = 8.0

    func validate() throws {
        let unknown = only.filter { GesturePreset.named($0) == nil }
        guard unknown.isEmpty else {
            throw ValidationError("Unknown gesture: \(unknown.joined(separator: ", ")).")
        }
        guard repetitions > 0, duration > 0 else {
            throw ValidationError("--repetitions and --duration must be positive.")
        }
    }

    func run() async throws {
        let presets = only.isEmpty ? GesturePreset.all : GesturePreset.all.filter { only.contains($0.id) }
        let folder = directory.map { URL(fileURLWithPath: $0) } ?? GestureCalibration.directory(home: InvokingUser.home)
        var calibration = GestureCalibration()
        let recordingName = "calibration-\(calibration.id).csv"
        let recordings = GestureCalibration.recordingsDirectory(in: folder)
        let recordingURL = recordings.appending(path: recordingName)

        let samples = try MotionSensor().samples(orExplain: "calibrate")
        try InvokingUser.createDirectory(recordings)
        let session = try CalibrationSession(recording: recordingURL)
        InvokingUser.giveOwnership(of: recordingURL)
        let reader = Task.detached {
            for await sample in samples {
                session.process(sample)
            }
        }
        defer { reader.cancel() }

        print(Style.bold("Gesture calibration"))
        print(
            """
            Put the Mac where you usually use it. For each gesture you'll get instructions,
            then a countdown. Between gestures, keep your hands off the Mac and desk.
            """)
        try await waitForReturn("Press Return to begin.")
        try await holdStill(session, seconds: 3)

        for (index, preset) in presets.enumerated() {
            print()
            print(Style.bold(Style.cyan("\(index + 1) of \(presets.count) · \(preset.name)")))
            print(preset.instructions)
            let isTaps = preset.signature.kind == .taps
            print(
                Style.dim(
                    isTaps
                        ? "Do it \(repetitions) times, waiting about 2 seconds between each."
                        : "Keep it up for \(Int(duration)) seconds, until it says stop."))
            if preset.id.hasSuffix("typing") {
                print(Style.dim("Type anywhere; what you type here is ignored."))
            }

            guard try await waitForReturn("Press Return when you're ready, or type s and Return to skip.") else {
                print(Style.dim("Skipped."))
                continue
            }
            try await countDown()

            let start = session.begin()
            let events = isTaps ? try await recordTaps(session) : try await recordActivity(session)
            let end = session.end()
            calibration.sections.append(
                .init(gesture: preset.id, recording: recordingName, start: start, end: end, examples: events))

            try await holdStill(session, seconds: 2)
        }

        session.finish()
        guard !calibration.sections.isEmpty else {
            try? FileManager.default.removeItem(at: recordingURL)
            print("Nothing recorded.")
            return
        }
        let saved = try calibration.save(in: folder)
        InvokingUser.giveOwnership(of: saved.deletingLastPathComponent())
        InvokingUser.giveOwnership(of: saved)

        print()
        print(Style.bold("Summary") + Style.dim("  (recognized as, once each gesture is fitted to its examples)"))
        let candidates = GesturePreset.all.map { GestureRecognizer.Candidate(id: $0.id, signature: $0.signature) }
        let results = calibration.check(against: candidates)
        for section in calibration.sections {
            guard let preset = GesturePreset.named(section.gesture) else { continue }
            print(Self.summary(of: preset, events: section.examples, recognizedAs: results[section.gesture] ?? []))
        }
        print()
        print("Saved \(saved.path).")
        if directory == nil {
            print("Gyro uses it the next time the app opens or comes to the front.")
        }
    }

    // MARK: - Steps

    /// Records until `repetitions` tap groups arrive, or a generous timeout passes.
    private func recordTaps(_ session: CalibrationSession) async throws -> [MotionEvent] {
        let timeout = GestureCalibration.tapTimeout(repetitions: repetitions)
        print(Style.bold(Style.green("Go!")) + Style.dim("  (up to \(Int(timeout)) s)"))
        let clock = ContinuousClock()
        let start = clock.now
        var events: [MotionEvent] = []
        var finishedAt: ContinuousClock.Instant?

        while clock.now - start < .seconds(timeout) {
            try await Task.sleep(for: .milliseconds(100))
            for event in session.takeEvents() where event.kind == .taps {
                events.append(event)
                print(
                    "  " + Style.green("●") + " \(events.count)  "
                        + Self.describe(tap: event, recognizer: session.recognizer))
            }
            if events.count >= repetitions {
                // Leave a moment in case the last tap was part of a group.
                let done = finishedAt ?? clock.now
                finishedAt = done
                if clock.now - done > .seconds(1) { break }
            }
        }
        if events.count < repetitions {
            print(Style.yellow("  Heard \(events.count) of \(repetitions)."))
        }
        print(Style.bold("Stop."))
        return events
    }

    /// Records for `duration` seconds, showing a progress bar and the latest summary.
    private func recordActivity(_ session: CalibrationSession) async throws -> [MotionEvent] {
        print(Style.bold(Style.green("Go!")))
        let clock = ContinuousClock()
        let started = clock.now
        let start = session.latestTime
        var events: [MotionEvent] = []
        var latest: MotionEvent?

        while true {
            let elapsed = Self.seconds(clock.now - started)
            for event in session.takeEvents() where event.kind == .activity {
                latest = event
                // Summaries cover the last 1.5 s, so skip the ones that began before "Go".
                if GestureCalibration.isExample(event, of: .activity, from: start) {
                    events.append(event)
                }
            }
            let filled = Int(min(elapsed / duration, 1) * 24)
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 24 - filled)
            let detail =
                latest.map { e in
                    [MotionFeature.impacts, .impactStrength, .vibration, .turning].compactMap { f in
                        e[f].map { "\(f.title.lowercased()) \(f.format($0))" }
                    }.joined(separator: " · ")
                } ?? ""
            print("\r\u{1B}[K  \(bar)  \(Style.dim(detail))", terminator: "")
            fflush(stdout)
            if elapsed >= duration { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        print()
        print(Style.bold("Stop."))
        return events
    }

    private func holdStill(_ session: CalibrationSession, seconds: Double) async throws {
        print(Style.dim("Hands off for a moment…"))
        try await Task.sleep(for: .seconds(seconds))
        _ = session.takeEvents()
    }

    private func countDown() async throws {
        for count in [3, 2, 1] {
            print(Style.bold("\(count)… "), terminator: "")
            fflush(stdout)
            try await Task.sleep(for: .seconds(1))
        }
        print()
    }

    /// Waits for Return. Returns `false` if the user typed s to skip.
    @discardableResult
    private func waitForReturn(_ prompt: String) async throws -> Bool {
        // Drop anything typed during the last gesture, such as typing practice.
        tcflush(STDIN_FILENO, TCIFLUSH)
        print(Style.dim(prompt), terminator: " ")
        fflush(stdout)
        let line = await Task.detached { readLine() }.value
        guard let line else { throw CLIError(description: "Input ended.") }
        return line.trimmingCharacters(in: .whitespaces).lowercased() != "s"
    }

    // MARK: - Reporting

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func name(_ id: String?) -> String {
        id.flatMap { GesturePreset.named($0)?.name } ?? "nothing"
    }

    private static func describe(tap: MotionEvent, recognizer: GestureRecognizer) -> String {
        let count = tap.count == 1 ? "1 tap " : "\(tap.count) taps"
        let strength = tap[.strength].map(MotionFeature.strength.format) ?? ""
        let rock = [MotionFeature.rockX, .rockY].compactMap { f in
            tap[f].map { "\(f == .rockX ? "x" : "y") \(f.format($0))" }
        }.joined(separator: " ")
        let spin = tap[.spin].map(MotionFeature.spin.format) ?? ""
        let match = name(recognizer.bestMatch(for: tap)?.id)
        return "\(count)  \(strength)  spin \(spin)  rock \(rock)  " + Style.dim("→ \(match)")
    }

    private static func summary(of preset: GesturePreset, events: [MotionEvent], recognizedAs: [String?]) -> String {
        let matches = Dictionary(grouping: recognizedAs) { $0 }
            .map { (name($0.key), $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.0) \($0.1)" }
            .joined(separator: ", ")
        let correct = recognizedAs.filter { $0 == preset.id }.count
        let mark = events.isEmpty ? Style.yellow("–") : correct * 2 > events.count ? Style.green("✓") : Style.red("✗")

        let features: [MotionFeature] =
            preset.signature.kind == .taps
            ? [.strength, .spin, .rockX, .rockY, .length]
            : [.impacts, .impactStrength, .vibration, .rumble, .turning]
        let medians = features.compactMap { feature -> String? in
            let values = events.compactMap { $0[feature] }.sorted()
            guard !values.isEmpty else { return nil }
            return "\(feature.title.lowercased()) \(feature.format(values[values.count / 2]))"
        }.joined(separator: ", ")

        return """
            \(mark) \(Style.bold(preset.name.padded(to: 15))) \(events.count) \(preset.signature.kind == .taps ? "groups" : "moments"), recognized as: \(matches.isEmpty ? "–" : matches)
                              \(Style.dim(medians))
            """
    }
}

/// Shared between the reader task, which feeds readings, and the prompts.
private final class CalibrationSession: Sendable {
    private struct State {
        var detector = MotionEventDetector()
        var latestTime = 0.0
        var events: [MotionEvent] = []
        var pending = ""
    }

    let recognizer = GestureRecognizer(candidates: GesturePreset.all.map { .init(id: $0.id, signature: $0.signature) })
    private let state = Mutex(State())
    private let file: FileHandle

    init(recording url: URL) throws {
        try Data((MotionRecording.csvHeader + "\n").utf8).write(to: url)
        file = try FileHandle(forWritingTo: url)
        file.seekToEndOfFile()
    }

    /// The newest reading's time, on the sensor clock.
    var latestTime: Double {
        state.withLock { $0.latestTime }
    }

    func process(_ sample: MotionSample) {
        let chunk: String? = state.withLock { state in
            state.latestTime = sample.timestamp
            state.events += state.detector.process(sample)
            state.pending += MotionRecording.csvRow(sample) + "\n"
            guard state.pending.utf8.count > 64_000 else { return nil }
            defer { state.pending = "" }
            return state.pending
        }
        if let chunk {
            file.write(Data(chunk.utf8))
        }
    }

    /// Starts a gesture: forgets earlier events and returns the time it began.
    func begin() -> Double {
        state.withLock { state in
            state.events.removeAll()
            return state.latestTime
        }
    }

    /// Ends a gesture and returns the time it ended.
    func end() -> Double {
        latestTime
    }

    func takeEvents() -> [MotionEvent] {
        state.withLock { state in
            defer { state.events.removeAll() }
            return state.events
        }
    }

    /// Writes what's left of the recording.
    func finish() {
        let chunk = state.withLock { state in
            defer { state.pending = "" }
            return state.pending
        }
        file.write(Data(chunk.utf8))
        try? file.close()
    }
}
