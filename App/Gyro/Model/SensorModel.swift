import GyroKit
import GyroXPC
import Observation
import os

private let log = Logger(subsystem: HelperService.appBundleIdentifier, category: "motion")

/// Live sensor state for the whole app.
///
/// Motion readings stream in on a background task and are folded into
/// ``MotionBuffer``. A frame loop then publishes them to SwiftUI about 60
/// times a second, which is all the UI can show anyway.
@Observable
final class SensorModel {
    enum MotionStatus: Equatable {
        case stopped
        case connecting
        case streaming
        /// The helper is installed, but launchd didn't start it or the connection dropped.
        case unreachable
        case failed(String)
    }

    private(set) var motion = MotionSnapshot()
    private(set) var history = MotionHistory()
    private(set) var motionStatus = MotionStatus.stopped
    private(set) var sampleRate: Double?
    private(set) var lidAngle: Double?
    /// Where motion is coming from, while it streams or is about to.
    private(set) var source: MotionSource?

    @ObservationIgnored private let buffer = MotionBuffer()
    @ObservationIgnored private let lidSensor = try? LidAngleSensor()
    @ObservationIgnored private var rateMeter = SampleRateMeter()
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var connectingSince: ContinuousClock.Instant?
    @ObservationIgnored private var pendingVibration = 0.0

    /// Receives taps and activity summaries as they're detected, on the main actor.
    @ObservationIgnored var eventHandler: (([MotionEvent]) -> Void)?

    /// If launchd can't start the helper, the connection waits silently instead of failing.
    private static let connectionTimeout = Duration.seconds(5)
    private static let frameInterval = Duration.milliseconds(16)

    var hasLidSensor: Bool { lidSensor != nil }

    /// Whether motion is streaming or about to.
    var isMotionLive: Bool {
        motionStatus == .connecting || motionStatus == .streaming
    }

    /// Starts the frame loop, which also polls the lid angle.
    ///
    /// While motion is off, the loop slows to the lid's polling rate, and ends if there's no lid
    /// sensor either. ``startMotion(from:)`` starts it again.
    func start() {
        guard frameTask == nil else { return }
        frameTask = Task { [weak self] in
            var frame = 0
            while !Task.isCancelled {
                // Ends once the model is gone, or there's nothing left to update.
                guard let interval = self?.publishFrame(frame) else { break }
                frame += 1
                try? await Task.sleep(for: interval)
            }
            self?.frameTask = nil
        }
    }

    func startMotion(from source: MotionSource) {
        stopMotion()
        self.source = source
        motionStatus = .connecting
        connectingSince = .now
        start()

        // Readings the previous source's task delivers before it notices it was cancelled
        // carry an older session, so the buffer drops them.
        let buffer = buffer
        let session = buffer.session
        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for try await sample in try source.samples() {
                    buffer.process(sample, session: session)
                }
            } catch is CancellationError {
                return
            } catch MotionClient.Failure.connection {
                await self?.motionUnreachable()
            } catch {
                await self?.motionFailed(error)
            }
        }
    }

    func stopMotion() {
        streamTask?.cancel()
        streamTask = nil
        buffer.reset()
        source = nil
        motionStatus = .stopped
        motion = MotionSnapshot()
        history.removeAll()
        rateMeter.reset()
        sampleRate = nil
    }

    /// Re-zeroes the orientation estimate. Mostly useful for yaw, which drifts.
    func resetAttitude() {
        buffer.resetAttitude()
    }

    /// Starts keeping raw readings, including the last couple of seconds, for a recording.
    func startCapture() {
        buffer.startCapture()
    }

    /// Stops keeping raw readings and returns them.
    func finishCapture() -> MotionRecording {
        MotionRecording(samples: buffer.finishCapture())
    }

    private func motionUnreachable() {
        guard !Task.isCancelled else { return }
        log.notice("Couldn't reach the helper")
        motionStatus = .unreachable
    }

    private func motionFailed(_ error: any Error) {
        guard !Task.isCancelled else { return }
        log.error("Motion failed: \(String(describing: error), privacy: .public)")
        motionStatus = .failed(String(describing: error))
    }

    /// Publishes one frame, and returns how long to wait before the next, or `nil` to stop.
    private func publishFrame(_ frame: Int) -> Duration? {
        if motionStatus == .connecting, let connectingSince, connectingSince.duration(to: .now) > Self.connectionTimeout
        {
            streamTask?.cancel()
            log.notice("The helper didn't answer within \(Self.connectionTimeout, privacy: .public)")
            motionStatus = .unreachable
        }

        let update = buffer.takeFrame()
        if update.sampleCount > 0, motionStatus != .stopped {
            motion = update.snapshot
            if motionStatus == .connecting {
                motionStatus = .streaming
            }
            rateMeter.record(update.sampleCount, at: update.snapshot.timestamp)
            if sampleRate != rateMeter.hertz {
                sampleRate = rateMeter.hertz
            }
            // Charts don't need 60 points a second, but keep the strongest shake in between.
            pendingVibration = max(pendingVibration, update.vibration)
            if frame.isMultiple(of: 2) {
                history.append(update.snapshot, vibration: pendingVibration)
                pendingVibration = 0
            }
        }
        if !update.events.isEmpty, motionStatus == .streaming {
            eventHandler?(update.events)
        }

        // Every frame while idle, since those come four times slower.
        if frame.isMultiple(of: 4) || !isMotionLive, let lidSensor {
            let angle = try? lidSensor.angle()
            if angle != lidAngle {
                lidAngle = angle
            }
        }

        if isMotionLive { return Self.frameInterval }
        return lidSensor == nil ? nil : Self.frameInterval * 4
    }
}
