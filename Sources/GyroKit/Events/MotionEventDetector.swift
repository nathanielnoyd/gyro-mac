import Foundation

/// Finds taps and ongoing motion in the IMU's readings, and describes each with ``MotionFeature`` values.
///
/// Two high-pass filters split the acceleration. The fast one (above about 16 Hz) isolates jolts:
/// a tap rings the chassis for a few tens of milliseconds and stands far above the background
/// there, while tilting the Mac barely registers. The slow one (above about 1.5 Hz) keeps the
/// low rumble of a wobbling desk for the activity summaries.
///
/// A jolt is anything louder than a few times the background noise, which the detector keeps
/// measuring while things are quiet. Jolts close together form a group. A group of up to a few
/// short jolts, with quiet on both sides, becomes a ``MotionEvent/Kind/taps`` event. Typing makes
/// jolts too, but they keep coming, so their groups grow too long to count as taps.
///
/// Independently, every ``Configuration/activityInterval`` the detector summarizes the last
/// ``Configuration/activityWindow`` seconds as an ``MotionEvent/Kind/activity`` event.
public struct MotionEventDetector: Sendable {
    /// Bump when features change meaning, so saved examples are measured again from their recordings.
    public static let version = 1

    public struct Configuration: Hashable, Sendable {
        /// The smallest jolt, in g, that counts, however quiet the Mac is.
        public var minimumThreshold = 0.004
        /// How many times the background noise a jolt must reach.
        public var noiseMultiple = 4.0
        /// Jolts further apart than this, in seconds, belong to separate groups.
        public var maximumGap = 0.4
        /// How long the Mac must be quiet, in seconds, before a group for it to count as taps.
        public var quietBefore = 0.5
        /// Groups with more jolts than this are activity, not taps.
        public var maximumTaps = 4
        /// A jolt longer than this, in seconds, is ongoing motion rather than a tap.
        /// Taps on a MacBook ring for about 200 ms, knocks on a desk for up to about 500 ms.
        public var maximumLength = 0.8
        /// How many seconds each activity summary covers.
        public var activityWindow = 1.5
        /// Seconds between activity summaries.
        public var activityInterval = 0.25

        public init() {}
    }

    public var configuration: Configuration

    /// The current background level, in g, that jolts are measured against.
    public private(set) var noiseFloor = 0.001

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The level, in g, a jolt has to reach right now.
    public var threshold: Double {
        max(configuration.minimumThreshold, noiseFloor * configuration.noiseMultiple)
    }

    /// Feeds one reading and returns any events it completed.
    public mutating func process(_ sample: MotionSample) -> [MotionEvent] {
        switch sample.kind {
        case .rotationRate:
            processRotation(sample.value, at: sample.timestamp)
            return []
        case .acceleration:
            return processAcceleration(sample.value, at: sample.timestamp)
        }
    }

    // MARK: - Filters

    /// Filter time constants, in seconds.
    private enum Smoothing {
        static let fastAcceleration = 0.01
        static let slowAcceleration = 0.1
        static let fastRotation = 0.1
        static let slowRotation = 2.0
        static let noise = 3.0
        /// Faster than ``noise``, so rocking the Mac doesn't dull the next tap's rock for long.
        static let rotationNoise = 1.0
        static let initialNoise = 0.2
    }

    /// Readings further apart than this, in seconds (after sleep, say), restart the filters.
    private static let maximumStep = 0.1
    /// Filters settle for this long, in seconds, before jolts count.
    private static let warmUp = 0.5
    /// A jolt ends once it has stayed quiet for this long, in seconds. Quiet means under half
    /// the threshold, or under ``releaseFraction`` of the jolt's peak, whichever is higher.
    private static let release = 0.03
    /// The chassis keeps ringing faintly for half a second after a hard tap. Below this share
    /// of the peak, the jolt counts as over.
    private static let releaseFraction = 0.12
    /// Right after a jolt, its fading echo must be outdone before another jolt counts:
    /// this share of the last peak, decaying with ``echoDecay``.
    private static let echoFraction = 0.35
    /// The echo's time constant, in seconds.
    private static let echoDecay = 0.2
    /// Readings kept from just before a jolt, so its onset isn't lost.
    private static let preRoll = 24

    private struct Reading {
        var time: Double
        var value: Vector3
    }

