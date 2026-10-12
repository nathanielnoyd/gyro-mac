import Foundation
import Testing

@testable import GyroKit

struct MotionEventDetectorTests {
    @Test func tapOnLeftRocksLeft() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.tap(strength: 0.05, rock: Vector3(x: -8, y: -6, z: 0))
        mac.rest(1)

        let taps = mac.events().filter { $0.kind == .taps }
        let tap = try #require(taps.only)
        #expect(tap.count == 1)
        // Measured on an M5 Pro: a tap on the left palm rest tips the Mac about a diagonal.
        #expect(try #require(tap[.rockX]) < -0.6)
        #expect(try #require(tap[.rockY]) < -0.4)
        // Sampled at 800 Hz, the ringing's first peak reaches a bit over half the envelope.
        #expect((log10(0.02)...log10(0.05)).contains(try #require(tap[.strength])))
        #expect(abs(try #require(tap[.pushZ]) - 1) < 0.1)
        #expect(Self.presets.bestMatch(for: tap)?.id == "tap-left")
    }

    @Test func tapOnRightRocksRight() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.tap(strength: 0.05, rock: Vector3(x: 9, y: 4, z: 0))
        mac.rest(1)

        let tap = try #require(mac.events().filter { $0.kind == .taps }.only)
        #expect(try #require(tap[.rockX]) > 0.6)
        #expect(try #require(tap[.rockY]) > 0.2)
        #expect(Self.presets.bestMatch(for: tap)?.id == "tap-right")
    }

    @Test func tapsCloseTogetherFormOneGroup() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.tap(strength: 0.05, rock: Vector3(x: 5, y: 3, z: 0), tailDecay: 0.1)
        mac.rest(0.05)
        mac.tap(strength: 0.04, rock: Vector3(x: 5, y: 3, z: 0), tailDecay: 0.1)
        mac.rest(1)

        let tap = try #require(mac.events().filter { $0.kind == .taps }.only)
        #expect(tap.count == 2)
        #expect((log10(0.02)...log10(0.05)).contains(try #require(tap[.strength])))
        #expect(Self.presets.bestMatch(for: tap)?.id == "double-tap")
    }

    /// Knocks on the desk aren't a gesture, and mustn't pass for a double tap on the Mac.
    @Test func knockingOnTheDeskIsNotADoubleTap() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.knock(strength: 0.06)
        mac.knock(strength: 0.06)
        mac.rest(1)

        let knock = try #require(mac.events().filter { $0.kind == .taps }.only)
        #expect(knock.count == 2)
        #expect(try #require(knock[.spin]) < log10(3))
        #expect(Self.presets.bestMatch(for: knock) == nil)
    }

    @Test func toneFollowsRingingFrequency() throws {
        var low = SyntheticMac()
        low.rest(2)
        low.tap(strength: 0.05, rock: .zero, frequency: 60, decay: 0.03, tail: 0)
        low.rest(1)
        var high = SyntheticMac()
        high.rest(2)
        high.tap(strength: 0.05, rock: .zero, frequency: 200, decay: 0.03, tail: 0)
        high.rest(1)

        let lowTone = try #require(low.events().filter { $0.kind == .taps }.only?[.tone])
        let highTone = try #require(high.events().filter { $0.kind == .taps }.only?[.tone])
        #expect(abs(pow(10, lowTone) - 60) < 15)
        #expect(abs(pow(10, highTone) - 200) < 40)
    }

    @Test func tooManyTapsAreNotTaps() {
        var mac = SyntheticMac()
        mac.rest(2)
        for _ in 0..<6 {
            mac.tap(strength: 0.05, rock: .zero)
            mac.rest(0.15)
        }
        mac.rest(1)

        #expect(mac.events().filter { $0.kind == .taps }.isEmpty)
    }

    @Test func tapRightAfterOtherMotionIsIgnored() {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.typing(seconds: 2, strength: 0.03)
        mac.rest(0.15)
        mac.tap(strength: 0.05, rock: Vector3(x: -8, y: -6, z: 0))
        mac.rest(1)

        #expect(mac.events().filter { $0.kind == .taps }.isEmpty)
    }

    @Test func typingIsActivityNotTaps() {
        var soft = SyntheticMac()
        soft.rest(2)
        soft.typing(seconds: 4, strength: 0.012)
        soft.rest(2)
        var hard = SyntheticMac()
        hard.rest(2)
        hard.typing(seconds: 4, strength: 0.05)
        hard.rest(2)

        #expect(soft.events().filter { $0.kind == .taps }.isEmpty)
        #expect(Self.activities(in: soft.events()) == ["+soft-typing", "-soft-typing"])
        #expect(Self.activities(in: hard.events()) == ["+hard-typing", "-hard-typing"])
    }

    @Test func wobblingDeskRumbles() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.advance(3) { t in Vector3(x: 0.05 * sin(2 * .pi * 5 * t), y: 0, z: 0) }
        mac.rest(2)

        let events = mac.events()
        #expect(events.filter { $0.kind == .taps }.isEmpty)
        let loudest = try #require(events.filter { $0.kind == .activity }.max { $0[.vibration]! < $1[.vibration]! })
        #expect(try #require(loudest[.rumble]) > 0.8)
        #expect(Self.activities(in: events) == ["+desk-shake", "-desk-shake"])
    }

    @Test func turningIsPickingUp() {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.advance(2, rotation: { t in Vector3(x: 60 * sin(2 * .pi * t), y: 30 * sin(2 * .pi * 0.7 * t), z: 0) })
        mac.rest(3)

        #expect(Self.activities(in: mac.events()) == ["+pick-up", "-pick-up"])
    }

    @Test func restingMacReportsNothing() {
        var mac = SyntheticMac()
        mac.rest(10)

        let events = mac.events()
        #expect(events.filter { $0.kind == .taps }.isEmpty)
        #expect(Self.activities(in: events).isEmpty)
        #expect(events.count { $0.kind == .activity } > 30)
    }

    @Test func recordingReplaysTheSameEvents() throws {
        var mac = SyntheticMac()
        mac.rest(2)
        mac.tap(strength: 0.05, rock: Vector3(x: -8, y: -6, z: 0))
        mac.rest(1)

        let recording = MotionRecording(samples: mac.samples)
        let reloaded = try MotionRecording(csv: recording.csv)
        let original = recording.events().filter { $0.kind == .taps }
        let replayed = reloaded.events().filter { $0.kind == .taps }
        #expect(replayed.count == original.count)
        #expect(abs(replayed[0][.rockY]! - original[0][.rockY]!) < 0.01)
        #expect(throws: GyroError.invalidRecording(line: 2)) {
            try MotionRecording(csv: "time,sensor,x,y,z\n0.1,q,1,2,3")
        }
    }

    // MARK: - Helpers

    static var presets: GestureRecognizer {
        GestureRecognizer(candidates: GesturePreset.all.map { .init(id: $0.id, signature: $0.signature) })
    }

    /// Activity changes, as "+id" when one begins and "-id" when it ends.
    static func activities(in events: [MotionEvent]) -> [String] {
        var recognizer = presets
        return events.flatMap { recognizer.recognize($0) }.compactMap { recognition in
            switch recognition.phase {
            case .began: "+" + recognition.id
            case .ended: "-" + recognition.id
            case .tapped: nil
            }
        }
    }
}

