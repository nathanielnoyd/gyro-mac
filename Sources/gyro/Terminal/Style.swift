import Foundation

/// ANSI text styling, disabled when output isn't a terminal or `NO_COLOR` is set.
enum Style {
    static let isEnabled = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func bold(_ text: String) -> String { apply("1", text) }
    static func dim(_ text: String) -> String { apply("2", text) }
    static func red(_ text: String) -> String { apply("31", text) }
    static func green(_ text: String) -> String { apply("32", text) }
    static func yellow(_ text: String) -> String { apply("33", text) }
    static func blue(_ text: String) -> String { apply("34", text) }
    static func cyan(_ text: String) -> String { apply("36", text) }

    /// The color used for each axis throughout the CLI: x red, y green, z blue.
    static func axis(_ index: Int, _ text: String) -> String {
        [red, green, blue][index](text)
    }

    private static func apply(_ code: String, _ text: String) -> String {
        isEnabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}

extension String {
    /// The number of characters shown on screen, ignoring ANSI escape sequences.
    var visibleWidth: Int {
        replacing(/\u{1B}\[[0-9;?]*[A-Za-z]/, with: "").count
    }

    /// Pads with trailing spaces to `width` visible characters.
    func padded(to width: Int) -> String {
        let visible = visibleWidth
        return visible >= width ? self : self + String(repeating: " ", count: width - visible)
    }

    /// Pads with leading spaces to `width` characters. Only use on unstyled text.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
