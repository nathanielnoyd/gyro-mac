import Foundation

/// A 24-bit color, shown as closely as the terminal allows.
struct TerminalColor: Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    /// The nearest of the 16 basic colors, as its foreground SGR code (30–37 or 90–97).
    var basic: Int

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8, basic: Int) {
        self.red = red
        self.green = green
        self.blue = blue
        self.basic = basic
    }

    /// Mixes toward `other` by `amount`, from 0 to 1.
    ///
    /// Without truecolor, gives whichever end is closer: colors in between tend to land on muddy palette entries.
    func mixed(with other: TerminalColor, by amount: Double) -> TerminalColor {
        guard Style.depth == .trueColor else { return amount < 0.5 ? self : other }
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * min(max(amount, 0), 1)).rounded())
        }
        return TerminalColor(mix(red, other.red), mix(green, other.green), mix(blue, other.blue), basic: amount < 0.5 ? basic : other.basic)
    }

    fileprivate func sgr(background: Bool) -> String {
        switch Style.depth {
        case .none:
            return ""
        case .basic:
            return String(basic + (background ? 10 : 0))
        case .palette256:
            return (background ? "48;5;" : "38;5;") + String(paletteIndex)
        case .trueColor:
            return (background ? "48;2;" : "38;2;") + "\(red);\(green);\(blue)"
        }
    }

    /// The nearest entry in the 6×6×6 cube or gray ramp of the 256-color palette.
    private var paletteIndex: Int {
        let levels = [0, 95, 135, 175, 215, 255]
        func nearestLevel(_ value: UInt8) -> Int {
            levels.indices.min { abs(levels[$0] - Int(value)) < abs(levels[$1] - Int(value)) }!
        }
        let (r, g, b) = (nearestLevel(red), nearestLevel(green), nearestLevel(blue))
        let cube = (levels[r], levels[g], levels[b])

        let average = (Int(red) + Int(green) + Int(blue)) / 3
        let grayStep = min(max((average - 8 + 5) / 10, 0), 23)
        let gray = 8 + grayStep * 10

        func distance(_ c: (Int, Int, Int)) -> Int {
            let (dr, dg, db) = (c.0 - Int(red), c.1 - Int(green), c.2 - Int(blue))
            return dr * dr + dg * dg + db * db
        }
        return distance((gray, gray, gray)) < distance(cube) ? 232 + grayStep : 16 + 36 * r + 6 * g + b
    }
}

/// The CLI's colors, matched to the Gyro app's dark appearance.
enum Palette {
    static let red = TerminalColor(255, 69, 58, basic: 91)
    static let green = TerminalColor(48, 209, 88, basic: 92)
    static let blue = TerminalColor(64, 156, 255, basic: 94)
    static let cyan = TerminalColor(100, 210, 255, basic: 96)
    static let yellow = TerminalColor(255, 214, 10, basic: 93)
    static let purple = TerminalColor(191, 90, 242, basic: 95)
    /// The gold of the app icon's rotor, used for vibration.
    static let gold = TerminalColor(255, 196, 61, basic: 33)
    static let dimGold = TerminalColor(150, 115, 40, basic: 33)
    static let accent = TerminalColor(10, 132, 255, basic: 94)
    static let white = TerminalColor(235, 235, 245, basic: 97)
    static let secondary = TerminalColor(152, 152, 162, basic: 37)
    static let border = TerminalColor(72, 72, 84, basic: 90)
    static let skyHigh = TerminalColor(28, 78, 160, basic: 34)
    static let skyLow = TerminalColor(80, 180, 230, basic: 36)
    static let groundHigh = TerminalColor(172, 132, 92, basic: 33)
    static let groundLow = TerminalColor(120, 85, 45, basic: 33)

    /// The color for each axis, as in the app: x red, y green, z blue.
    static let axes = [red, green, blue]
}

/// ANSI text styling, disabled when output isn't a terminal or `NO_COLOR` is set.
enum Style {
    enum Depth: Comparable {
        case none, basic, palette256, trueColor
    }

    static let depth: Depth = {
        let environment = ProcessInfo.processInfo.environment
        guard isatty(STDOUT_FILENO) != 0, environment["NO_COLOR"] == nil else { return .none }
        let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
        let term = environment["TERM"]?.lowercased() ?? ""
        if colorTerm == "truecolor" || colorTerm == "24bit" || ["direct", "truecolor", "ghostty", "kitty", "wezterm", "alacritty"].contains(where: term.contains) {
            return .trueColor
        }
        return term.contains("256") ? .palette256 : .basic
    }()

    static var isEnabled: Bool { depth != .none }

    /// Whether output goes to a terminal, rather than a pipe or file that a script might read.
    static let isTerminal = isatty(STDOUT_FILENO) != 0

    static func bold(_ text: String) -> String { apply("1", text) }
    static func dim(_ text: String) -> String { apply("2", text) }
    static func red(_ text: String) -> String { color(Palette.red, text) }
    static func green(_ text: String) -> String { color(Palette.green, text) }
    static func yellow(_ text: String) -> String { color(Palette.yellow, text) }
    static func blue(_ text: String) -> String { color(Palette.blue, text) }
    static func cyan(_ text: String) -> String { color(Palette.cyan, text) }

    /// The color used for each axis throughout the CLI: x red, y green, z blue.
    static func axis(_ index: Int, _ text: String) -> String {
        color(Palette.axes[index], text)
    }

    static func color(_ foreground: TerminalColor, _ text: String) -> String {
        apply(foreground.sgr(background: false), text)
    }

    static func color(_ foreground: TerminalColor?, on background: TerminalColor?, _ text: String) -> String {
        let codes = [foreground?.sgr(background: false), background?.sgr(background: true)].compactMap(\.self)
        return apply(codes.joined(separator: ";"), text)
    }

    private static func apply(_ code: String, _ text: String) -> String {
        isEnabled && !code.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}

extension String {
    /// The number of characters shown on screen, ignoring ANSI escape sequences.
    var visibleWidth: Int {
        guard contains("\u{1B}") else { return count }
        return replacing(/\u{1B}\[[0-9;?]*[A-Za-z]/, with: "").count
    }

    /// Pads with trailing spaces to `width` visible characters.
    func padded(to width: Int) -> String {
        let visible = visibleWidth
        return visible >= width ? self : self + String(repeating: " ", count: width - visible)
    }

    /// Pads with leading spaces to `width` visible characters.
    func leftPadded(to width: Int) -> String {
        let visible = visibleWidth
        return visible >= width ? self : String(repeating: " ", count: width - visible) + self
    }

    /// Cuts to at most `width` visible characters, keeping escape sequences intact.
    func truncated(to width: Int) -> String {
        guard visibleWidth > width else { return self }
        var result = ""
        var visible = 0
        var inEscape = false
        for character in self {
            if inEscape {
                result.append(character)
                if character.isLetter { inEscape = false }
            } else if character == "\u{1B}" {
                result.append(character)
                inEscape = true
            } else if visible < width {
                result.append(character)
                visible += 1
            }
        }
        return result + (Style.isEnabled ? "\u{1B}[0m" : "")
    }
}