struct GestureSignatureTests {
    private func event(_ features: [MotionFeature: Double], count: Int = 1) -> MotionEvent {
        MotionEvent(kind: .taps, time: 0, count: count, features: features)
    }

    @Test func openEndsAcceptAnythingBeyondThem() {
        let signature = GestureSignature(kind: .taps, ranges: [.rockY: -1 ... -0.4])
        #expect(signature.distance(to: event([.rockY: -1])) == 0)
        #expect(signature.distance(to: event([.rockY: -0.7])) == 0)
        #expect(signature.distance(to: event([.rockY: -0.45]))! > 0.8)
        #expect(signature.distance(to: event([.rockY: -0.3])) == nil)
        #expect(signature.distance(to: event([.rockY: -0.3]), tolerance: 1.5) != nil)
    }

    @Test func countMustMatch() {
        let signature = GestureSignature(kind: .taps, count: 2, ranges: [:])
        #expect(signature.distance(to: event([:], count: 2)) == 0)
        #expect(signature.distance(to: event([:], count: 1)) == nil)
    }

    @Test func fittingCoversExamplesWithRoom() throws {
        let examples = [
            event([.strength: -1.5, .rockY: -0.9, .pushX: -1]),
            event([.strength: -1.3, .rockY: -0.7, .pushX: 1]),
            event([.strength: -1.4, .rockY: -0.8, .pushX: 0], count: 2),
        ]
        let signature = try #require(GestureSignature(fitting: examples))
        #expect(signature.count == 1)
        for example in examples {
            #expect(
                signature.distance(to: MotionEvent(kind: .taps, time: 0, count: 1, features: example.features)) != nil)
        }
        let strength = try #require(signature.ranges[.strength])
        #expect(strength.lowerBound < -1.5 - 0.2 && strength.upperBound > -1.3 + 0.2)
        // Push x varied across its whole domain, so it doesn't constrain the gesture.
        #expect(signature.ranges[.pushX] == nil)
        #expect(signature.distance(to: event([.strength: -1.4, .rockY: 0.8, .pushX: 0])) == nil)
    }
}

