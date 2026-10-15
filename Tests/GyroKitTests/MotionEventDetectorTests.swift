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
