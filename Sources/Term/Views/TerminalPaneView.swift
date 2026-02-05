import AppKit
import SwiftTerm

protocol TerminalPaneViewDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: TerminalPaneView)
    func paneDidClose(_ pane: TerminalPaneView)
    func pane(_ pane: TerminalPaneView, didUpdateTitle title: String)
}

class TerminalPaneView: NSView {
    weak var delegate: TerminalPaneViewDelegate?

    private var terminalView: LocalProcessTerminalView!
    private var vibrancyView: NSVisualEffectView?
    private var isActive = false
    private let paneId = UUID().uuidString.prefix(8)

    // Search state
    private var searchMatches: [SearchResult] = []
    private var currentMatchIndex: Int = 0
    private var currentSearchQuery: String = ""

    // URL pattern for detection
    private static let urlPattern = try? NSRegularExpression(
        pattern: "https?://[^\\s\\)\\]\\>\"']+",
        options: [.caseInsensitive]
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        logInfo("Setting up terminal pane \(paneId)", context: "TerminalPane")

        wantsLayer = true

        // Setup vibrancy if enabled
        setupVibrancy()

        // Background color (visible when vibrancy is off)
        layer?.backgroundColor = Settings.shared.theme.background.cgColor

        // Subtle inner shadow / border effect
        layer?.borderWidth = 0.5
        layer?.borderColor = Settings.shared.theme.border.cgColor

        // Создаём терминал
        logDebug("Creating LocalProcessTerminalView", context: "TerminalPane")
        terminalView = LocalProcessTerminalView(frame: bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(terminalView)

        // Constraints with small padding
        let padding: CGFloat = 8
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        ])

        // Настройка
        applySettings()

        // Запуск shell
        startShell()

        // Обработка завершения процесса
        terminalView.processDelegate = self

