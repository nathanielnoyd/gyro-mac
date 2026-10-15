import GyroKit
import XPC

/// Streams IMU readings from the privileged helper. Used by the app.
public enum MotionClient {
    /// Why ``samples()`` failed, or why its stream ended.
    public enum Failure: Error, CustomStringConvertible {
        /// The helper started but couldn't read the sensors.
        case helper(String)
        /// The connection to the helper failed or closed.
        case connection(XPCRichError)

        /// The helper's own message, or advice to reinstall the helper if the connection failed.
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

        let session: XPCSession
        do {
            session = try XPCSession(
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
        } catch let error as XPCRichError {
            // launchd has no helper loaded to connect to.
            throw Failure.connection(error)
        }

        continuation.onTermination = { _ in
            session.cancel(reason: "The app stopped reading motion.")
        }
        do {
            try session.send(HelperRequest.startMotion)
        } catch {
            session.cancel(reason: "Couldn't ask the helper for motion.")
            throw (error as? XPCRichError).map(Failure.connection) ?? error
        }
        return stream
    }
}
