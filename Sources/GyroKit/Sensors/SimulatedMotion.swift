import Foundation

/// Generates realistic-looking IMU readings, for demos, screenshots and Macs without an IMU.
///
/// The simulated MacBook rocks gently, pitching ±20° and rolling ±10°, with a brief tap every few seconds.
public enum SimulatedMotion {
    public static func samples(rate: Double = 800) -> AsyncStream<MotionSample> {
        AsyncStream { continuation in
            let task = Task {
                let clock = ContinuousClock()
                let start = clock.now
                var step = 0
                while !Task.isCancelled {
                    let time = Double(step) / rate
                    let pitch = (20 * sin(time * 0.9)).radians
                    let roll = (10 * sin(time * 0.6)).radians
                    let rotationRate = Vector3(x: 20 * 0.9 * cos(time * 0.9), y: 10 * 0.6 * cos(time * 0.6), z: 0)

                    // Gravity seen by a device pitched around x and rolled around y; Core Motion convention.
                    let gravity = Vector3(x: sin(roll), y: -sin(pitch) * cos(roll), z: -cos(pitch) * cos(roll))
                    let tap = step % 2_400 < 40 ? 0.04 * sin(Double(step)) : 0

                    continuation.yield(MotionSample(kind: .acceleration, value: gravity + Vector3(x: 0, y: 0, z: tap), timestamp: time))
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
}
