import Foundation
import GyroKit

/// A motion Gyro watches for, and what to do when it happens.
struct Gesture: Codable, Identifiable, Hashable {
    /// The preset's id for built-in gestures, otherwise a UUID.
    var id: String
    var name: String
    /// An SF Symbol.
    var symbol: String
    /// What to do while recording examples.
    var instructions: String
    /// The built-in gesture this one is, if any.
    var presetID: String?
    var signature: GestureSignature
    /// Recorded performances of the gesture. Once there are some, the signature is fitted to them.
    var examples: [MotionEvent] = []
    var recordings: [GestureRecording] = []
    /// Scales the signature's ranges: below 1 is stricter, above 1 more forgiving.
    var tolerance = 1.0
    var isEnabled = true
    var actions: [GestureAction] = []

    var kind: MotionEvent.Kind { signature.kind }
    var preset: GesturePreset? { presetID.flatMap(GesturePreset.named) }
    var isCustom: Bool { presetID == nil }
    var isTrained: Bool { !examples.isEmpty }

    init(preset: GesturePreset) {
        id = preset.id
        name = preset.name
        symbol = preset.symbol
        instructions = preset.instructions
        presetID = preset.id
        signature = preset.signature
    }

    init(name: String, kind: MotionEvent.Kind, examples: [MotionEvent], signature: GestureSignature) {
        id = UUID().uuidString
        self.name = name
        symbol = kind == .taps ? "hand.tap" : "waveform.path"
        instructions = Self.instructions(for: kind)
        self.signature = signature
        self.examples = examples
    }

    /// Fields added after the first release keep their defaults when an older file lacks them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        instructions = try container.decode(String.self, forKey: .instructions)
        presetID = try container.decodeIfPresent(String.self, forKey: .presetID)
        signature = try container.decode(GestureSignature.self, forKey: .signature)
        examples = try container.decodeIfPresent([MotionEvent].self, forKey: .examples) ?? examples
        recordings = try container.decodeIfPresent([GestureRecording].self, forKey: .recordings) ?? recordings
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance) ?? tolerance
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        actions = try container.decodeIfPresent([GestureAction].self, forKey: .actions) ?? actions
    }

    /// What to do while recording examples of a new gesture.
    static func instructions(for kind: MotionEvent.Kind) -> String {
        kind == .taps
            ? "Perform the gesture, then pause for a moment before the next one."
            : "Keep it up until the recording ends."
    }

    /// How the recognizer sees the gesture.
    var candidate: GestureRecognizer.Candidate {
        GestureRecognizer.Candidate(id: id, signature: signature, tolerance: tolerance)
    }

    /// Refits the signature to the examples, or restores the preset's when there are none.
    mutating func refit() {
        if let fitted = GestureSignature(fitting: examples) {
            signature = fitted
        } else if let preset {
            signature = preset.signature
        }
    }
}

/// Raw readings saved while recording examples, so they can be measured again if the detector changes.
struct GestureRecording: Codable, Hashable {
    /// The file name, inside the recordings folder.
    var file: String
    /// The stretch of the recording, on the sensor clock, that examples come from.
    var examplesFrom: Double
    var examplesUntil: Double
}

extension GestureRecording {
    /// The recording a calibration section was measured from.
    init(_ section: GestureCalibration.Section) {
        self.init(file: section.recording, examplesFrom: section.start, examplesUntil: section.end)
    }
}

/// Something to do when a gesture is recognized.
struct GestureAction: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case sound
        case notification
        case shortcut
        case openURL
        case script

        var id: Self { self }

        var title: String {
            switch self {
            case .sound: "Play Sound"
            case .notification: "Show Notification"
            case .shortcut: "Run Shortcut"
            case .openURL: "Open URL"
            case .script: "Run Shell Script"
            }
        }

        var symbol: String {
            switch self {
            case .sound: "speaker.wave.2"
            case .notification: "bell.badge"
            case .shortcut: "square.2.layers.3d"
            case .openURL: "link"
            case .script: "terminal"
            }
        }

        /// The value a new action starts with.
        var defaultValue: String {
            switch self {
            case .sound: "Tink"
            case .notification, .shortcut: ""
            case .openURL: "https://"
            case .script: "say \"$GYRO_GESTURE\""
            }
        }
    }

    var id = UUID()
    var kind: Kind
    /// The sound's name, the shortcut's name, the URL or the script. Unused for notifications.
    var value: String

    init(kind: Kind) {
        self.kind = kind
        value = kind.defaultValue
    }
}
