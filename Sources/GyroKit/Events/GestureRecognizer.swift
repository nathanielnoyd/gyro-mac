/// Matches ``MotionEvent`` values against a set of gesture signatures.
///
/// Taps are recognized one group at a time: the closest matching signature wins. Activity is
/// a state. It begins once the same signature has been the closest match for
/// ``onsetCount`` summaries in a row, and ends after ``releaseCount`` summaries that don't match it.
public struct GestureRecognizer: Sendable {
    /// A gesture the recognizer looks for.
    public struct Candidate: Hashable, Sendable {
        /// Identifies the gesture in each ``Recognition``.
        public var id: String
        /// What the gesture looks like to the sensors.
        public var signature: GestureSignature
        /// Scales the signature's ranges. Above 1 is more forgiving.
        public var tolerance: Double

        /// Creates a candidate.
        public init(id: String, signature: GestureSignature, tolerance: Double = 1) {
            self.id = id
            self.signature = signature
            self.tolerance = tolerance
        }
    }

    /// A gesture the recognizer found.
    public struct Recognition: Hashable, Sendable {
        /// What happened to the gesture.
        public enum Phase: Hashable, Sendable {
            /// A group of taps matched.
            case tapped
            /// An activity started.
            case began
            /// An activity stopped.
            case ended
        }

        /// The matching candidate's ``Candidate/id``.
        public var id: String
        /// Whether taps matched, or an activity began or ended.
        public var phase: Phase
        /// The event that led to the recognition.
        public var event: MotionEvent
        /// How far the event was from the middle of the signature, 0 to 1.
        public var distance: Double
    }

    /// The gestures to look for.
    ///
    /// Removing the candidate for ``activeActivity`` clears it without an ``Recognition/Phase/ended``
    /// recognition.
    public var candidates: [Candidate] {
        didSet {
            if let activeActivity, !candidates.contains(where: { $0.id == activeActivity }) {
                self.activeActivity = nil
            }
        }
    }

    /// Summaries in a row an activity must match before it begins. At the default interval, 0.75 s.
    public var onsetCount = 3
    /// Summaries in a row that must not match before an activity ends. At the default interval, 1 s.
    public var releaseCount = 4

    /// The activity happening now, if any.
    public private(set) var activeActivity: String?

    private var leader: String?
    private var streak = 0
    private var misses = 0

    /// Creates a recognizer that looks for `candidates`.
    public init(candidates: [Candidate] = []) {
        self.candidates = candidates
    }

    /// The closest candidate that matches `event`, if any.
    public func bestMatch(for event: MotionEvent) -> (id: String, distance: Double)? {
        candidates
            .compactMap { candidate in
                candidate.signature.distance(to: event, tolerance: candidate.tolerance).map { (candidate.id, $0) }
            }
            .min { $0.1 < $1.1 }
    }

    /// Feeds one event and returns what it recognized.
    ///
    /// A taps event yields at most one ``Recognition/Phase/tapped`` recognition. An activity event can
    /// end one activity and begin another in the same call.
    public mutating func recognize(_ event: MotionEvent) -> [Recognition] {
        let match = bestMatch(for: event)
        switch event.kind {
        case .taps:
            return match.map { [Recognition(id: $0.id, phase: .tapped, event: event, distance: $0.distance)] } ?? []
        case .activity:
            return track(match, event: event)
        }
    }

    private mutating func track(_ match: (id: String, distance: Double)?, event: MotionEvent) -> [Recognition] {
        if let match, match.id == leader {
            streak += 1
        } else {
            leader = match?.id
            streak = match == nil ? 0 : 1
        }
        misses = match?.id == activeActivity ? 0 : misses + 1

        var recognitions: [Recognition] = []
        if let match, match.id != activeActivity, streak >= onsetCount {
            if let activeActivity {
                recognitions.append(Recognition(id: activeActivity, phase: .ended, event: event, distance: 1))
            }
            activeActivity = match.id
            misses = 0
            recognitions.append(Recognition(id: match.id, phase: .began, event: event, distance: match.distance))
        } else if let activeActivity, misses >= releaseCount {
            recognitions.append(Recognition(id: activeActivity, phase: .ended, event: event, distance: 1))
            self.activeActivity = nil
        }
        return recognitions
    }
}