/// Builds IMU readings for a MacBook lying flat, sampled at 800 Hz with a little sensor noise.
struct SyntheticMac {
    var rate = 800.0
    private(set) var samples: [MotionSample] = []
    private var time = 0.0
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Advances for `seconds`, adding `acceleration` (g) and `rotation` (°/s) as functions of time since the start.
    mutating func advance(
        _ seconds: Double,
        acceleration: (Double) -> Vector3 = { _ in .zero },
        rotation: (Double) -> Vector3 = { _ in .zero }
    ) {
        let steps = Int(seconds * rate)
        for step in 0..<steps {
            let local = Double(step) / rate
            let gravity = Vector3(x: 0, y: 0, z: -0.98)
            let a = gravity + acceleration(local) + noise(0.0015)
            let g = Vector3(x: 0.4, y: -0.1, z: 0.06) + rotation(local) + noise(0.08)
            samples.append(MotionSample(kind: .acceleration, value: a, timestamp: time))
            samples.append(MotionSample(kind: .rotationRate, value: g, timestamp: time))
            time += 1 / rate
        }
    }

    mutating func rest(_ seconds: Double) {
        advance(seconds)
    }

    /// A tap that rings the chassis along `push` and briefly tips it at `rock` °/s.
    ///
    /// Like real taps on a MacBook, a sharp burst is followed by a quieter tail
    /// (`tail` times as strong, decaying over `tailDecay` seconds) that rings on for a while.
    mutating func tap(
        strength: Double,
        rock: Vector3,
        push: Vector3 = Vector3(x: 0, y: 0, z: 1),
        frequency: Double = 40,
        decay: Double = 0.015,
        tail: Double = 0.2,
        tailDecay: Double = 0.25
    ) {
        let duration = max(0.08, decay * 6, tail > 0 ? tailDecay * 2 : 0)
        advance(
            duration,
            acceleration: { t in
                let burst = exp(-t / decay) * sin(2 * .pi * frequency * t)
                let ringing = tail * exp(-t / tailDecay) * sin(2 * .pi * frequency * 1.1 * t) * min(t / 0.03, 1)
                return push * (strength * (burst + ringing))
            },
            rotation: { t in rock * (exp(-t / 0.015) * sin(2 * .pi * 40 * t)) }
        )
    }

    /// A knock on the desk beside the Mac: strong, but it barely tips the Mac and rings longer.
    mutating func knock(strength: Double) {
        tap(strength: strength, rock: Vector3(x: 1.2, y: 0.8, z: 0), tailDecay: 0.35)
    }

    /// Keystrokes about seven times a second.
    mutating func typing(seconds: Double, strength: Double) {
        var elapsed = 0.0
        var key = 0
        while elapsed < seconds {
            tap(
                strength: strength * (0.8 + 0.4 * Double(key % 3) / 2), rock: .zero,
                push: Vector3(x: 0.2, y: 0, z: 1).normalized, frequency: 150, decay: 0.005, tail: 0)
            let gap = 0.06 + 0.04 * Double(key % 4)
            rest(gap)
            elapsed += 0.08 + gap
            key += 1
        }
    }

    func events() -> [MotionEvent] {
        MotionRecording(samples: samples).events()
    }

    private mutating func noise(_ amplitude: Double) -> Vector3 {
        Vector3(x: random() * amplitude, y: random() * amplitude, z: random() * amplitude)
    }

    /// A uniform value in −1...1 from a fixed sequence, so tests are repeatable.
    private mutating func random() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(1 << 53) * 2 - 1
    }
}

extension Collection {
    /// The only element, or `nil` if there are none or several.
    var only: Element? {
        count == 1 ? first : nil
    }
}

struct SimulatedGestureTests {
    /// The simulation acts out the built-in gestures, so the app can show them without sensors.
    @Test func simulationPerformsBuiltInGestures() {
        var detector = MotionEventDetector()
        var recognizer = MotionEventDetectorTests.presets
        var recognized: [String] = []
        let rate = 800.0
        for step in 0..<Int(SimulatedMotion.period * rate) {
            let time = Double(step) / rate
            let (acceleration, rotationRate) = SimulatedMotion.reading(at: time)
            let events =
                detector.process(MotionSample(kind: .acceleration, value: acceleration, timestamp: time))
                + detector.process(MotionSample(kind: .rotationRate, value: rotationRate, timestamp: time))
            for event in events {
                for recognition in recognizer.recognize(event) {
                    recognized.append((recognition.phase == .ended ? "-" : "") + recognition.id)
                }
            }
        }
        #expect(recognized == ["tap-left", "tap-right", "double-tap", "hard-typing", "-hard-typing"])
    }
}

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
