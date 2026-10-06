import ArgumentParser
import Foundation
import GyroKit

struct Events: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Recognize taps, typing and other gestures. Requires sudo.",
        discussion: """
            Prints each built-in gesture as it's recognized. With --verbose, also prints
            every tap group the detector finds, recognized or not, and changes in ongoing
            activity, with the features gestures are matched on. That shows what the
            sensors make of whatever you do to the Mac.

            --record saves the raw readings, and --replay plays a recording back
            through the detector without sudo. The Gyro app saves a recording each
            time you record examples of a gesture, in
            ~/Library/Application Support/Gyro/Recordings.

            Example: sudo gyro events --verbose --record taps.csv
            """
    )

    @Flag(name: .shortAndLong, help: "Also print unrecognized taps and activity summaries, with their features.")
    var verbose = false

    @Option(name: .long, help: "Save the raw readings to this CSV file.")
    var record: String?

    @Option(name: .long, help: "Read readings from a recording instead of the sensors.")
    var replay: String?

    func validate() throws {
        if record != nil, replay != nil {
            throw ValidationError("--record and --replay can't be used together.")
        }
    }

    func run() async throws {
        var printer = EventPrinter(verbose: verbose)

        if let replay {
            let recording = try MotionRecording(contentsOf: URL(fileURLWithPath: replay))
            var detector = MotionEventDetector()
            for sample in recording.samples {
                printer.start(at: sample.timestamp)
                for event in detector.process(sample) {
                    printer.handle(event)
                }
            }
            return
        }

        let output = try record.map(RecordingFile.init)
        let samples = try MotionSensor().samples(orExplain: "events")
        // On stderr, so it stays out of piped output.
        let banner = Style.color(Palette.green, "●") + " " + Style.bold("Listening") + Style.dim("  Tap or type. Press Ctrl-C to stop.")
        FileHandle.standardError.write(Data((banner + "\n").utf8))
        var detector = MotionEventDetector()
        for await sample in samples {
            printer.start(at: sample.timestamp)
            output?.write(sample)
            for event in detector.process(sample) {
                printer.handle(event)
            }
        }
    }
}

/// Matches events against the built-in gestures and prints the results.
private struct EventPrinter {
    let verbose: Bool
    private var recognizer = GestureRecognizer(candidates: GesturePreset.all.map {
        GestureRecognizer.Candidate(id: $0.id, signature: $0.signature)
    })
    private var startTime: Double?
    /// The last activity summary printed, to skip repeats while nothing much changes.
    private var lastActivity: MotionEvent?

    init(verbose: Bool) {
        self.verbose = verbose
    }

    /// Sets the time printed as zero, if it isn't set yet.
    mutating func start(at time: Double) {
        startTime = startTime ?? time
    }

    mutating func handle(_ event: MotionEvent) {
        let time = Style.dim(String(format: "%8.2f", event.time - (startTime ?? event.time)))

        let recognitions = recognizer.recognize(event)
        for recognition in recognitions {
            let preset = GesturePreset.named(recognition.id)
            let name = preset?.name ?? recognition.id
            let glyph = String(preset?.glyph ?? "●")
            switch recognition.phase {
            case .tapped:
                let strength = recognition.event[.strength].map(MotionFeature.strength.format) ?? ""
                print("\(time)  \(Style.color(Palette.cyan, glyph)) \(Style.bold(name.padded(to: 16)))\(Style.dim(strength))")
            case .began:
                print("\(time)  \(Style.color(Palette.cyan, glyph)) \(Style.bold(name.padded(to: 16)))\(Style.dim("began"))")
            case .ended:
                print("\(time)  \(Style.dim(glyph + " " + name.padded(to: 16) + "ended"))")
            }
        }

        guard verbose else { return }
        switch event.kind {
        case .taps:
            let label = recognitions.isEmpty ? Style.color(Palette.yellow, "unrecognized") : ""
            print("\(time)  \(Style.dim("╎ taps ×\(event.count)")) \(label)\n            \(Style.dim(event.summary))")
        case .activity:
            if hasChanged(event) {
                print("\(time)  \(Style.dim("∿ activity  " + event.summary))")
                lastActivity = event
            }
        }
    }

    /// Whether the summary differs enough from the last one printed to be worth a line.
    private func hasChanged(_ event: MotionEvent) -> Bool {
        guard let lastActivity else { return true }
        let impactsChanged = abs((event[.impacts] ?? 0) - (lastActivity[.impacts] ?? 0)) >= 1
        let vibrationChanged = abs((event[.vibration] ?? 0) - (lastActivity[.vibration] ?? 0)) >= 0.15
        let turningChanged = abs((event[.turning] ?? 0) - (lastActivity[.turning] ?? 0)) >= 0.2
        return impactsChanged || vibrationChanged || turningChanged
    }
}

/// Appends readings to a CSV file as they arrive, so stopping with Ctrl-C keeps everything so far.
private final class RecordingFile {
    private let handle: FileHandle

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try Data((MotionRecording.csvHeader + "\n").utf8).write(to: url)
        InvokingUser.giveOwnership(of: url)
        handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
    }

    func write(_ sample: MotionSample) {
        handle.write(Data((MotionRecording.csvRow(sample) + "\n").utf8))
    }
}
