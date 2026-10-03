import Foundation
import GyroKit

/// Simulated IMU readings for `gyro --demo`, for development and screenshots on any Mac.
enum DemoMotion {
    static func samples(rate: Double = 800) -> AsyncStream<MotionSample> {
        AsyncStream { continuation in
            let task = Task {
                let start = ContinuousClock.now
                var step = 0
                while !Task.isCancelled {
                    let time = Double(step) / rate
                    // Rock gently: ±20° of roll and ±10° of pitch.
                    let roll = 20 * sin(time * 0.9)
                    let pitch = 10 * sin(time * 0.6)
                    let rollRate = 20 * 0.9 * cos(time * 0.9)
                    let pitchRate = 10 * 0.6 * cos(time * 0.6)

                    let r = roll * .pi / 180, p = pitch * .pi / 180
                    let gravity = Vector3(x: sin(p), y: -sin(r) * cos(p), z: -cos(r) * cos(p))
                    let tap = step % 2_400 < 40 ? 0.04 * sin(Double(step)) : 0

                    continuation.yield(MotionSample(kind: .acceleration, value: gravity + Vector3(x: 0, y: 0, z: tap), timestamp: time))
                    continuation.yield(MotionSample(kind: .rotationRate, value: Vector3(x: rollRate, y: pitchRate, z: 0), timestamp: time))

                    step += 1
                    if step % 16 == 0 {
                        try? await Task.sleep(until: start + .seconds(Double(step) / rate))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
