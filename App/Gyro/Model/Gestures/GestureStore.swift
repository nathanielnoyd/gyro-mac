import Foundation
import GyroKit
import os

/// Keeps gestures, their recordings and calibrations in ~/Library/Application Support/Gyro.
struct GestureStore {
    let directory: URL

    static let standard = GestureStore(directory: GestureCalibration.directory(home: .homeDirectory))

    var recordingsDirectory: URL { GestureCalibration.recordingsDirectory(in: directory) }
    private var fileURL: URL { directory.appending(path: "Gestures.json") }

    struct Contents: Codable {
        /// The ``MotionEventDetector/version`` the examples were measured with.
        var detectorVersion = MotionEventDetector.version
        var gestures: [Gesture]
        /// Calibrations already applied, by id, so each is only applied once.
        var appliedCalibrations: Set<String>?
    }

    /// The saved gestures, with every built-in one first, in order, then the custom ones.
    func load() -> Contents {
        var saved: [Gesture] = []
        var applied: Set<String> = []
        do {
            let contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: fileURL))
            saved = contents.gestures
            applied = contents.appliedCalibrations ?? []
            if contents.detectorVersion != MotionEventDetector.version {
                saved = saved.map(remeasured)
            }
        } catch CocoaError.fileReadNoSuchFile {
            // Nothing saved yet.
        } catch {
            // Move the file aside so the next save doesn't overwrite the user's gestures.
            let backup = directory.appending(path: "Gestures-unreadable-\(GestureCalibration.stamp(for: .now)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            log.error("Couldn't read saved gestures, moved them to \(backup.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        let presets = GesturePreset.all.map { preset in
            saved.first { $0.presetID == preset.id } ?? Gesture(preset: preset)
        }
        return Contents(gestures: presets + saved.filter(\.isCustom), appliedCalibrations: applied)
    }

    func save(_ contents: Contents) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(contents)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save gestures: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Writes a recording and returns its file name.
    func save(_ recording: MotionRecording, for gesture: String) throws -> String {
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let file = "\(gesture)-\(GestureCalibration.stamp(for: .now)).csv"
        try recording.write(to: recordingsDirectory.appending(path: file))
        return file
    }

    /// Deletes the files of `recordings`, except those `gestures` still use.
    func delete(_ recordings: [GestureRecording], keepingThoseUsedBy gestures: [Gesture]) {
        let inUse = Set(gestures.flatMap(\.recordings).map(\.file))
        for file in Set(recordings.map(\.file)).subtracting(inUse) {
            try? FileManager.default.removeItem(at: recordingsDirectory.appending(path: file))
        }
    }

    /// The gesture with its examples measured again from its recordings, by the current detector.
    func remeasured(_ gesture: Gesture) -> Gesture {
        guard !gesture.recordings.isEmpty else { return gesture }
        var gesture = gesture
        gesture.examples = gesture.recordings.flatMap { recording -> [MotionEvent] in
            guard let raw = try? MotionRecording(contentsOf: recordingsDirectory.appending(path: recording.file)) else { return [] }
            return raw.events().filter {
                GestureCalibration.isExample($0, of: gesture.kind, from: recording.examplesFrom, until: recording.examplesUntil)
            }
        }
        gesture.refit()
        return gesture
    }
}

nonisolated private let log = Logger(subsystem: "io.github.nathanielnoyd.gyro", category: "gestures")
