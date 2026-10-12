/// A drawing surface of braille dots: each character cell holds a 2×4 grid of dots, which are about square.
///
/// Each cell has one color, set by whatever was drawn in it last.
struct BrailleCanvas {
    /// Size in character cells.
    let columns: Int
    let rows: Int

    private var dots: [UInt8]
    private var colors: [TerminalColor?]
    private var glyphs: [(Character, TerminalColor)?]

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 0)
        self.rows = max(rows, 0)
        dots = Array(repeating: 0, count: self.columns * self.rows)
        colors = Array(repeating: nil, count: self.columns * self.rows)
        glyphs = Array(repeating: nil, count: self.columns * self.rows)
    }

    /// Size in dots.
    var width: Int { columns * 2 }
    var height: Int { rows * 4 }

    /// Turns on the dot at `x`, `y`, counted from the top left. Dots outside the canvas are ignored.
    mutating func plot(_ x: Int, _ y: Int, _ color: TerminalColor) {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return }
        let cell = (y / 4) * columns + x / 2
        dots[cell] |= Self.bits[y % 4][x % 2]
        colors[cell] = color
    }

    /// Draws a straight line between two points, in dots.
    mutating func line(from start: (x: Double, y: Double), to end: (x: Double, y: Double), _ color: TerminalColor) {
        let steps = Int(max(abs(end.x - start.x), abs(end.y - start.y)).rounded(.up))
        guard steps > 0 else {
            plot(Int(start.x.rounded()), Int(start.y.rounded()), color)
            return
        }
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            plot(
                Int((start.x + (end.x - start.x) * t).rounded()), Int((start.y + (end.y - start.y) * t).rounded()),
                color)
        }
    }

    /// Puts a character over a cell, replacing its dots.
    mutating func put(_ character: Character, column: Int, row: Int, _ color: TerminalColor) {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return }
        glyphs[row * columns + column] = (character, color)
    }

    func render() -> [String] {
        (0..<rows).map { row in
            var line = ""
            var run = ""
            var runColor: TerminalColor?
            func flush() {
                line += runColor.map { Style.color($0, run) } ?? run
                run = ""
            }
            for column in 0..<columns {
                let cell = row * columns + column
                let (character, color): (Character, TerminalColor?) =
                    if let glyph = glyphs[cell] {
                        (glyph.0, glyph.1)
                    } else if dots[cell] == 0 {
                        (" ", runColor)
                    } else {
                        (Character(UnicodeScalar(0x2800 + UInt32(dots[cell]))!), colors[cell])
                    }
                if color != runColor {
                    flush()
                    runColor = color
                }
                run.append(character)
            }
            flush()
            return line
        }
    }

    /// The bit for each dot in a braille cell, by row then column.
    private static let bits: [[UInt8]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]
}

/// A drawing surface of colored square pixels, two per character cell using half blocks.
struct PixelCanvas {
    let columns: Int
    let rows: Int
    private var pixels: [TerminalColor?]

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        pixels = Array(repeating: nil, count: columns * rows * 2)
    }

    var width: Int { columns }
    var height: Int { rows * 2 }

    subscript(x: Int, y: Int) -> TerminalColor? {
        get { pixels[y * width + x] }
        set {
            guard (0..<width).contains(x), (0..<height).contains(y) else { return }
            pixels[y * width + x] = newValue
        }
    }

    func render() -> [String] {
        (0..<rows).map { row in
            (0..<columns).map { column in
                let top = self[column, row * 2]
                let bottom = self[column, row * 2 + 1]
                switch (top, bottom) {
                case (nil, nil): return " "
                case (let top?, nil): return Style.color(top, "▀")
                case (nil, let bottom?): return Style.color(bottom, "▄")
                case (let top?, let bottom?):
                    return top == bottom ? Style.color(top, "█") : Style.color(top, on: bottom, "▀")
                }
            }.joined()
        }
    }
}
