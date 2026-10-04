import GyroKit
import Observation

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
        case failed(String)
    }

    private(set) var motion = MotionSnapshot()
    private(set) var history = MotionHistory()
    private(set) var motionStatus = MotionStatus.stopped
    private(set) var sampleRate: Double?
    private(set) var lidAngle: Double?

    @ObservationIgnored private let buffer = MotionBuffer()
    @ObservationIgnored private let lidSensor = try? LidAngleSensor()
    @ObservationIgnored private var rateMeter = SampleRateMeter()
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var connectingSince: ContinuousClock.Instant?

    /// If launchd can't start the helper, the connection waits silently instead of failing.
    private static let connectionTimeout = Duration.seconds(5)

    var hasLidSensor: Bool { lidSensor != nil }

    /// Whether motion is streaming or about to.
    var isMotionLive: Bool {
        motionStatus == .connecting || motionStatus == .streaming
    }

    /// Starts the frame loop, which also polls the lid angle.
    func start() {
        guard frameTask == nil else { return }
        frameTask = Task { [weak self] in
            var frame = 0
            while !Task.isCancelled {
                self?.publishFrame(frame)
                frame += 1
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func startMotion(from source: MotionSource) {
        stopMotion()
        motionStatus = .connecting
        connectingSince = .now

        let buffer = buffer
        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for try await sample in try source.samples() {
                    buffer.process(sample)
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.motionFailed(error)
            }
        }
    }

    func stopMotion() {
        streamTask?.cancel()
        streamTask = nil
        buffer.reset()
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

    private func motionFailed(_ error: any Error) {
        guard !Task.isCancelled else { return }
        motionStatus = .failed(String(describing: error))
    }

    private func publishFrame(_ frame: Int) {
        if motionStatus == .connecting, let connectingSince, connectingSince.duration(to: .now) > Self.connectionTimeout {
            streamTask?.cancel()
            motionStatus = .failed("Gyro couldn't reach its helper. Try reinstalling it from Settings.")
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
            // Charts don't need 60 points a second.
            if frame.isMultiple(of: 2) {
                history.append(update.snapshot)
            }
        }

        if frame.isMultiple(of: 4), let lidSensor {
            let angle = try? lidSensor.angle()
            if angle != lidAngle {
                lidAngle = angle
            }
        }
    }
}
