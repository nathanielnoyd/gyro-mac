import Dispatch
import Foundation
import GyroKit
import os
import Synchronization
import XPC

/// Serves IMU readings to clients over XPC. Runs inside the privileged helper.
public enum MotionServer {
    /// Listens for clients that satisfy `requirement` and never returns.
    ///
    /// The helper exits once it has had no clients for `idleTimeout`. launchd starts
    /// it again the next time the app connects, so a root process isn't left running.
    public static func run(requirement: XPCPeerRequirement, idleTimeout: Duration = .seconds(30)) throws -> Never {
        let clients = ClientRegistry(idleTimeout: idleTimeout)

        let listener = try XPCListener(
            service: HelperService.machServiceName,
            requirement: requirement
        ) { request in
            let client = MotionClientConnection(id: clients.nextID())
            let (decision, session) = request.accept(
                incomingMessageHandler: { (request: HelperRequest) -> (any Encodable)? in
                    client.handle(request)
                    return nil
                },
                cancellationHandler: { _ in
                    client.close()
                    clients.remove(client.id)
                }
            )
            client.attach(session)
            clients.add(client.id)
            return decision
        }

        log.notice("Listening on \(HelperService.machServiceName, privacy: .public)")
        clients.scheduleIdleExit()
        withExtendedLifetime(listener) {
            dispatchMain()
        }
    }
}

private let log = Logger(subsystem: HelperService.machServiceName, category: "server")

/// Tracks connected clients and exits the process after a period with none.
private final class ClientRegistry: Sendable {
    private struct State {
        var lastID = 0
        var connected: Set<Int> = []
        /// Bumped on every change, so a pending idle check can tell it's stale.
        var generation = 0
    }

    private let idleTimeout: Duration
    private let state = Mutex(State())

    init(idleTimeout: Duration) {
        self.idleTimeout = idleTimeout
    }

    func nextID() -> Int {
        state.withLock { state in
            state.lastID += 1
            return state.lastID
        }
    }

    func add(_ id: Int) {
        let count = state.withLock { state in
            state.connected.insert(id)
            state.generation += 1
            return state.connected.count
        }
        log.notice("Client \(id) connected (\(count) active)")
    }

    func remove(_ id: Int) {
        let count = state.withLock { state in
            state.connected.remove(id)
            state.generation += 1
            return state.connected.count
        }
        log.notice("Client \(id) disconnected (\(count) active)")
        if count == 0 {
            scheduleIdleExit()
        }
    }

    func scheduleIdleExit() {
        let generation = state.withLock { $0.generation }
        let delay = Double(idleTimeout.components.seconds) + Double(idleTimeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            let idle = state.withLock { $0.generation == generation && $0.connected.isEmpty }
            if idle {
                log.notice("No clients for \(delay, format: .fixed(precision: 0)) s; exiting until launchd needs us again")
                exit(0)
            }
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

    let id: Int
    private let state = Mutex(State())

    init(id: Int) {
        self.id = id
    }

    func attach(_ session: XPCSession) {
        state.withLock { $0.session = session }
    }

    func handle(_ request: HelperRequest) {
        switch request {
        case .startMotion: start()
        case .stopMotion: stopStreaming()
        }
    }

    /// Stops streaming and drops the session. The session's handlers reference this
    /// connection, so releasing the session here is what lets both be freed.
    func close() {
        stopStreaming()
        state.withLock { $0.session = nil }
    }

    private func stopStreaming() {
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
            log.error("Client \(self.id) couldn't start motion: \(error.description, privacy: .public)")
            send(.failure(error.description))
            return
        }
        log.notice("Client \(self.id) started motion")

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
            // The app went away; its cancellation handler will close this connection.
        }
    }
}
