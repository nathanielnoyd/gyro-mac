/// A box with rounded corners, a title in its top edge and an optional note on the right of it.
struct Panel {
    var title: String
    var accessory = ""
    /// Total width, borders included.
    var width: Int
    var lines: [String]

    /// The width available to each line.
    static func contentWidth(for width: Int) -> Int { width - 4 }

    func render() -> [String] {
        let inner = Self.contentWidth(for: width)
        let border = { (text: String) in Style.color(Palette.border, text) }

        let heading = Style.bold(title)
        let note = accessory.isEmpty ? "" : " " + accessory + " "
        let rule = max(width - heading.visibleWidth - note.visibleWidth - 6, 0)
        let top = border("╭─ ") + heading + " " + border(String(repeating: "─", count: rule)) + note + border("─╮")

        let body = lines.map { border("│") + " " + $0.truncated(to: inner).padded(to: inner) + " " + border("│") }
        let bottom = border("╰" + String(repeating: "─", count: max(width - 2, 0)) + "╯")
        return [top] + body + [bottom]
    }
}

/// Numbers drawn three rows tall from block characters, for readings worth seeing from across the room.
enum LargeNumerals {
    static let height = 3

    static func render(_ text: String) -> [String] {
        (0..<height).map { row in
            text.map { character in
                if character == "°" { return row == 0 ? "°" : " " }
                return glyphs[character]?[row] ?? String(repeating: " ", count: 3)
            }.joined(separator: " ")
        }
    }

    private static let glyphs: [Character: [String]] = [
        "0": ["█▀█", "█ █", "▀▀▀"],
        "1": ["▀█ ", " █ ", "▀▀▀"],
        "2": ["▀▀█", "█▀▀", "▀▀▀"],
        "3": ["▀▀█", " ▀█", "▀▀▀"],
        "4": ["█ █", "▀▀█", "  ▀"],
        "5": ["█▀▀", "▀▀█", "▀▀▀"],
        "6": ["█▀▀", "█▀█", "▀▀▀"],
        "7": ["▀▀█", "  █", "  ▀"],
        "8": ["█▀█", "█▀█", "▀▀▀"],
        "9": ["█▀█", "▀▀█", "▀▀▀"],
        "-": ["   ", "▀▀▀", "   "],
    ]
}
