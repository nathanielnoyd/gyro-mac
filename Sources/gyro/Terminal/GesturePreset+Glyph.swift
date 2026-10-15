import GyroKit

extension GesturePreset {
    /// A one-column stand-in for the app's SF Symbol. Avoids characters that terminals may draw as wide emoji.
    var glyph: Character {
        switch id {
        case "tap-left": "◂"
        case "tap-right": "▸"
        case "double-tap": "◆"
        case "soft-typing": "∴"
        case "hard-typing": "≡"
        case "desk-shake": "≈"
        case "pick-up": "⇕"
        default: "●"
        }
    }
}
