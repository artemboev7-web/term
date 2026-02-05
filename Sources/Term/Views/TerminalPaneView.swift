import AppKit

protocol TerminalPaneViewDelegate: AnyObject {
    func paneDidBecomeActive(_ pane: TerminalPaneView)
    func paneDidClose(_ pane: TerminalPaneView)
    func pane(_ pane: TerminalPaneView, didUpdateTitle title: String)
}

// Custom search match result
struct SearchMatch {
    let row: Int
    let column: Int
    let length: Int
}

class TerminalPaneView: NSView, TerminalEmulatorDelegate, PTYManagerDelegate {
    weak var delegate: TerminalPaneViewDelegate?

    // Our custom terminal emulator
    private var terminal: TerminalEmulator!
    private var ptyManager: PTYManager!
    private var inputHandler: InputHandler!

    // Metal rendering
    private var metalView: MetalTerminalView?
    private var vibrancyView: NSVisualEffectView?

    private var isActive = false
    private let paneId = UUID().uuidString.prefix(8)

    // Search state
    private var searchMatches: [SearchMatch] = []
    private var currentMatchIndex: Int = 0
    private var currentSearchQuery: String = ""

    // Cell size for font calculations
    private var cellSize: NSSize = NSSize(width: 8, height: 16)

    // URL pattern for detection
    private static let urlPattern = try? NSRegularExpression(
        pattern: "https?://[^\\s\\)\\]\\>\"']+",
        options: [.caseInsensitive]
    )

    // MARK: - Initialization

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

        // Background color
        layer?.backgroundColor = Settings.shared.theme.background.cgColor

        // Border
        layer?.borderWidth = 0.5
        layer?.borderColor = Settings.shared.theme.border.cgColor

        // Create terminal emulator with default size (will resize later)
        let cols = 80
        let rows = 24
        terminal = TerminalEmulator(cols: cols, rows: rows)
        terminal.delegate = self

        // Create PTY manager
        let shell = Settings.shared.shell
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        ptyManager = PTYManager(shell: shell, workingDirectory: homeDir)
        ptyManager.delegate = self

        // Create input handler
        inputHandler = InputHandler()
        inputHandler.ptyManager = ptyManager

        // Setup Metal view
        setupMetalView()

        // Apply settings
        applySettings()

        // Start shell
        startShell()

        // Subscribe to notifications
        setupNotifications()

