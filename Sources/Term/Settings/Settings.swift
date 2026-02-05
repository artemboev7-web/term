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

    var theme: Theme = .dark {
        didSet {
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = true

    var scrollbackLines: Int = 10000

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
    }

    func save() {
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(shell, forKey: "shell")
        defaults.set(theme.name, forKey: "theme")
        defaults.set(cursorBlink, forKey: "cursorBlink")
        defaults.set(scrollbackLines, forKey: "scrollbackLines")
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
    let selection: NSColor

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

    // MARK: - Built-in Themes

    static let dark = Theme(
        name: "Dark",
        background: NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        foreground: NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
        cursor: NSColor(red: 0.40, green: 0.80, blue: 1.00, alpha: 1.0),
        selection: NSColor(red: 0.30, green: 0.40, blue: 0.55, alpha: 0.5),
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
        selection: NSColor(red: 0.70, green: 0.85, blue: 1.00, alpha: 0.5),
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

    static let allThemes: [Theme] = [.dark, .light]

    static func named(_ name: String) -> Theme? {
        return allThemes.first { $0.name == name }
    }
}
