import Dispatch
import GyroKit
import Synchronization
import XPC

/// Serves IMU readings to clients over XPC. Runs inside the privileged helper.
public enum MotionServer {
    /// Listens for clients that satisfy `requirement` and never returns.
    public static func run(requirement: XPCPeerRequirement) throws -> Never {
        let listener = try XPCListener(
            service: HelperService.machServiceName,
            requirement: requirement
        ) { request in
            let client = MotionClientConnection()
            let (decision, session) = request.accept(
                incomingMessageHandler: { (request: HelperRequest) -> (any Encodable)? in
                    client.handle(request)
                    return nil
                },
                cancellationHandler: { _ in
                    client.stop()
                }
            )
            client.attach(session)
            return decision
        }

        withExtendedLifetime(listener) {
            dispatchMain()
        }
    }
}

/// One connected app. Streams readings to it in batches while it asks for them.
private final class MotionClientConnection: Sendable {
    /// Readings per message. At about 1,600 readings a second this sends roughly 50 messages a second.
    private static let batchSize = 32

    private struct State {
        var session: XPCSession?
        var stream: Task<Void, Never>?
    }

    private let state = Mutex(State())

    func attach(_ session: XPCSession) {
        state.withLock { $0.session = session }
    }

    func handle(_ request: HelperRequest) {
        switch request {
        case .startMotion: start()
        case .stopMotion: stop()
        }
    }

    func stop() {
        let stream = state.withLock { state in
            defer { state.stream = nil }
            return state.stream
        }
        stream?.cancel()
    }

    private func start() {
        let samples: AsyncStream<MotionSample>
        do {
            samples = try MotionSensor().samples()
        } catch {
            send(.failure(error.description))
            return
        }

        let stream = Task { [weak self] in
            var batch: [MotionSample] = []
            batch.reserveCapacity(Self.batchSize)
            for await sample in samples {
                batch.append(sample)
                if batch.count == Self.batchSize {
                    self?.send(.motion(batch))
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }

        let previous = state.withLock { state in
            defer { state.stream = stream }
            return state.stream
        }
        previous?.cancel()
    }

    private func send(_ event: HelperEvent) {
        let session = state.withLock { $0.session }
        do {
            try session?.send(event)
        } catch {
            // The app went away; its cancellation handler will stop the stream.
        }
    }
}
