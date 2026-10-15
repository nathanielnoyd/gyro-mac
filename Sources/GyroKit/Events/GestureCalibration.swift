import Foundation

/// Examples of several gestures, recorded one after another in a guided session.
///
/// Both the Gyro app and `gyro calibrate` write calibrations to the `Calibrations` folder in
/// ``directory(home:)``, with their raw readings in `Recordings`. The app fits each gesture to
/// the examples in the newest calibration that includes it.
public struct GestureCalibration: Codable, Hashable, Sendable, Identifiable {
    /// One gesture's part of the session.
    public struct Section: Codable, Hashable, Sendable {
        /// The gesture's id: a ``GesturePreset`` id, or a custom gesture's.
        public var gesture: String
        /// The raw recording's file name, in the `Recordings` folder.
        public var recording: String
        /// When the gesture was performed, on the sensor clock.
        public var start: Double
        /// When the performance ended, on the sensor clock.
        public var end: Double
        /// The events that count as examples of the gesture.
        public var examples: [MotionEvent]

        /// Creates a section.
        public init(gesture: String, recording: String, start: Double, end: Double, examples: [MotionEvent]) {
            self.gesture = gesture
            self.recording = recording
            self.start = start
            self.end = end
            self.examples = examples
        }
    }

    /// The session's ``stamp(for:)``, which also names its file.
    public var id: String
    /// When the session was recorded.
    public var date: Date
    /// The ``MotionEventDetector/version`` the examples were measured with.
    public var detectorVersion: Int
    /// One section per gesture, in the order they were recorded.
    public var sections: [Section]

    /// Creates a calibration recorded at `date`, measured with the current detector version.
    public init(date: Date = .now, sections: [Section] = []) {
        self.id = Self.stamp(for: date)
        self.date = date
        self.detectorVersion = MotionEventDetector.version
        self.sections = sections
    }

    /// A file-name-friendly local timestamp, such as 2026-10-06-201645.
    public static func stamp(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0,
            c.second ?? 0)
    }

    // MARK: - Examples

    /// How many times to perform each tap gesture.
    public static let repetitions = 5
    /// How long to record each ongoing gesture, in seconds.
    public static let activityDuration = 8.0

    /// The longest to wait for a tap gesture's repetitions, in seconds.
    public static func tapTimeout(repetitions: Int = repetitions) -> Double {
        Double(repetitions) * 3 + 6
    }

    /// Whether `event` counts as an example of a gesture of `kind` performed from `start` until `end`.
    ///
    /// Activity summaries cover the stretch before them, so the first ones are skipped
    /// until the summary lies entirely inside the performance.
    public static func isExample(
        _ event: MotionEvent, of kind: MotionEvent.Kind, from start: Double, until end: Double = .infinity
    ) -> Bool {
        let settle = kind == .activity ? MotionEventDetector.Configuration().activityWindow : 0
        return event.kind == kind && event.time >= start + settle && event.time <= end
    }

    // MARK: - Checking

    /// For each section, what its examples are recognized as once every calibrated gesture is fitted
    /// to its examples. Gestures without a section keep their signature from `candidates`.
    ///
    /// Activity examples are matched one summary at a time, without the recognizer's onset delay.
    public func check(against candidates: [GestureRecognizer.Candidate]) -> [String: [String?]] {
        var fitted = candidates
        for section in sections {
            guard let signature = GestureSignature(fitting: section.examples) else { continue }
            if let index = fitted.firstIndex(where: { $0.id == section.gesture }) {
                fitted[index].signature = signature
            } else {
                fitted.append(.init(id: section.gesture, signature: signature))
            }
        }
        let recognizer = GestureRecognizer(candidates: fitted)
        var results: [String: [String?]] = [:]
        for section in sections {
            results[section.gesture] = section.examples.map { recognizer.bestMatch(for: $0)?.id }
        }
        return results
    }

    // MARK: - Files

    /// Where Gyro keeps gestures, recordings and calibrations for the user whose home is `home`.
    public static func directory(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Gyro")
    }

    /// The `Calibrations` folder in `directory`, such as the one ``directory(home:)`` returns.
    public static func calibrationsDirectory(in directory: URL) -> URL {
        directory.appending(path: "Calibrations")
    }

    /// The `Recordings` folder in `directory`, where raw readings are saved.
    public static func recordingsDirectory(in directory: URL) -> URL {
        directory.appending(path: "Recordings")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Writes the calibration to the `Calibrations` folder in `directory` and returns its URL.
    @discardableResult
    public func save(in directory: URL) throws -> URL {
        let folder = Self.calibrationsDirectory(in: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(id).json")
        try Self.encoder.encode(self).write(to: url, options: .atomic)
        return url
    }

    /// Every calibration saved in `directory`, oldest first.
    public static func all(in directory: URL) -> [GestureCalibration] {
        let folder = calibrationsDirectory(in: directory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(GestureCalibration.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date < $1.date }
    }
}