        // Subscribe to vibrancy changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVibrancyChange),
            name: .vibrancyChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFontChange),
            name: .fontSizeChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFontChange),
            name: .fontChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeChanged,
            object: nil
        )

        logInfo("Terminal pane \(paneId) setup complete", context: "TerminalPane")
    }

    deinit {
        logInfo("Terminal pane \(paneId) deallocated", context: "TerminalPane")
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Vibrancy

    private func setupVibrancy() {
        // Remove existing vibrancy view if any
        vibrancyView?.removeFromSuperview()
        vibrancyView = nil

        guard Settings.shared.vibrancy else {
            logDebug("Vibrancy disabled", context: "TerminalPane")
            layer?.backgroundColor = Settings.shared.theme.background.cgColor
            return
        }

        logDebug("Setting up vibrancy effect", context: "TerminalPane")

        // Create vibrancy view
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true

        // Add as background
        addSubview(visualEffect, positioned: .below, relativeTo: terminalView)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        vibrancyView = visualEffect

        // Make terminal background semi-transparent
        layer?.backgroundColor = Settings.shared.theme.background.withAlphaComponent(0.7).cgColor
    }

    @objc private func handleVibrancyChange() {
        logDebug("Vibrancy setting changed", context: "TerminalPane")
        setupVibrancy()
        updateTheme()
    }

    @objc private func handleFontChange() {
        logDebug("Font changed: \(Settings.shared.fontFamily) \(Settings.shared.fontSize)pt", context: "TerminalPane")
        applyFont()
    }

    @objc private func handleThemeChange() {
        logDebug("Theme changed: \(Settings.shared.theme.name)", context: "TerminalPane")
        updateTheme()
    }

    private func applySettings() {
        let settings = Settings.shared
        let theme = settings.theme

        logDebug("Applying settings: theme=\(theme.name), vibrancy=\(settings.vibrancy)", context: "TerminalPane")

        // Font
        applyFont()

        // v0 style colors
        if settings.vibrancy {
            terminalView.nativeBackgroundColor = theme.background.withAlphaComponent(0.6)
        } else {
            terminalView.nativeBackgroundColor = theme.background
        }
        terminalView.nativeForegroundColor = theme.foreground
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection

        // Apply ANSI colors
        applyAnsiColors(theme)
    }

    private func applyFont() {
        let settings = Settings.shared
        let size = CGFloat(settings.fontSize)

        // Try custom font first
        if let font = NSFont(name: settings.fontFamily, size: size) {
            logDebug("Using font: \(settings.fontFamily)", context: "TerminalPane")
            terminalView.font = font
        } else if let font = NSFont(name: "SF Mono", size: size) {
            logWarning("Font '\(settings.fontFamily)' not found, falling back to SF Mono", context: "TerminalPane")
            terminalView.font = font
        } else {
            logWarning("Falling back to system monospace font", context: "TerminalPane")
            terminalView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    private func applyAnsiColors(_ theme: Theme) {
        let terminal = terminalView.getTerminal()

        let nsColors: [NSColor] = [
            theme.black, theme.red, theme.green, theme.yellow,
            theme.blue, theme.magenta, theme.cyan, theme.white,
            theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
            theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite
        ]

        var colors: [Color] = []
        for nsColor in nsColors {
            if let rgb = nsColor.usingColorSpace(.deviceRGB) {
                let color = Color(
                    red: UInt16(rgb.redComponent * 65535),
                    green: UInt16(rgb.greenComponent * 65535),
                    blue: UInt16(rgb.blueComponent * 65535)
                )
                colors.append(color)
            }
        }

        if colors.count == 16 {
            terminal.installPalette(colors: colors)
            logDebug("ANSI palette installed", context: "TerminalPane")
        } else {
            logError("Failed to create ANSI palette: got \(colors.count) colors", context: "TerminalPane")
        }
    }

    private func startShell() {
        let shell = Settings.shared.shell
        logInfo("Starting shell: \(shell)", context: "TerminalPane")

        let environment = ProcessInfo.processInfo.environment

        var env: [String] = []
        for (key, value) in environment {
            env.append("\(key)=\(value)")
        }

        env.append("TERM=xterm-256color")
        env.append("COLORTERM=truecolor")
        env.append("CLICOLOR=1")
        env.append("CLICOLOR_FORCE=1")

        logDebug("Environment prepared, starting process...", context: "TerminalPane")

        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: env,
            execName: (shell as NSString).lastPathComponent
        )

        logInfo("Shell process started", context: "TerminalPane")
    }

    // MARK: - Public Methods

    func focus() {
        logDebug("Pane \(paneId) focused", context: "TerminalPane")
        isActive = true
        window?.makeFirstResponder(terminalView)
        delegate?.paneDidBecomeActive(self)

        layer?.borderColor = Settings.shared.theme.cursor.withAlphaComponent(0.3).cgColor
    }

    func blur() {
        logDebug("Pane \(paneId) blurred", context: "TerminalPane")
        isActive = false
        layer?.borderColor = Settings.shared.theme.border.cgColor
    }

    func clear() {
        logDebug("Clearing buffer", context: "TerminalPane")
        terminalView.send(txt: "\u{0C}")
    }

    func updateFont() {
        applyFont()
    }

    func updateTheme() {
        let theme = Settings.shared.theme
        let settings = Settings.shared

        if settings.vibrancy {
            layer?.backgroundColor = theme.background.withAlphaComponent(0.7).cgColor
            terminalView.nativeBackgroundColor = theme.background.withAlphaComponent(0.6)
        } else {
            layer?.backgroundColor = theme.background.cgColor
            terminalView.nativeBackgroundColor = theme.background
        }

        layer?.borderColor = isActive ? theme.cursor.withAlphaComponent(0.3).cgColor : theme.border.cgColor

        terminalView.nativeForegroundColor = theme.foreground
        terminalView.caretColor = theme.cursor
        terminalView.selectedTextBackgroundColor = theme.selection

        applyAnsiColors(theme)
    }

    // MARK: - Search

    func search(for query: String) -> (count: Int, current: Int) {
        currentSearchQuery = query

        guard !query.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            return (0, 0)
        }

        let terminal = terminalView.getTerminal()
        searchMatches = terminal.search(for: query, direction: .forward, wrapAround: true)

        if searchMatches.isEmpty {
            currentMatchIndex = 0
            logDebug("Search '\(query)': no matches", context: "TerminalPane")
        } else {
            currentMatchIndex = 0
            scrollToMatch(searchMatches[currentMatchIndex])
            logDebug("Search '\(query)': \(searchMatches.count) matches", context: "TerminalPane")
        }

        return (searchMatches.count, currentMatchIndex)
    }

    func findNext() -> (count: Int, current: Int) {
        guard !searchMatches.isEmpty else {
            return (0, 0)
        }

        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        scrollToMatch(searchMatches[currentMatchIndex])
        return (searchMatches.count, currentMatchIndex)
    }

    func findPrevious() -> (count: Int, current: Int) {
        guard !searchMatches.isEmpty else {
            return (0, 0)
        }

        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        scrollToMatch(searchMatches[currentMatchIndex])
        return (searchMatches.count, currentMatchIndex)
    }

    func clearSearch() {
        searchMatches = []
        currentMatchIndex = 0
        currentSearchQuery = ""
    }

    private func scrollToMatch(_ match: SearchResult) {
        let terminal = terminalView.getTerminal()
        terminal.scroll(toLine: match.startLocation.row)
    }

    // MARK: - URL Detection

    private func detectURLAtPoint(_ point: NSPoint) -> URL? {
        let terminal = terminalView.getTerminal()
        let localPoint = terminalView.convert(point, from: self)

        // Get character position from point
        guard let (col, row) = terminalView.getPosition(forPoint: localPoint) else {
            return nil
        }

        // Get the line content
        guard row >= 0, row < terminal.rows else {
            return nil
        }

        let line = terminal.getLine(row: row)
        let lineText = line?.getString() ?? ""

        // Find URLs in the line
        guard let urlPattern = Self.urlPattern else { return nil }
        let range = NSRange(lineText.startIndex..., in: lineText)
        let matches = urlPattern.matches(in: lineText, options: [], range: range)

        // Check if click is on a URL
        for match in matches {
            guard let urlRange = Range(match.range, in: lineText) else { continue }
            let startCol = lineText.distance(from: lineText.startIndex, to: urlRange.lowerBound)
            let endCol = lineText.distance(from: lineText.startIndex, to: urlRange.upperBound)

            if col >= startCol && col < endCol {
                let urlString = String(lineText[urlRange])
                return URL(string: urlString)
            }
        }

        return nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Cmd+click = open URL
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            if let url = detectURLAtPoint(point) {
                logInfo("Opening URL: \(url)", context: "TerminalPane")
                NSWorkspace.shared.open(url)
                return
            }
        }

        super.mouseDown(with: event)
        focus()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalPaneView: LocalProcessTerminalViewDelegate {
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        logInfo("Shell process terminated with exit code: \(exitCode ?? -1)", context: "TerminalPane")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.paneDidClose(self)
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        logDebug("Terminal size changed: \(newCols)x\(newRows)", context: "TerminalPane")
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        logDebug("Terminal title changed: \(title)", context: "TerminalPane")
        delegate?.pane(self, didUpdateTitle: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            logDebug("Current directory: \(dir)", context: "TerminalPane")
        }
    }
}