    private var accelerationClock: Double?
    private var rotationClock: Double?
    private var startTime: Double?
    private var fastAccelerationBase: Vector3 = .zero
    private var slowAccelerationBase: Vector3 = .zero
    private var fastRotationBase: Vector3 = .zero
    private var slowRotationBase: Vector3 = .zero
    private var rotationNoise = 0.05
    private var recentAcceleration: [Reading] = []
    private var recentRotation: [Reading] = []

    private static func weight(_ dt: Double, _ timeConstant: Double) -> Double {
        min(dt / timeConstant, 1)
    }

    /// Seconds since the previous reading on `clock`, or `nil` when the filters should restart.
    private static func step(_ clock: inout Double?, to time: Double) -> Double? {
        defer { clock = time }
        guard let previous = clock else { return nil }
        let dt = time - previous
        return dt >= 0 && dt < maximumStep ? dt : nil
    }

    private static func remember(_ reading: Reading, in readings: inout [Reading]) {
        readings.append(reading)
        if readings.count > 2 * preRoll {
            readings.removeFirst(readings.count - preRoll)
        }
    }

    private mutating func processRotation(_ rate: Vector3, at time: Double) {
        guard let dt = Self.step(&rotationClock, to: time) else {
            fastRotationBase = rate
            slowRotationBase = rate
            return
        }
        fastRotationBase += (rate - fastRotationBase) * Self.weight(dt, Smoothing.fastRotation)
        slowRotationBase += (rate - slowRotationBase) * Self.weight(dt, Smoothing.slowRotation)
        let fast = rate - fastRotationBase
        let slow = rate - slowRotationBase

        bucket.turning += slow.magnitude * slow.magnitude
        bucket.rotationCount += 1

        let reading = Reading(time: time, value: fast)
        if jolt != nil {
            jolt?.rotation.append(reading)
        } else {
            rotationNoise += (fast.magnitude - rotationNoise) * Self.weight(dt, Smoothing.rotationNoise)
            Self.remember(reading, in: &recentRotation)
        }
    }

    private mutating func processAcceleration(_ acceleration: Vector3, at time: Double) -> [MotionEvent] {
        guard let dt = Self.step(&accelerationClock, to: time) else {
            restart(at: time, acceleration: acceleration)
            return []
        }
        fastAccelerationBase += (acceleration - fastAccelerationBase) * Self.weight(dt, Smoothing.fastAcceleration)
        slowAccelerationBase += (acceleration - slowAccelerationBase) * Self.weight(dt, Smoothing.slowAcceleration)
        let fast = acceleration - fastAccelerationBase
        let slow = acceleration - slowAccelerationBase
        let low = slow - fast

        bucket.vibration += slow.magnitude * slow.magnitude
        bucket.rumble += low.magnitude * low.magnitude
        bucket.accelerationCount += 1

        let level = fast.magnitude
        let threshold = threshold
        let reading = Reading(time: time, value: fast)
        let elapsed = time - (startTime ?? time)

        if let current = jolt, current.isRetriggered(by: level, at: time, threshold: threshold) {
            // A second tap while the first still rings, as in a quick double tap.
            finishJolt()
            jolt = Jolt(start: time, peak: level, acceleration: [reading], rotation: [])
        } else if jolt != nil {
            jolt?.add(reading, level: level, threshold: threshold, maximumLength: configuration.maximumLength)
            if let jolt, time - jolt.lastLoud > Self.release {
                finishJolt()
            }
        } else if level > max(threshold, echo(at: time)), elapsed > Self.warmUp {
            jolt = Jolt(start: time, peak: level, acceleration: recentAcceleration + [reading], rotation: recentRotation)
            recentAcceleration.removeAll(keepingCapacity: true)
            recentRotation.removeAll(keepingCapacity: true)
        } else {
            let smoothing = elapsed < 1 ? Smoothing.initialNoise : Smoothing.noise
            noiseFloor += (level - noiseFloor) * Self.weight(dt, smoothing)
            Self.remember(reading, in: &recentAcceleration)
        }

        var events: [MotionEvent] = []
        if let taps = finishGroupIfDue(at: time) {
            events.append(taps)
        }
        if let activity = summarizeIfDue(at: time) {
            events.append(activity)
        }
        return events
    }

