import AppKit

class Settings {
    static let shared = Settings()

    // MARK: - Appearance

    var fontSize: Int = 14 {
        didSet {
            NotificationCenter.default.post(name: .fontSizeChanged, object: nil)
        }
    }

    var fontFamily: String = "SF Mono" {
        didSet {
            NotificationCenter.default.post(name: .fontChanged, object: nil)
        }
    }

    var theme: Theme = .v0Dark {
        didSet {
            NotificationCenter.default.post(name: .themeChanged, object: nil)
        }
    }

    var vibrancy: Bool = true {
        didSet {
            NotificationCenter.default.post(name: .vibrancyChanged, object: nil)
        }
    }

    var windowOpacity: Double = 0.92

    // MARK: - Shell

    var shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    // MARK: - Cursor

    var cursorStyle: CursorStyle = .block
    var cursorBlink: Bool = true

    // MARK: - Buffer

    var scrollbackLines: Int = 10000

    // MARK: - Available Fonts

    static let availableFonts: [(name: String, displayName: String)] = [
        ("SF Mono", "SF Mono"),
        ("JetBrains Mono", "JetBrains Mono"),
        ("Fira Code", "Fira Code"),
        ("Source Code Pro", "Source Code Pro"),
        ("Menlo", "Menlo"),
        ("Monaco", "Monaco"),
        ("Hack", "Hack"),
        ("Consolas", "Consolas"),
        ("IBM Plex Mono", "IBM Plex Mono"),
        ("Cascadia Code", "Cascadia Code")
    ]

    // MARK: - Persistence

    private let defaults = UserDefaults.standard

    func load() {
        logInfo("Loading settings from UserDefaults", context: "Settings")

        fontSize = defaults.integer(forKey: "fontSize")
        if fontSize == 0 { fontSize = 14 }

        if let family = defaults.string(forKey: "fontFamily"), !family.isEmpty {
            fontFamily = family
        }

        if let themeName = defaults.string(forKey: "theme"),
           let loadedTheme = Theme.named(themeName) {
            theme = loadedTheme
        }

        // Vibrancy по умолчанию включён
        if defaults.object(forKey: "vibrancy") != nil {
            vibrancy = defaults.bool(forKey: "vibrancy")
        }

        windowOpacity = defaults.double(forKey: "windowOpacity")
        if windowOpacity == 0 { windowOpacity = 0.92 }

        if let shellPath = defaults.string(forKey: "shell"), !shellPath.isEmpty {
            shell = shellPath
        }

        cursorBlink = defaults.bool(forKey: "cursorBlink")

        scrollbackLines = defaults.integer(forKey: "scrollbackLines")
        if scrollbackLines == 0 { scrollbackLines = 10000 }

        logInfo("Settings loaded: theme=\(theme.name), font=\(fontFamily) \(fontSize)pt, vibrancy=\(vibrancy), shell=\(shell)", context: "Settings")
    }

    func save() {
        logInfo("Saving settings to UserDefaults", context: "Settings")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(fontFamily, forKey: "fontFamily")
        defaults.set(theme.name, forKey: "theme")
        defaults.set(vibrancy, forKey: "vibrancy")
        defaults.set(windowOpacity, forKey: "windowOpacity")
        defaults.set(shell, forKey: "shell")
        defaults.set(cursorBlink, forKey: "cursorBlink")
        defaults.set(scrollbackLines, forKey: "scrollbackLines")
        logDebug("Settings saved successfully", context: "Settings")
    }
}

// MARK: - Cursor Style

enum CursorStyle: String, CaseIterable {
    case block = "Block"
    case underline = "Underline"
    case bar = "Bar"
}

// MARK: - Notifications

extension Notification.Name {
    static let fontSizeChanged = Notification.Name("fontSizeChanged")
    static let fontChanged = Notification.Name("fontChanged")
    static let themeChanged = Notification.Name("themeChanged")
    static let vibrancyChanged = Notification.Name("vibrancyChanged")
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