        logInfo("Terminal pane \(paneId) setup complete", context: "TerminalPane")
    }

    deinit {
        ptyManager.stop()
        metalView?.pauseRendering()
        NotificationCenter.default.removeObserver(self)
        logDebug("Terminal pane \(paneId) deallocated", context: "TerminalPane")
    }

    // MARK: - Setup

    private func setupVibrancy() {
        if Settings.shared.vibrancy {
            logDebug("Vibrancy enabled", context: "TerminalPane")
            let vibrancy = NSVisualEffectView(frame: bounds)
            vibrancy.blendingMode = .behindWindow
            vibrancy.material = .sidebar
            vibrancy.state = .active
            vibrancy.translatesAutoresizingMaskIntoConstraints = false
            addSubview(vibrancy)
            NSLayoutConstraint.activate([
                vibrancy.topAnchor.constraint(equalTo: topAnchor),
                vibrancy.bottomAnchor.constraint(equalTo: bottomAnchor),
                vibrancy.leadingAnchor.constraint(equalTo: leadingAnchor),
                vibrancy.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            vibrancyView = vibrancy
        } else {
            logDebug("Vibrancy disabled", context: "TerminalPane")
        }
    }

    private func setupMetalView() {
        guard let metalView = MetalTerminalView(frame: bounds, terminal: terminal) else {
            logError("Failed to create MetalTerminalView", context: "TerminalPane")
            return
        }

        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)

        let padding: CGFloat = 8
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        ])

        self.metalView = metalView
        logInfo("Metal renderer initialized for pane \(paneId)", context: "TerminalPane")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vibrancyChanged),
            name: .vibrancyChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontChanged),
            name: .fontChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontSizeChanged),
            name: .fontSizeChanged,
            object: nil
        )
    }

    // MARK: - Shell

    private func startShell() {
        let shell = Settings.shared.shell
        logInfo("Starting shell: \(shell)", context: "TerminalPane")

        if ptyManager.start() {
            ptyManager.resize(cols: terminal.cols, rows: terminal.rows)
            logInfo("Shell process started", context: "TerminalPane")
        } else {
            logError("Failed to start shell", context: "TerminalPane")
        }
    }

    // MARK: - Settings

    func applySettings() {
        logDebug("Applying settings", context: "TerminalPane")

        // Apply theme
        let theme = Settings.shared.theme
        layer?.backgroundColor = theme.background.cgColor
        layer?.borderColor = theme.border.cgColor
        metalView?.applyTheme(theme)

        // Apply font
        applyFont()

        // Apply cursor settings
        metalView?.applySettings()
    }

    private func applyFont() {
        let settings = Settings.shared
        let size = CGFloat(settings.fontSize)

        let font: NSFont
        if let f = NSFont(name: settings.fontFamily, size: size) {
            font = f
        } else if let f = NSFont(name: "SF Mono", size: size) {
            logWarning("Falling back to SF Mono font", context: "TerminalPane")
            font = f
        } else {
            logWarning("Falling back to system monospace font", context: "TerminalPane")
            font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }

        metalView?.setFont(font)
    }

    // MARK: - Resize

    override func layout() {
        super.layout()
        updateTerminalSize()
    }

    private func updateTerminalSize() {
        guard let metalView = metalView else { return }

        // Calculate cell size from font
        let settings = Settings.shared
        let size = CGFloat(settings.fontSize)
        let font = NSFont(name: settings.fontFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)

        let fontAttributes = [NSAttributedString.Key.font: font]
        let charSize = NSString("W").size(withAttributes: fontAttributes)

        let padding: CGFloat = 8
        let contentWidth = bounds.width - (padding * 2)
        let contentHeight = bounds.height - (padding * 2)

        let cols = max(1, Int(contentWidth / charSize.width))
        let rows = max(1, Int(contentHeight / charSize.height))

        if cols != terminal.cols || rows != terminal.rows {
            logDebug("Terminal size changed: \(cols)x\(rows)", context: "TerminalPane")
            terminal.resize(cols: cols, rows: rows)
            ptyManager.resize(cols: cols, rows: rows)
            metalView.markAllDirty()
        }
    }

    // MARK: - Notifications

    @objc private func vibrancyChanged() {
        let enabled = Settings.shared.vibrancy

        if enabled && vibrancyView == nil {
            setupVibrancy()
        } else if !enabled, let v = vibrancyView {
            v.removeFromSuperview()
            vibrancyView = nil
        }
    }

    @objc private func themeChanged() {
        let theme = Settings.shared.theme
        layer?.backgroundColor = theme.background.cgColor
        layer?.borderColor = theme.border.cgColor
        metalView?.applyTheme(theme)
    }

    @objc private func fontChanged() {
        applyFont()
        updateTerminalSize()
    }

    @objc private func fontSizeChanged() {
        applyFont()
        updateTerminalSize()
    }

    // MARK: - Focus

    func focus() {
        window?.makeFirstResponder(self)
        isActive = true
        delegate?.paneDidBecomeActive(self)
        logDebug("Pane \(paneId) focused", context: "TerminalPane")
    }

    // MARK: - Keyboard Input

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        inputHandler.handleKeyDown(event)
    }

    // Handle command key shortcuts
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers {
        case "c":
            if metalView?.selectionManager.isActive == true {
                copy(self)
                return true
            }
            // Otherwise send Ctrl-C
            inputHandler.ptyManager?.write(Data([0x03]))
            return true

        case "v":
            paste(self)
            return true

        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        focus()

        let point = convert(event.locationInWindow, from: nil)
        let (row, col) = cellPosition(at: point)

        // Start selection
        metalView?.selectionManager.startSelection(row: row, col: col)
        metalView?.markAllDirty()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let (row, col) = cellPosition(at: point)

        // Update selection
        metalView?.selectionManager.updateSelection(row: row, col: col)
        metalView?.markAllDirty()
    }

    override func mouseUp(with event: NSEvent) {
        metalView?.selectionManager.endSelection()
    }

    override func scrollWheel(with event: NSEvent) {
        // TODO: Handle scrollback
        metalView?.markAllDirty()
    }

    private func cellPosition(at point: NSPoint) -> (row: Int, col: Int) {
        let settings = Settings.shared
        let size = CGFloat(settings.fontSize)
        let font = NSFont(name: settings.fontFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)

        let fontAttributes = [NSAttributedString.Key.font: font]
        let charSize = NSString("W").size(withAttributes: fontAttributes)

        let padding: CGFloat = 8
        let x = point.x - padding
        let y = bounds.height - point.y - padding  // Flip Y

        let col = max(0, min(Int(x / charSize.width), terminal.cols - 1))
        let row = max(0, min(Int(y / charSize.height), terminal.rows - 1))

        return (row, col)
    }

    // MARK: - Copy/Paste

    @objc func copy(_ sender: Any?) {
        guard let text = metalView?.getSelectedText(), !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Clear selection after copy
        metalView?.selectionManager.clearSelection()
        metalView?.markAllDirty()
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }

        inputHandler.bracketedPasteMode = terminal.modes.contains(.bracketedPaste)
        inputHandler.paste(text)
    }

    // MARK: - TerminalEmulatorDelegate

    func terminal(_ terminal: TerminalEmulator, titleChanged: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.pane(self, didUpdateTitle: titleChanged)
        }
    }

    func terminalBell(_ terminal: TerminalEmulator) {
        NSSound.beep()
    }

    func terminal(_ terminal: TerminalEmulator, send data: Data) {
        ptyManager.write(data)
    }

    func terminalDidUpdate(_ terminal: TerminalEmulator) {
        DispatchQueue.main.async { [weak self] in
            self?.metalView?.markAllDirty()
        }
    }

    func terminal(_ terminal: TerminalEmulator, sizeChanged cols: Int, rows: Int) {
        // Size change is handled elsewhere
    }

    // MARK: - PTYManagerDelegate

    func ptyManager(_ manager: PTYManager, didReceiveData data: Data) {
        logDebug("Received \(data.count) bytes from PTY", context: "TerminalPane")
        terminal.feed(data)
    }

    func ptyManager(_ manager: PTYManager, processTerminated exitCode: Int32) {
        logInfo("Shell process terminated with code \(exitCode)", context: "TerminalPane")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.paneDidClose(self)
        }
    }

    // MARK: - Search

    func search(for query: String, backwards: Bool = false) -> (count: Int, current: Int) {
        guard !query.isEmpty else {
            clearSearch()
            return (0, 0)
        }

        currentSearchQuery = query
        searchMatches.removeAll()

        // Search through terminal buffer
        for row in 0..<terminal.rows {
            guard let line = terminal.getLine(row: row) else { continue }

            var lineText = ""
            for col in 0..<line.count {
                lineText.append(line[col].character)
            }

            // Find matches in this line
            var searchRange = lineText.startIndex..<lineText.endIndex
            while let range = lineText.range(of: query, options: .caseInsensitive, range: searchRange) {
                let column = lineText.distance(from: lineText.startIndex, to: range.lowerBound)
                searchMatches.append(SearchMatch(row: row, column: column, length: query.count))
                searchRange = range.upperBound..<lineText.endIndex
            }
        }

        if searchMatches.isEmpty {
            return (0, 0)
        }

        currentMatchIndex = backwards ? searchMatches.count - 1 : 0
        highlightCurrentMatch()
        return (searchMatches.count, currentMatchIndex + 1)
    }

    func findNext() -> (count: Int, current: Int) {
        guard !searchMatches.isEmpty else { return (0, 0) }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        highlightCurrentMatch()
        return (searchMatches.count, currentMatchIndex + 1)
    }

    func findPrevious() -> (count: Int, current: Int) {
        guard !searchMatches.isEmpty else { return (0, 0) }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        highlightCurrentMatch()
        return (searchMatches.count, currentMatchIndex + 1)
    }

    func clearSearch() {
        searchMatches.removeAll()
        currentMatchIndex = 0
        currentSearchQuery = ""
        metalView?.setSelection(start: nil, end: nil)
    }

    private func highlightCurrentMatch() {
        guard currentMatchIndex < searchMatches.count else { return }
        let match = searchMatches[currentMatchIndex]

        // Highlight the match using selection
        metalView?.setSelection(
            start: (row: match.row, col: match.column),
            end: (row: match.row, col: match.column + match.length - 1)
        )
    }

    // MARK: - Buffer Operations

    func clear() {
        terminal.reset()
        metalView?.setNeedsDisplay(bounds)
    }

    // MARK: - Settings Updates

    func updateFont() {
        // Recalculate cell size based on new font
        let font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(Settings.shared.fontSize),
            weight: .regular
        )
        cellSize = calculateCellSize(for: font)

        // Recalculate terminal size
        let cols = max(1, Int(bounds.width / cellSize.width))
        let rows = max(1, Int(bounds.height / cellSize.height))

        terminal.resize(cols: cols, rows: rows)
        ptyManager?.resize(cols: cols, rows: rows)

        // Update Metal view
        metalView?.frame = bounds
        metalView?.setNeedsDisplay(bounds)
    }

    func updateTheme() {
        // Update background color
        layer?.backgroundColor = Settings.shared.theme.background.cgColor
        metalView?.setNeedsDisplay(bounds)
    }

    private func calculateCellSize(for font: NSFont) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let sampleChar = NSAttributedString(string: "M", attributes: attributes)
        let size = sampleChar.size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
}