    /// Starts over after the first reading or a long gap.
    private mutating func restart(at time: Double, acceleration: Vector3) {
        startTime = time
        fastAccelerationBase = acceleration
        slowAccelerationBase = acceleration
        jolt = nil
        group.removeAll()
        lastJoltEnd = -.infinity
        buckets.removeAll()
        bucket = Bucket()
        nextSummary = nil
        recentAcceleration.removeAll()
        recentRotation.removeAll()
    }

    // MARK: - Jolts and taps

    private struct Jolt {
        var start: Double
        var lastLoud: Double
        var peak: Double
        var acceleration: [Reading]
        var rotation: [Reading]
        var isSustained = false
        /// When the ringing last fell well below the peak, if it's stayed there since.
        var fadedSince: Double?
        /// Whether the ringing has stayed well below the peak for a while since it began.
        var hasFaded = false

        init(start: Double, peak: Double, acceleration: [Reading], rotation: [Reading]) {
            self.start = start
            self.lastLoud = start
            self.peak = peak
            self.acceleration = acceleration
            self.rotation = rotation
        }

        mutating func add(_ reading: Reading, level: Double, threshold: Double, maximumLength: Double) {
            acceleration.append(reading)
            peak = max(peak, level)
            if level > max(threshold / 2, peak * MotionEventDetector.releaseFraction) {
                lastLoud = reading.time
            }
            if level < peak * 0.3 {
                let since = fadedSince ?? reading.time
                fadedSince = since
                hasFaded = hasFaded || reading.time - since >= 0.03
            } else {
                fadedSince = nil
            }
            if reading.time - start > maximumLength {
                isSustained = true
            }
        }

        /// Whether `level` is a fresh jolt: strong, after the ringing had faded for a while.
        func isRetriggered(by level: Double, at time: Double, threshold: Double) -> Bool {
            guard !isSustained, hasFaded else { return false }
            return level >= max(peak * 0.5, threshold * 2)
        }
    }

    private var jolt: Jolt?
    private var group: [[MotionFeature: Double]] = []
    private var groupStart = 0.0
    private var groupIsValid = false
    private var lastJoltEnd = -Double.infinity
    private var lastJoltPeak = 0.0

    /// How loud the last jolt's lingering ringing may still be at `time`, in g.
    private func echo(at time: Double) -> Double {
        lastJoltPeak * Self.echoFraction * exp(-max(time - lastJoltEnd, 0) / Self.echoDecay)
    }

    private mutating func finishJolt() {
        guard let jolt else { return }
        self.jolt = nil
        let quiet = jolt.start - lastJoltEnd
        lastJoltEnd = jolt.lastLoud
        lastJoltPeak = jolt.peak

        bucket.impacts += 1
        bucket.impactStrength += log10(jolt.peak)

        guard !jolt.isSustained else {
            groupIsValid = false
            return
        }
        if group.isEmpty {
            groupStart = jolt.start
            groupIsValid = quiet >= configuration.quietBefore
        }
        group.append(Self.features(of: jolt, rotationNoise: rotationNoise))
    }

    private mutating func finishGroupIfDue(at time: Double) -> MotionEvent? {
        guard !group.isEmpty, jolt == nil, time - lastJoltEnd > configuration.maximumGap else { return nil }
        defer { group.removeAll() }
        guard groupIsValid, group.count <= configuration.maximumTaps else { return nil }
        return MotionEvent(kind: .taps, time: groupStart, count: group.count, features: Self.combine(group))
    }

    /// The group's features: the strongest jolt's strength and spin, and the average of the rest.
    private static func combine(_ taps: [[MotionFeature: Double]]) -> [MotionFeature: Double] {
        var combined: [MotionFeature: Double] = [:]
        for feature in MotionFeature.allCases where feature.kind == .taps {
            let values = taps.compactMap { $0[feature] }
            guard !values.isEmpty else { continue }
            switch feature {
            case .strength, .spin: combined[feature] = values.max()
            default: combined[feature] = values.reduce(0, +) / Double(values.count)
            }
        }
        return combined
    }

