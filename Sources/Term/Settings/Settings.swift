import AppKit

class Settings {
    static let shared = Settings()

    // MARK: - Properties

    var fontSize: Int = 14 {
        didSet {
            NotificationCenter.default.post(name: .fontSizeChanged, object: nil)
        }
    }

    var fontFamily: String = "SF Mono"

    var shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    var theme: Theme = .v0Dark {
        didSet {
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = true

    var scrollbackLines: Int = 10000

    var windowOpacity: Double = 1.0
    var vibrancy: Bool = false

    // MARK: - Persistence

    private let defaults = UserDefaults.standard

    func load() {
        fontSize = defaults.integer(forKey: "fontSize")
        if fontSize == 0 { fontSize = 14 }

        if let family = defaults.string(forKey: "fontFamily") {
            fontFamily = family
        }

        if let shellPath = defaults.string(forKey: "shell") {
            shell = shellPath
        }

        if let themeName = defaults.string(forKey: "theme"),
           let loadedTheme = Theme.named(themeName) {
            theme = loadedTheme
        }

        cursorBlink = defaults.bool(forKey: "cursorBlink")
        scrollbackLines = defaults.integer(forKey: "scrollbackLines")
        if scrollbackLines == 0 { scrollbackLines = 10000 }

        windowOpacity = defaults.double(forKey: "windowOpacity")
        if windowOpacity == 0 { windowOpacity = 1.0 }

        vibrancy = defaults.bool(forKey: "vibrancy")
    }

    func save() {
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(shell, forKey: "shell")
        defaults.set(theme.name, forKey: "theme")
        defaults.set(cursorBlink, forKey: "cursorBlink")
        defaults.set(scrollbackLines, forKey: "scrollbackLines")
        defaults.set(windowOpacity, forKey: "windowOpacity")
        defaults.set(vibrancy, forKey: "vibrancy")
    }
}

// MARK: - Cursor Style

enum CursorStyle: String, CaseIterable {
    case block = "Block"
    case underline = "Underline"
    case bar = "Bar"
}

// MARK: - Theme

struct Theme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor
    let cursorText: NSColor
    let selection: NSColor
    let border: NSColor

    // ANSI colors
    let black: NSColor
    let red: NSColor
    let green: NSColor
    let yellow: NSColor
    let blue: NSColor
    let magenta: NSColor
    let cyan: NSColor
    let white: NSColor

    // Bright variants
    let brightBlack: NSColor
    let brightRed: NSColor
    let brightGreen: NSColor
    let brightYellow: NSColor
    let brightBlue: NSColor
    let brightMagenta: NSColor
    let brightCyan: NSColor
    let brightWhite: NSColor

    // MARK: - v0.app Style Theme (Default)

    static let v0Dark = Theme(
        name: "v0 Dark",
        // Deep black with subtle blue tint (v0 style)
        background: NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0),  // #0a0a0d
        foreground: NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0),  // #ededed
        // Gradient-like cursor (purple/blue accent)
        cursor: NSColor(red: 0.55, green: 0.36, blue: 1.0, alpha: 1.0),       // #8c5cff
        cursorText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.35, green: 0.25, blue: 0.55, alpha: 0.4),   // Purple tint
        border: NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),      // Subtle border

        // ANSI - muted, modern palette
        black: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        red: NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0),         // Soft red
        green: NSColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1.0),       // Mint green
        yellow: NSColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1.0),       // Warm yellow
        blue: NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0),         // Vibrant blue
        magenta: NSColor(red: 0.75, green: 0.45, blue: 1.0, alpha: 1.0),      // Purple (v0 accent)
        cyan: NSColor(red: 0.30, green: 0.85, blue: 0.90, alpha: 1.0),        // Teal
        white: NSColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1.0),

        // Bright variants
        brightBlack: NSColor(red: 0.40, green: 0.40, blue: 0.45, alpha: 1.0),
        brightRed: NSColor(red: 1.0, green: 0.50, blue: 0.55, alpha: 1.0),
        brightGreen: NSColor(red: 0.45, green: 1.0, blue: 0.65, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 0.92, blue: 0.50, alpha: 1.0),
        brightBlue: NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 0.85, green: 0.60, blue: 1.0, alpha: 1.0),
        brightCyan: NSColor(red: 0.50, green: 1.0, blue: 0.95, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    // MARK: - v0 Midnight (даже темнее)

    static let v0Midnight = Theme(
        name: "v0 Midnight",
        background: NSColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1.0),    // Near black
        foreground: NSColor(red: 0.88, green: 0.88, blue: 0.92, alpha: 1.0),
        cursor: NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1.0),       // Brighter purple
        cursorText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.30, green: 0.20, blue: 0.50, alpha: 0.5),
        border: NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0),

        black: NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0),
        red: NSColor(red: 0.90, green: 0.30, blue: 0.40, alpha: 1.0),
        green: NSColor(red: 0.25, green: 0.80, blue: 0.50, alpha: 1.0),
        yellow: NSColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0),
        blue: NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0),
        magenta: NSColor(red: 0.70, green: 0.40, blue: 0.95, alpha: 1.0),
        cyan: NSColor(red: 0.25, green: 0.80, blue: 0.85, alpha: 1.0),
        white: NSColor(red: 0.80, green: 0.80, blue: 0.85, alpha: 1.0),

        brightBlack: NSColor(red: 0.35, green: 0.35, blue: 0.40, alpha: 1.0),
        brightRed: NSColor(red: 1.0, green: 0.45, blue: 0.50, alpha: 1.0),
        brightGreen: NSColor(red: 0.40, green: 0.95, blue: 0.60, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 0.90, blue: 0.45, alpha: 1.0),
        brightBlue: NSColor(red: 0.50, green: 0.70, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 0.80, green: 0.55, blue: 1.0, alpha: 1.0),
        brightCyan: NSColor(red: 0.45, green: 0.95, blue: 0.90, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    // MARK: - v0 Aurora (с цветными акцентами)

    static let v0Aurora = Theme(
        name: "v0 Aurora",
        background: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0),
        foreground: NSColor(red: 0.92, green: 0.92, blue: 0.95, alpha: 1.0),
        // Gradient cursor - pink to blue feel
        cursor: NSColor(red: 0.90, green: 0.40, blue: 0.70, alpha: 1.0),      // Pink
        cursorText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.45, green: 0.25, blue: 0.45, alpha: 0.4),
        border: NSColor(red: 0.18, green: 0.15, blue: 0.20, alpha: 1.0),

        black: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
        red: NSColor(red: 1.0, green: 0.40, blue: 0.50, alpha: 1.0),
        green: NSColor(red: 0.35, green: 0.90, blue: 0.60, alpha: 1.0),
        yellow: NSColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 1.0),
        blue: NSColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1.0),
        magenta: NSColor(red: 0.90, green: 0.45, blue: 0.85, alpha: 1.0),     // Pink-purple
        cyan: NSColor(red: 0.35, green: 0.90, blue: 0.95, alpha: 1.0),
        white: NSColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0),

        brightBlack: NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1.0),
        brightRed: NSColor(red: 1.0, green: 0.55, blue: 0.60, alpha: 1.0),
        brightGreen: NSColor(red: 0.50, green: 1.0, blue: 0.70, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 1.0),
        brightBlue: NSColor(red: 0.60, green: 0.80, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 1.0, green: 0.60, blue: 0.90, alpha: 1.0),
        brightCyan: NSColor(red: 0.55, green: 1.0, blue: 1.0, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    // MARK: - Legacy themes

    static let dark = Theme(
        name: "Classic Dark",
        background: NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        foreground: NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
        cursor: NSColor(red: 0.40, green: 0.80, blue: 1.00, alpha: 1.0),
        cursorText: NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
        selection: NSColor(red: 0.30, green: 0.40, blue: 0.55, alpha: 0.5),
        border: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0),
        black: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0),
        red: NSColor(red: 0.90, green: 0.35, blue: 0.35, alpha: 1.0),
        green: NSColor(red: 0.35, green: 0.80, blue: 0.35, alpha: 1.0),
        yellow: NSColor(red: 0.90, green: 0.80, blue: 0.40, alpha: 1.0),
        blue: NSColor(red: 0.40, green: 0.55, blue: 0.90, alpha: 1.0),
        magenta: NSColor(red: 0.75, green: 0.45, blue: 0.85, alpha: 1.0),
        cyan: NSColor(red: 0.40, green: 0.80, blue: 0.85, alpha: 1.0),
        white: NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
        brightBlack: NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1.0),
        brightRed: NSColor(red: 1.00, green: 0.50, blue: 0.50, alpha: 1.0),
        brightGreen: NSColor(red: 0.50, green: 1.00, blue: 0.50, alpha: 1.0),
        brightYellow: NSColor(red: 1.00, green: 0.95, blue: 0.55, alpha: 1.0),
        brightBlue: NSColor(red: 0.55, green: 0.70, blue: 1.00, alpha: 1.0),
        brightMagenta: NSColor(red: 0.90, green: 0.60, blue: 1.00, alpha: 1.0),
        brightCyan: NSColor(red: 0.55, green: 0.95, blue: 1.00, alpha: 1.0),
        brightWhite: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
    )

    static let light = Theme(
        name: "Light",
        background: NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0),
        foreground: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
        cursor: NSColor(red: 0.20, green: 0.50, blue: 0.90, alpha: 1.0),
        cursorText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.70, green: 0.85, blue: 1.00, alpha: 0.5),
        border: NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0),
        black: NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.0),
        red: NSColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1.0),
        green: NSColor(red: 0.15, green: 0.55, blue: 0.15, alpha: 1.0),
        yellow: NSColor(red: 0.65, green: 0.50, blue: 0.10, alpha: 1.0),
        blue: NSColor(red: 0.15, green: 0.30, blue: 0.75, alpha: 1.0),
        magenta: NSColor(red: 0.55, green: 0.20, blue: 0.65, alpha: 1.0),
        cyan: NSColor(red: 0.15, green: 0.55, blue: 0.60, alpha: 1.0),
        white: NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
        brightBlack: NSColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1.0),
        brightRed: NSColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1.0),
        brightGreen: NSColor(red: 0.25, green: 0.70, blue: 0.25, alpha: 1.0),
        brightYellow: NSColor(red: 0.80, green: 0.65, blue: 0.20, alpha: 1.0),
        brightBlue: NSColor(red: 0.30, green: 0.45, blue: 0.90, alpha: 1.0),
        brightMagenta: NSColor(red: 0.70, green: 0.35, blue: 0.80, alpha: 1.0),
        brightCyan: NSColor(red: 0.25, green: 0.70, blue: 0.75, alpha: 1.0),
        brightWhite: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
    )

    static let allThemes: [Theme] = [.v0Dark, .v0Midnight, .v0Aurora, .dark, .light]

    static func named(_ name: String) -> Theme? {
        return allThemes.first { $0.name == name }
    }
}
