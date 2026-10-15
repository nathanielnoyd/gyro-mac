import Foundation
import Testing

@testable import GyroKit

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
