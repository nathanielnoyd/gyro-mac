import GyroKit
import GyroXPC

/// Where motion readings come from.
enum MotionSource: String, CaseIterable, Identifiable {
    /// The real IMU, read by the privileged helper.
    case sensors
    /// Generated readings, for demos and Macs without an IMU.
    case simulated

    /// The user's choice, in `@AppStorage`.
    static let storageKey = "motionSource"

    var id: Self { self }

    var title: String {
        switch self {
        case .sensors: "Built-in Sensors"
        case .simulated: "Simulated"
        }
    }

    nonisolated func samples() throws -> AsyncThrowingStream<MotionSample, any Error> {
        switch self {
        case .sensors:
            return try MotionClient.samples()
        case .simulated:
            let simulated = SimulatedMotion.samples()
            return AsyncThrowingStream { continuation in
                let task = Task {
                    for await sample in simulated {
                        continuation.yield(sample)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}
