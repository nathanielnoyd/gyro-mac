import Foundation

/// A built-in gesture, with a starting signature that recording examples can replace.
///
/// The starting signatures are educated guesses about how MacBooks respond. Every desk and
/// every hand is different, so each gesture works best after recording a few examples of it.
public struct GesturePreset: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// An SF Symbol.
    public var symbol: String
    /// What to do while recording examples.
    public var instructions: String
    public var signature: GestureSignature

    public static func named(_ id: String) -> GesturePreset? {
        all.first { $0.id == id }
    }

    // Ranges come from a calibration run on an M5 Pro MacBook Pro on a wooden desk
    // (`gyro calibrate`). Taps on the chassis spin the Mac at 5–11 °/s; knocks on the desk
    // and single keystrokes stay under about 3 °/s. That Mac rocked about a diagonal: taps on
    // the left palm rest tipped it to about (−0.8, −0.6) in rock front–back and left–right,
    // taps on the right to about (+0.9, +0.4).
    //
    // There's no knock-on-the-desk gesture: in practice knocks and taps on the Mac were
    // confused too often to be worth triggering anything.
    public static let all: [GesturePreset] = [
        GesturePreset(
            id: "tap-left",
            name: "Tap Left",
            symbol: "hand.point.left",
            instructions: "Tap the palm rest to the left of the trackpad once, then pause.",
            signature: GestureSignature(kind: .taps, count: 1, ranges: [
                .strength: log10(0.012)...1,
                .spin: log10(3.5)...3,
                .rockX: -1 ... -0.3,
                .rockY: -1 ... -0.1,
            ])
        ),
        GesturePreset(
            id: "tap-right",
            name: "Tap Right",
            symbol: "hand.point.right",
            instructions: "Tap the palm rest to the right of the trackpad once, then pause.",
            signature: GestureSignature(kind: .taps, count: 1, ranges: [
                .strength: log10(0.012)...1,
                .spin: log10(3.5)...3,
                .rockX: 0.3...1,
                .rockY: 0.1...1,
            ])
        ),
        GesturePreset(
            id: "double-tap",
            name: "Double Tap",
            symbol: "hand.tap",
            instructions: "Tap the Mac twice in quick succession, then pause.",
            signature: GestureSignature(kind: .taps, count: 2, ranges: [
                .strength: log10(0.015)...1,
                .spin: log10(2.4)...log10(12),
                .length: log10(0.06)...log10(0.28),
            ])
        ),
        GesturePreset(
            id: "soft-typing",
            name: "Soft Typing",
            symbol: "keyboard",
            instructions: "Type the way you usually do.",
            signature: GestureSignature(kind: .activity, ranges: [
                .impacts: 1.5...20,
                .impactStrength: log10(0.004)...log10(0.028),
                .turning: -2...log10(3),
            ])
        ),
        GesturePreset(
            id: "hard-typing",
            name: "Hard Typing",
            symbol: "hammer",
            instructions: "Type hard, as if the keyboard owes you money.",
            signature: GestureSignature(kind: .activity, ranges: [
                .impacts: 1.5...20,
                .impactStrength: log10(0.028)...log10(0.1),
                .vibration: -4...log10(0.04),
                .turning: -2...log10(5),
            ])
        ),
        GesturePreset(
            id: "desk-shake",
            name: "Shake the Desk",
            symbol: "water.waves",
            instructions: "Shake or wobble the desk the Mac sits on.",
            signature: GestureSignature(kind: .activity, ranges: [
                .vibration: log10(0.025)...1,
                .rumble: 0.6...1,
                .turning: -2...log10(8),
            ])
        ),
        GesturePreset(
            id: "pick-up",
            name: "Pick Up",
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            instructions: "Pick the Mac up and move it around.",
            signature: GestureSignature(kind: .activity, ranges: [
                .turning: log10(25)...3,
            ])
        ),
    ]
}