    // MARK: - v0.app Style Themes

    static let v0Dark = Theme(
        name: "v0 Dark",
        background: NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0),
        foreground: NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0),
        cursor: NSColor(red: 0.55, green: 0.36, blue: 1.0, alpha: 1.0),
        cursorText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        selection: NSColor(red: 0.35, green: 0.25, blue: 0.55, alpha: 0.4),
        border: NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),
        black: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        red: NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0),
        green: NSColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1.0),
        yellow: NSColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1.0),
        blue: NSColor(red: 0.40, green: 0.60, blue: 1.0, alpha: 1.0),
        magenta: NSColor(red: 0.75, green: 0.45, blue: 1.0, alpha: 1.0),
        cyan: NSColor(red: 0.30, green: 0.85, blue: 0.90, alpha: 1.0),
        white: NSColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1.0),
        brightBlack: NSColor(red: 0.40, green: 0.40, blue: 0.45, alpha: 1.0),
        brightRed: NSColor(red: 1.0, green: 0.50, blue: 0.55, alpha: 1.0),
        brightGreen: NSColor(red: 0.45, green: 1.0, blue: 0.65, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 0.92, blue: 0.50, alpha: 1.0),
        brightBlue: NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 0.85, green: 0.60, blue: 1.0, alpha: 1.0),
        brightCyan: NSColor(red: 0.50, green: 1.0, blue: 0.95, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    static let v0Midnight = Theme(
        name: "v0 Midnight",
        background: NSColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1.0),
        foreground: NSColor(red: 0.88, green: 0.88, blue: 0.92, alpha: 1.0),
        cursor: NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1.0),
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

    // MARK: - Dracula

    static let dracula = Theme(
        name: "Dracula",
        background: NSColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1.0),  // #282a36
        foreground: NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0),  // #f8f8f2
        cursor: NSColor(red: 0.94, green: 0.47, blue: 0.66, alpha: 1.0),      // #ff79c6
        cursorText: NSColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1.0),
        selection: NSColor(red: 0.27, green: 0.28, blue: 0.35, alpha: 0.8),   // #44475a
        border: NSColor(red: 0.27, green: 0.28, blue: 0.35, alpha: 1.0),
        black: NSColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1.0),       // #21222c
        red: NSColor(red: 1.0, green: 0.33, blue: 0.33, alpha: 1.0),          // #ff5555
        green: NSColor(red: 0.31, green: 0.98, blue: 0.48, alpha: 1.0),       // #50fa7b
        yellow: NSColor(red: 0.95, green: 0.98, blue: 0.48, alpha: 1.0),      // #f1fa8c
        blue: NSColor(red: 0.74, green: 0.58, blue: 0.98, alpha: 1.0),        // #bd93f9
        magenta: NSColor(red: 0.94, green: 0.47, blue: 0.66, alpha: 1.0),     // #ff79c6
        cyan: NSColor(red: 0.54, green: 0.98, blue: 0.98, alpha: 1.0),        // #8be9fd
        white: NSColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1.0),       // #f8f8f2
        brightBlack: NSColor(red: 0.38, green: 0.40, blue: 0.50, alpha: 1.0), // #6272a4
        brightRed: NSColor(red: 1.0, green: 0.43, blue: 0.43, alpha: 1.0),
        brightGreen: NSColor(red: 0.41, green: 1.0, blue: 0.58, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 1.0),
        brightBlue: NSColor(red: 0.84, green: 0.68, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 1.0, green: 0.57, blue: 0.76, alpha: 1.0),
        brightCyan: NSColor(red: 0.64, green: 1.0, blue: 1.0, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    // MARK: - Nord

    static let nord = Theme(
        name: "Nord",
        background: NSColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1.0),  // #2e3440
        foreground: NSColor(red: 0.85, green: 0.87, blue: 0.91, alpha: 1.0),  // #d8dee9
        cursor: NSColor(red: 0.53, green: 0.75, blue: 0.82, alpha: 1.0),      // #88c0d0
        cursorText: NSColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 1.0),
        selection: NSColor(red: 0.26, green: 0.30, blue: 0.37, alpha: 0.8),   // #434c5e
        border: NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1.0),      // #3b4252
        black: NSColor(red: 0.23, green: 0.26, blue: 0.32, alpha: 1.0),       // #3b4252
        red: NSColor(red: 0.75, green: 0.38, blue: 0.42, alpha: 1.0),         // #bf616a
        green: NSColor(red: 0.64, green: 0.75, blue: 0.55, alpha: 1.0),       // #a3be8c
        yellow: NSColor(red: 0.92, green: 0.80, blue: 0.55, alpha: 1.0),      // #ebcb8b
        blue: NSColor(red: 0.51, green: 0.63, blue: 0.76, alpha: 1.0),        // #81a1c1
        magenta: NSColor(red: 0.71, green: 0.56, blue: 0.68, alpha: 1.0),     // #b48ead
        cyan: NSColor(red: 0.53, green: 0.75, blue: 0.82, alpha: 1.0),        // #88c0d0
        white: NSColor(red: 0.90, green: 0.91, blue: 0.94, alpha: 1.0),       // #e5e9f0
        brightBlack: NSColor(red: 0.30, green: 0.34, blue: 0.42, alpha: 1.0), // #4c566a
        brightRed: NSColor(red: 0.75, green: 0.38, blue: 0.42, alpha: 1.0),
        brightGreen: NSColor(red: 0.64, green: 0.75, blue: 0.55, alpha: 1.0),
        brightYellow: NSColor(red: 0.92, green: 0.80, blue: 0.55, alpha: 1.0),
        brightBlue: NSColor(red: 0.51, green: 0.63, blue: 0.76, alpha: 1.0),
        brightMagenta: NSColor(red: 0.71, green: 0.56, blue: 0.68, alpha: 1.0),
        brightCyan: NSColor(red: 0.56, green: 0.74, blue: 0.73, alpha: 1.0),  // #8fbcbb
        brightWhite: NSColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)  // #eceff4
    )

    // MARK: - Catppuccin Mocha

    static let catppuccin = Theme(
        name: "Catppuccin",
        background: NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0),  // #1e1e2e
        foreground: NSColor(red: 0.80, green: 0.84, blue: 0.96, alpha: 1.0),  // #cdd6f4
        cursor: NSColor(red: 0.95, green: 0.55, blue: 0.66, alpha: 1.0),      // #f38ba8
        cursorText: NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0),
        selection: NSColor(red: 0.27, green: 0.28, blue: 0.35, alpha: 0.7),   // #45475a
        border: NSColor(red: 0.19, green: 0.20, blue: 0.27, alpha: 1.0),      // #313244
        black: NSColor(red: 0.27, green: 0.28, blue: 0.35, alpha: 1.0),       // #45475a
        red: NSColor(red: 0.95, green: 0.55, blue: 0.66, alpha: 1.0),         // #f38ba8
        green: NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 1.0),       // #a6e3a1
        yellow: NSColor(red: 0.98, green: 0.90, blue: 0.59, alpha: 1.0),      // #f9e2af
        blue: NSColor(red: 0.54, green: 0.71, blue: 0.98, alpha: 1.0),        // #89b4fa
        magenta: NSColor(red: 0.80, green: 0.62, blue: 0.96, alpha: 1.0),     // #cba6f7
        cyan: NSColor(red: 0.58, green: 0.89, blue: 0.84, alpha: 1.0),        // #94e2d5
        white: NSColor(red: 0.73, green: 0.75, blue: 0.85, alpha: 1.0),       // #bac2de
        brightBlack: NSColor(red: 0.35, green: 0.36, blue: 0.44, alpha: 1.0), // #585b70
        brightRed: NSColor(red: 0.95, green: 0.55, blue: 0.66, alpha: 1.0),
        brightGreen: NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 1.0),
        brightYellow: NSColor(red: 0.98, green: 0.90, blue: 0.59, alpha: 1.0),
        brightBlue: NSColor(red: 0.54, green: 0.71, blue: 0.98, alpha: 1.0),
        brightMagenta: NSColor(red: 0.80, green: 0.62, blue: 0.96, alpha: 1.0),
        brightCyan: NSColor(red: 0.58, green: 0.89, blue: 0.84, alpha: 1.0),
        brightWhite: NSColor(red: 0.65, green: 0.89, blue: 0.93, alpha: 1.0)  // #a6e3ef
    )

    // MARK: - Solarized Dark

    static let solarizedDark = Theme(
        name: "Solarized Dark",
        background: NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0),   // #002b36
        foreground: NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0),  // #839496
        cursor: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1.0),      // #268bd2
        cursorText: NSColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1.0),
        selection: NSColor(red: 0.03, green: 0.21, blue: 0.26, alpha: 0.8),   // #073642
        border: NSColor(red: 0.03, green: 0.21, blue: 0.26, alpha: 1.0),
        black: NSColor(red: 0.03, green: 0.21, blue: 0.26, alpha: 1.0),       // #073642
        red: NSColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1.0),         // #dc322f
        green: NSColor(red: 0.52, green: 0.60, blue: 0.0, alpha: 1.0),        // #859900
        yellow: NSColor(red: 0.71, green: 0.54, blue: 0.0, alpha: 1.0),       // #b58900
        blue: NSColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1.0),        // #268bd2
        magenta: NSColor(red: 0.83, green: 0.21, blue: 0.51, alpha: 1.0),     // #d33682
        cyan: NSColor(red: 0.16, green: 0.63, blue: 0.60, alpha: 1.0),        // #2aa198
        white: NSColor(red: 0.93, green: 0.91, blue: 0.84, alpha: 1.0),       // #eee8d5
        brightBlack: NSColor(red: 0.0, green: 0.27, blue: 0.33, alpha: 1.0),  // #002b36
        brightRed: NSColor(red: 0.80, green: 0.29, blue: 0.09, alpha: 1.0),   // #cb4b16
        brightGreen: NSColor(red: 0.35, green: 0.43, blue: 0.46, alpha: 1.0), // #586e75
        brightYellow: NSColor(red: 0.40, green: 0.48, blue: 0.51, alpha: 1.0),// #657b83
        brightBlue: NSColor(red: 0.51, green: 0.58, blue: 0.59, alpha: 1.0),  // #839496
        brightMagenta: NSColor(red: 0.42, green: 0.44, blue: 0.77, alpha: 1.0),// #6c71c4
        brightCyan: NSColor(red: 0.58, green: 0.63, blue: 0.63, alpha: 1.0),  // #93a1a1
        brightWhite: NSColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1.0)  // #fdf6e3
    )

    // MARK: - Tokyo Night

    static let tokyoNight = Theme(
        name: "Tokyo Night",
        background: NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1.0),  // #1a1b26
        foreground: NSColor(red: 0.66, green: 0.70, blue: 0.84, alpha: 1.0),  // #a9b1d6
        cursor: NSColor(red: 0.47, green: 0.51, blue: 0.69, alpha: 1.0),      // #7982b4
        cursorText: NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1.0),
        selection: NSColor(red: 0.21, green: 0.22, blue: 0.29, alpha: 0.8),   // #33467c
        border: NSColor(red: 0.15, green: 0.16, blue: 0.21, alpha: 1.0),
        black: NSColor(red: 0.09, green: 0.09, blue: 0.13, alpha: 1.0),       // #15161e
        red: NSColor(red: 0.97, green: 0.51, blue: 0.56, alpha: 1.0),         // #f7768e
        green: NSColor(red: 0.45, green: 0.85, blue: 0.62, alpha: 1.0),       // #73daca
        yellow: NSColor(red: 0.88, green: 0.77, blue: 0.49, alpha: 1.0),      // #e0af68
        blue: NSColor(red: 0.48, green: 0.65, blue: 0.93, alpha: 1.0),        // #7aa2f7
        magenta: NSColor(red: 0.73, green: 0.52, blue: 0.90, alpha: 1.0),     // #bb9af7
        cyan: NSColor(red: 0.49, green: 0.84, blue: 0.87, alpha: 1.0),        // #7dcfff
        white: NSColor(red: 0.66, green: 0.70, blue: 0.84, alpha: 1.0),       // #a9b1d6
        brightBlack: NSColor(red: 0.27, green: 0.28, blue: 0.35, alpha: 1.0), // #444b6a
        brightRed: NSColor(red: 1.0, green: 0.61, blue: 0.66, alpha: 1.0),
        brightGreen: NSColor(red: 0.55, green: 0.95, blue: 0.72, alpha: 1.0),
        brightYellow: NSColor(red: 0.98, green: 0.87, blue: 0.59, alpha: 1.0),
        brightBlue: NSColor(red: 0.58, green: 0.75, blue: 1.0, alpha: 1.0),
        brightMagenta: NSColor(red: 0.83, green: 0.62, blue: 1.0, alpha: 1.0),
        brightCyan: NSColor(red: 0.59, green: 0.94, blue: 0.97, alpha: 1.0),
        brightWhite: NSColor(red: 0.76, green: 0.80, blue: 0.94, alpha: 1.0)
    )

    // MARK: - Gruvbox Dark

    static let gruvbox = Theme(
        name: "Gruvbox",
        background: NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1.0),  // #282828
        foreground: NSColor(red: 0.92, green: 0.86, blue: 0.70, alpha: 1.0),  // #ebdbb2
        cursor: NSColor(red: 0.92, green: 0.86, blue: 0.70, alpha: 1.0),
        cursorText: NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1.0),
        selection: NSColor(red: 0.26, green: 0.25, blue: 0.22, alpha: 0.8),   // #3c3836
        border: NSColor(red: 0.20, green: 0.19, blue: 0.17, alpha: 1.0),
        black: NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1.0),       // #282828
        red: NSColor(red: 0.80, green: 0.14, blue: 0.11, alpha: 1.0),         // #cc241d
        green: NSColor(red: 0.60, green: 0.59, blue: 0.10, alpha: 1.0),       // #98971a
        yellow: NSColor(red: 0.84, green: 0.60, blue: 0.13, alpha: 1.0),      // #d79921
        blue: NSColor(red: 0.27, green: 0.52, blue: 0.53, alpha: 1.0),        // #458588
        magenta: NSColor(red: 0.69, green: 0.38, blue: 0.53, alpha: 1.0),     // #b16286
        cyan: NSColor(red: 0.41, green: 0.62, blue: 0.42, alpha: 1.0),        // #689d6a
        white: NSColor(red: 0.66, green: 0.60, blue: 0.52, alpha: 1.0),       // #a89984
        brightBlack: NSColor(red: 0.57, green: 0.51, blue: 0.45, alpha: 1.0), // #928374
        brightRed: NSColor(red: 0.98, green: 0.29, blue: 0.20, alpha: 1.0),   // #fb4934
        brightGreen: NSColor(red: 0.72, green: 0.73, blue: 0.15, alpha: 1.0), // #b8bb26
        brightYellow: NSColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1.0),// #fabd2f
        brightBlue: NSColor(red: 0.51, green: 0.65, blue: 0.60, alpha: 1.0),  // #83a598
        brightMagenta: NSColor(red: 0.83, green: 0.53, blue: 0.64, alpha: 1.0),// #d3869b
        brightCyan: NSColor(red: 0.56, green: 0.75, blue: 0.49, alpha: 1.0),  // #8ec07c
        brightWhite: NSColor(red: 0.92, green: 0.86, blue: 0.70, alpha: 1.0)  // #ebdbb2
    )

    // MARK: - One Dark

    static let oneDark = Theme(
        name: "One Dark",
        background: NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0),  // #282c34
        foreground: NSColor(red: 0.67, green: 0.72, blue: 0.78, alpha: 1.0),  // #abb2bf
        cursor: NSColor(red: 0.53, green: 0.60, blue: 0.74, alpha: 1.0),      // #528bff
        cursorText: NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1.0),
        selection: NSColor(red: 0.24, green: 0.26, blue: 0.31, alpha: 0.8),   // #3e4451
        border: NSColor(red: 0.21, green: 0.22, blue: 0.25, alpha: 1.0),
        black: NSColor(red: 0.19, green: 0.20, blue: 0.24, alpha: 1.0),       // #31343f
        red: NSColor(red: 0.88, green: 0.36, blue: 0.36, alpha: 1.0),         // #e06c75
        green: NSColor(red: 0.60, green: 0.77, blue: 0.46, alpha: 1.0),       // #98c379
        yellow: NSColor(red: 0.90, green: 0.78, blue: 0.51, alpha: 1.0),      // #e5c07b
        blue: NSColor(red: 0.38, green: 0.58, blue: 0.89, alpha: 1.0),        // #61afef
        magenta: NSColor(red: 0.78, green: 0.47, blue: 0.82, alpha: 1.0),     // #c678dd
        cyan: NSColor(red: 0.34, green: 0.71, blue: 0.73, alpha: 1.0),        // #56b6c2
        white: NSColor(red: 0.67, green: 0.72, blue: 0.78, alpha: 1.0),       // #abb2bf
        brightBlack: NSColor(red: 0.33, green: 0.37, blue: 0.44, alpha: 1.0), // #545862
        brightRed: NSColor(red: 0.88, green: 0.36, blue: 0.36, alpha: 1.0),
        brightGreen: NSColor(red: 0.60, green: 0.77, blue: 0.46, alpha: 1.0),
        brightYellow: NSColor(red: 0.90, green: 0.78, blue: 0.51, alpha: 1.0),
        brightBlue: NSColor(red: 0.38, green: 0.58, blue: 0.89, alpha: 1.0),
        brightMagenta: NSColor(red: 0.78, green: 0.47, blue: 0.82, alpha: 1.0),
        brightCyan: NSColor(red: 0.34, green: 0.71, blue: 0.73, alpha: 1.0),
        brightWhite: NSColor(red: 0.76, green: 0.80, blue: 0.85, alpha: 1.0)
    )

    // MARK: - Monokai Pro

    static let monokai = Theme(
        name: "Monokai",
        background: NSColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1.0),  // #2d2a2e
        foreground: NSColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1.0),  // #fcfcfa
        cursor: NSColor(red: 1.0, green: 0.84, blue: 0.26, alpha: 1.0),       // #ffd866
        cursorText: NSColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1.0),
        selection: NSColor(red: 0.27, green: 0.27, blue: 0.26, alpha: 0.8),   // #403e41
        border: NSColor(red: 0.22, green: 0.22, blue: 0.21, alpha: 1.0),
        black: NSColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1.0),       // #2d2a2e
        red: NSColor(red: 1.0, green: 0.38, blue: 0.42, alpha: 1.0),          // #ff6188
        green: NSColor(red: 0.66, green: 0.89, blue: 0.34, alpha: 1.0),       // #a9dc76
        yellow: NSColor(red: 1.0, green: 0.84, blue: 0.26, alpha: 1.0),       // #ffd866
        blue: NSColor(red: 0.47, green: 0.77, blue: 0.99, alpha: 1.0),        // #78dce8
        magenta: NSColor(red: 0.67, green: 0.51, blue: 1.0, alpha: 1.0),      // #ab9df2
        cyan: NSColor(red: 0.47, green: 0.77, blue: 0.99, alpha: 1.0),        // #78dce8
        white: NSColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1.0),       // #fcfcfa
        brightBlack: NSColor(red: 0.45, green: 0.44, blue: 0.45, alpha: 1.0), // #727072
        brightRed: NSColor(red: 1.0, green: 0.38, blue: 0.42, alpha: 1.0),
        brightGreen: NSColor(red: 0.66, green: 0.89, blue: 0.34, alpha: 1.0),
        brightYellow: NSColor(red: 1.0, green: 0.84, blue: 0.26, alpha: 1.0),
        brightBlue: NSColor(red: 0.47, green: 0.77, blue: 0.99, alpha: 1.0),
        brightMagenta: NSColor(red: 0.67, green: 0.51, blue: 1.0, alpha: 1.0),
        brightCyan: NSColor(red: 0.47, green: 0.77, blue: 0.99, alpha: 1.0),
        brightWhite: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    )

    // MARK: - Rosé Pine

    static let rosePine = Theme(
        name: "Rosé Pine",
        background: NSColor(red: 0.10, green: 0.09, blue: 0.13, alpha: 1.0),  // #191724
        foreground: NSColor(red: 0.88, green: 0.85, blue: 0.91, alpha: 1.0),  // #e0def4
        cursor: NSColor(red: 0.92, green: 0.74, blue: 0.73, alpha: 1.0),      // #ebbcba
        cursorText: NSColor(red: 0.10, green: 0.09, blue: 0.13, alpha: 1.0),
        selection: NSColor(red: 0.24, green: 0.21, blue: 0.34, alpha: 0.8),   // #403d52
        border: NSColor(red: 0.15, green: 0.14, blue: 0.20, alpha: 1.0),
        black: NSColor(red: 0.15, green: 0.14, blue: 0.20, alpha: 1.0),       // #26233a
        red: NSColor(red: 0.92, green: 0.55, blue: 0.58, alpha: 1.0),         // #eb6f92
        green: NSColor(red: 0.62, green: 0.80, blue: 0.63, alpha: 1.0),       // #9ccfd8 (pine)
        yellow: NSColor(red: 0.95, green: 0.76, blue: 0.55, alpha: 1.0),      // #f6c177
        blue: NSColor(red: 0.62, green: 0.53, blue: 0.78, alpha: 1.0),        // #c4a7e7 (iris)
        magenta: NSColor(red: 0.77, green: 0.65, blue: 0.82, alpha: 1.0),     // #c4a7e7
        cyan: NSColor(red: 0.61, green: 0.81, blue: 0.85, alpha: 1.0),        // #9ccfd8
        white: NSColor(red: 0.88, green: 0.85, blue: 0.91, alpha: 1.0),       // #e0def4
        brightBlack: NSColor(red: 0.43, green: 0.40, blue: 0.52, alpha: 1.0), // #6e6a86
        brightRed: NSColor(red: 0.92, green: 0.55, blue: 0.58, alpha: 1.0),
        brightGreen: NSColor(red: 0.62, green: 0.80, blue: 0.63, alpha: 1.0),
        brightYellow: NSColor(red: 0.95, green: 0.76, blue: 0.55, alpha: 1.0),
        brightBlue: NSColor(red: 0.62, green: 0.53, blue: 0.78, alpha: 1.0),
        brightMagenta: NSColor(red: 0.77, green: 0.65, blue: 0.82, alpha: 1.0),
        brightCyan: NSColor(red: 0.61, green: 0.81, blue: 0.85, alpha: 1.0),
        brightWhite: NSColor(red: 0.88, green: 0.85, blue: 0.91, alpha: 1.0)
    )

    static let allThemes: [Theme] = [
        .v0Dark, .v0Midnight, .dracula, .nord, .catppuccin,
        .tokyoNight, .gruvbox, .oneDark, .solarizedDark, .monokai, .rosePine
    ]

    static func named(_ name: String) -> Theme? {
        return allThemes.first { $0.name == name }
    }
}
