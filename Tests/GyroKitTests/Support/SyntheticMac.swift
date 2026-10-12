import Foundation
import Testing

@testable import GyroKit

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
