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

    /// Replaces the screen contents with `lines`.
    func draw(_ lines: [String]) {
        let clearToEndOfLine = "\u{1B}[K"
        let frame = lines.map { $0 + clearToEndOfLine }.joined(separator: "\n")
        write("\u{1B}[H" + frame + "\u{1B}[J")
    }

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}

extension Character {
    static let controlC = Character(UnicodeScalar(3))
}
