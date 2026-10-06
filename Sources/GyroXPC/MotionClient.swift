import GyroKit
import XPC

/// Streams IMU readings from the privileged helper. Used by the app.
public enum MotionClient {
    public enum Failure: Error, CustomStringConvertible {
        /// The helper started but couldn't read the sensors.
        case helper(String)
        /// The connection to the helper failed or closed.
        case connection(XPCRichError)

        public var description: String {
            switch self {
            case .helper(let message): message
            case .connection: "Gyro couldn't reach its helper. Try reinstalling it from Settings."
            }
        }
    }

    /// Connects to the helper and starts the IMU. Readings stop when the stream terminates.
    public static func samples() throws -> AsyncThrowingStream<MotionSample, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: MotionSample.self,
            bufferingPolicy: .bufferingNewest(8_192)
        )

        let session = try XPCSession(
            machService: HelperService.machServiceName,
            incomingMessageHandler: { (event: HelperEvent) -> (any Encodable)? in
                switch event {
                case .motion(let samples):
                    for sample in samples {
                        continuation.yield(sample)
                    }
                case .failure(let message):
                    continuation.finish(throwing: Failure.helper(message))
                }
                return nil
            },
            cancellationHandler: { error in
                continuation.finish(throwing: Failure.connection(error))
            }
        )

        continuation.onTermination = { _ in
            session.cancel(reason: "The app stopped reading motion.")
        }
        do {
            try session.send(HelperRequest.startMotion)
        } catch {
            session.cancel(reason: "Couldn't ask the helper for motion.")
            throw error
        }
        return stream
    }
}
