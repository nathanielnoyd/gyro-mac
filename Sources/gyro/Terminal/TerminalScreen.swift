import Foundation

/// Takes over the terminal for a full-screen display.
///
/// Switches to the alternate screen, hides the cursor and reads keys without
/// waiting for Return. ``restore()`` puts everything back.
final class TerminalScreen {
    private var originalAttributes = termios()
    private var isActive = false

    init() {
        guard isatty(STDIN_FILENO) != 0 else { return }
        tcgetattr(STDIN_FILENO, &originalAttributes)

        var raw = originalAttributes
        // No line buffering, no echo, and Ctrl-C arrives as a key so we can clean up.
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        // Reads return immediately, with or without a key.
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        write("\u{1B}[?1049h\u{1B}[?25l")
        isActive = true
    }

    deinit {
        restore()
    }

    func restore() {
        guard isActive else { return }
        write("\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalAttributes)
        isActive = false
    }

    /// The key pressed since the last call, if any.
    func readKey() -> Character? {
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }
        return Character(UnicodeScalar(byte))
    }

    /// The terminal's size in characters, or 80×24 if it can't be read.
    var size: (columns: Int, rows: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 else { return (80, 24) }
        return (Int(size.ws_col), Int(size.ws_row))
    }

    /// Replaces the screen contents with `lines`, cut to fit so nothing wraps or scrolls.
    func draw(_ lines: [String]) {
        // Clear each line before writing it: clearing after a line that fills the width would erase its last character.
        let clearLine = "\u{1B}[2K"
        let (columns, rows) = size
        let frame = lines.prefix(rows).map { clearLine + $0.truncated(to: columns) }.joined(separator: "\n")
        write("\u{1B}[H" + frame + "\u{1B}[J")
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

extension Character {
    static let controlC = Character(UnicodeScalar(3))
}