    private static func features(of jolt: Jolt, rotationNoise: Double) -> [MotionFeature: Double] {
        let push = firstSwing(jolt.acceleration.map(\.value)).normalized

        // How sure we are the Mac really tipped, rather than the gyroscope showing noise.
        let spin = jolt.rotation.map(\.value.magnitude).max() ?? 0
        let noise = max(rotationNoise, 0.05)
        let confidence = min(max((spin - 3 * noise) / (3 * noise), 0), 1)
        let rock = firstSwing(jolt.rotation.map(\.value)).normalized * confidence

        return [
            .strength: log10(jolt.peak),
            .spin: log10(max(spin, 0.01)),
            .rockX: rock.x,
            .rockY: rock.y,
            .pushX: push.x,
            .pushY: push.y,
            .pushZ: push.z,
            .length: log10(max(jolt.lastLoud - jolt.start, 0.001)),
            .tone: log10(max(tone(of: jolt, along: push), 1)),
        ]
    }

    /// The reading at the first big swing: where the signal first passes half its peak, then keeps rising.
    ///
    /// A tap rings back and forth, so the largest swing can point either way. The first one shows
    /// which way the tap actually pushed.
    static func firstSwing(_ values: [Vector3]) -> Vector3 {
        let magnitudes = values.map(\.magnitude)
        guard let peak = magnitudes.max(), peak > 0,
              var index = magnitudes.firstIndex(where: { $0 >= peak / 2 })
        else { return .zero }
        while index + 1 < magnitudes.count, magnitudes[index + 1] > magnitudes[index] {
            index += 1
        }
        return values[index]
    }

    /// How fast the jolt rings, in Hz, from how often it swings back and forth along its main direction.
    private static func tone(of jolt: Jolt, along direction: Vector3) -> Double {
        let readings = jolt.acceleration.filter { $0.time >= jolt.start && $0.time <= jolt.lastLoud }
        let values = readings.map { $0.value.x * direction.x + $0.value.y * direction.y + $0.value.z * direction.z }
        // Ignore the quiet tail, where noise would add crossings of its own.
        let floor = (values.map(abs).max() ?? 0) / 5

        var crossings: [Double] = []
        var sign = 0.0
        for (reading, value) in zip(readings, values) where abs(value) > floor {
            let current = value > 0 ? 1.0 : -1.0
            if sign != 0, current != sign {
                crossings.append(reading.time)
            }
            sign = current
        }
        guard let first = crossings.first, let last = crossings.last, last > first else {
            // Too short to ring: treat the jolt as half a swing.
            return 1 / (2 * max(jolt.lastLoud - jolt.start, 0.002))
        }
        let halfPeriod = (last - first) / Double(crossings.count - 1)
        return 1 / (2 * halfPeriod)
    }

    // MARK: - Activity

    /// Sums over one ``Configuration/activityInterval``.
    private struct Bucket {
        var vibration = 0.0
        var rumble = 0.0
        var accelerationCount = 0
        var turning = 0.0
        var rotationCount = 0
        var impacts = 0
        var impactStrength = 0.0
    }

    private var bucket = Bucket()
    private var buckets: [Bucket] = []
    private var nextSummary: Double?

    private mutating func summarizeIfDue(at time: Double) -> MotionEvent? {
        let interval = configuration.activityInterval
        guard let due = nextSummary else {
            nextSummary = time + interval
            return nil
        }
        guard time >= due else { return nil }
        nextSummary = time - due > interval ? time + interval : due + interval

        buckets.append(bucket)
        bucket = Bucket()
        let needed = max(Int((configuration.activityWindow / interval).rounded()), 1)
        if buckets.count > needed {
            buckets.removeFirst(buckets.count - needed)
        }
        guard buckets.count == needed else { return nil }

        func total<T: AdditiveArithmetic>(_ value: KeyPath<Bucket, T>) -> T {
            buckets.reduce(.zero) { $0 + $1[keyPath: value] }
        }
        let accelerationCount = Double(max(total(\.accelerationCount), 1))
        let rotationCount = Double(max(total(\.rotationCount), 1))
        let vibration = total(\.vibration)
        let impacts = total(\.impacts)

        return MotionEvent(kind: .activity, time: time, features: [
            .impacts: Double(impacts) / configuration.activityWindow,
            .impactStrength: impacts > 0 ? total(\.impactStrength) / Double(impacts) : MotionFeature.impactStrength.domain.lowerBound,
            .vibration: log10(max((vibration / accelerationCount).squareRoot(), 1e-4)),
            .rumble: vibration > 0 ? min((total(\.rumble) / vibration).squareRoot(), 1) : 0,
            .turning: log10(max((total(\.turning) / rotationCount).squareRoot(), 0.01)),
        ])
    }
}
