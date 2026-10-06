import Foundation

/// Generates realistic-looking IMU readings, for demos, screenshots and Macs without an IMU.
///
/// The simulation repeats every 24 seconds. The MacBook rocks gently, pitching ±20° and
/// rolling ±10°, then settles on the desk while someone taps its left and right palm rest,
/// double-taps it, knocks on the desk and types, then starts rocking again.
public enum SimulatedMotion {
    public static func samples(rate: Double = 800) -> AsyncStream<MotionSample> {
        AsyncStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let start = clock.now
                var step = 0
                while !Task.isCancelled {
                    let time = Double(step) / rate
                    let (acceleration, rotationRate) = reading(at: time)
                    continuation.yield(MotionSample(kind: .acceleration, value: acceleration, timestamp: time))
                    continuation.yield(MotionSample(kind: .rotationRate, value: rotationRate, timestamp: time))

                    step += 1
                    if step % 16 == 0 {
                        try? await clock.sleep(until: start + .seconds(Double(step) / rate))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static let period = 24.0

    /// Something done to the Mac while it rests, in seconds into each period.
    private enum Touch {
        /// A burst at about 40 Hz, then a quieter tail that rings for a while, as measured on
        /// an M5 Pro MacBook Pro. `rock` tips the Mac, in °/s.
        case tap(strength: Double, rock: Vector3, tailDecay: Double)
        case keystroke(strength: Double)
    }

    private static let touches: [(time: Double, touch: Touch)] = {
        var touches: [(Double, Touch)] = [
            (8.0, .tap(strength: 0.05, rock: Vector3(x: -8, y: -6, z: 0), tailDecay: 0.25)),
            (10.0, .tap(strength: 0.06, rock: Vector3(x: 9, y: 4, z: 0), tailDecay: 0.25)),
            (12.0, .tap(strength: 0.05, rock: Vector3(x: 5, y: 3, z: 0), tailDecay: 0.1)),
            (12.2, .tap(strength: 0.04, rock: Vector3(x: 5, y: 3, z: 0), tailDecay: 0.1)),
            (14.0, .tap(strength: 0.06, rock: Vector3(x: 1.2, y: 0.8, z: 0), tailDecay: 0.35)),
            (14.7, .tap(strength: 0.06, rock: Vector3(x: 1.2, y: 0.8, z: 0), tailDecay: 0.35)),
        ]
        // About three seconds of brisk, heavy-handed typing.
        var time = 16.0
        var key = 0
        while time < 19 {
            touches.append((time, .keystroke(strength: 0.06 + 0.01 * Double(key % 3))))
            time += 0.14 + 0.05 * Double(key % 4)
            key += 1
        }
        return touches
    }()

    static func reading(at time: Double) -> (acceleration: Vector3, rotationRate: Vector3) {
        // Orientation, and its rate of change by a central difference.
        let h = 1e-3
        let (pitch, roll) = tilt(at: time)
        let (pitchAhead, rollAhead) = tilt(at: time + h)
        let (pitchBehind, rollBehind) = tilt(at: time - h)
        var rotationRate = Vector3(x: (pitchAhead - pitchBehind) / (2 * h), y: (rollAhead - rollBehind) / (2 * h), z: 0)

        // Gravity seen by a device pitched around x and rolled around y; Core Motion convention.
        let p = pitch.radians, r = roll.radians
        var acceleration = Vector3(x: sin(r), y: -sin(p) * cos(r), z: -cos(p) * cos(r))

        let local = time.truncatingRemainder(dividingBy: period)
        for (start, touch) in touches where local >= start && local < start + 0.7 {
            let t = local - start
            switch touch {
            case .tap(let strength, let rock, let tailDecay):
                let burst = exp(-t / 0.015) * sin(2 * .pi * 40 * t)
                let ringing = 0.2 * exp(-t / tailDecay) * sin(2 * .pi * 44 * t) * min(t / 0.03, 1)
                acceleration.z += strength * (burst + ringing)
                rotationRate += rock * (exp(-t / 0.015) * sin(2 * .pi * 40 * t))
            case .keystroke(let strength) where t < 0.12:
                acceleration.z += strength * exp(-t / 0.005) * sin(2 * .pi * 150 * t)
            case .keystroke:
                break
            }
        }
        return (acceleration, rotationRate)
    }

    /// Pitch and roll, in degrees: gentle rocking that fades out while the Mac rests on the desk.
    private static func tilt(at time: Double) -> (pitch: Double, roll: Double) {
        let local = time.truncatingRemainder(dividingBy: period)
        let calm: Double = switch local {
        case ..<6: 1
        case ..<7: 1 - smoothStep(local - 6)
        case ..<23: 0
        default: smoothStep(local - 23)
        }
        return (20 * sin(time * 0.9) * calm, 10 * sin(time * 0.6) * calm)
    }

    private static func smoothStep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
