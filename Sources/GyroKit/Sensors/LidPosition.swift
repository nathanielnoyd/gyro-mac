/// A rough description of how far the lid is open.
public enum LidPosition: Sendable, CaseIterable, CustomStringConvertible {
    case closed
    case barelyOpen
    case open
    case wideOpen

    /// The position for a lid angle in degrees, as read by ``LidAngleSensor``.
    public init(angle: Double) {
        self =
            switch angle {
            case ..<1: .closed
            case ..<60: .barelyOpen
            case ..<135: .open
            default: .wideOpen
            }
    }

    /// The position in sentence case, such as “Barely open”.
    public var description: String {
        switch self {
        case .closed: "Closed"
        case .barelyOpen: "Barely open"
        case .open: "Open"
        case .wideOpen: "Wide open"
        }
    }
}
