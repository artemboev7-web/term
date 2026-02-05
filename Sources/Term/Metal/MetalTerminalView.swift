import MetalKit
import SwiftTerm
import AppKit

/// Metal-accelerated terminal view that renders SwiftTerm buffer
final class MetalTerminalView: MTKView {
    // MARK: - Properties

    private var renderer: MetalRenderer?
    private var cellGrid: CellGrid?

    // Reference to SwiftTerm terminal (weak to avoid retain cycle)
    weak var terminalView: LocalProcessTerminalView?

    // Dirty tracking
    private var needsFullRedraw: Bool = true
    private var dirtyRows: Set<Int> = []

    // Frame rate control
    private var lastRenderTime: CFAbsoluteTime = 0
    private let targetFrameTime: CFAbsoluteTime = 1.0 / 60.0  // 60 FPS

    // MARK: - Initialization

    init?(frame: NSRect, terminalView: LocalProcessTerminalView) {
        // Create renderer first
        guard let renderer = MetalRenderer() else {
            logError("Failed to create MetalRenderer", context: "MetalTerminalView")
            return nil
        }

        self.renderer = renderer
        self.terminalView = terminalView
        self.cellGrid = CellGrid(glyphAtlas: renderer.glyphAtlas)

        super.init(frame: frame, device: renderer.device)

        setup()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setup() {
        // MTKView configuration
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)
        enableSetNeedsDisplay = true  // Manual refresh control
        isPaused = true  // Don't auto-render, we control timing
        preferredFramesPerSecond = 60

        // Enable layer-backed view
        wantsLayer = true
        layer?.isOpaque = false

        // Subscribe to terminal updates
        setupTerminalObserver()

        logInfo("MetalTerminalView initialized", context: "MetalTerminalView")
    }

    private func setupTerminalObserver() {
        // Listen for terminal content changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(terminalDidUpdate),
            name: NSNotification.Name("TerminalContentChanged"),
            object: nil
        )

        // Listen for theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeChanged,
            object: nil
        )

        // Listen for font changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontDidChange),
            name: .fontChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontDidChange),
            name: .fontSizeChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    func setFont(_ font: NSFont) {
        renderer?.setFont(font)
        needsFullRedraw = true
        setNeedsDisplay(bounds)
    }

    func applyTheme(_ theme: Theme) {
        cellGrid?.applyTheme(theme)

        // Update clear color
        clearColor = MTLClearColor(
            red: Double(theme.background.redComponent),
            green: Double(theme.background.greenComponent),
            blue: Double(theme.background.blueComponent),
            alpha: 1.0
        )

        needsFullRedraw = true
        setNeedsDisplay(bounds)
    }

    func setCursor(row: Int, col: Int, visible: Bool) {
        cellGrid?.cursorRow = row
        cellGrid?.cursorCol = col
        cellGrid?.cursorVisible = visible
        renderer?.setCursor(row: row, col: col)
    }

    func setSelection(start: (row: Int, col: Int)?, end: (row: Int, col: Int)?) {
        cellGrid?.selectionStart = start
        cellGrid?.selectionEnd = end

        if let s = start, let e = end {
            renderer?.setSelection(startRow: s.row, startCol: s.col, endRow: e.row, endCol: e.col)
        } else {
            renderer?.clearSelection()
        }
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let renderer = renderer,
              let cellGrid = cellGrid,
              let terminalView = terminalView,
              let drawable = currentDrawable else {
            return
        }

        // Throttle rendering
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastRenderTime < targetFrameTime && !needsFullRedraw {
            return
        }
        lastRenderTime = now

        // Get terminal state
        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols

        // Update renderer configuration
        renderer.setGridSize(cols: cols, rows: rows)

        // Build cell instances
        let instances = cellGrid.buildInstances(from: terminal, rows: rows, cols: cols)

        // Update GPU buffer
        renderer.updateInstances(instances)

        // Render
        renderer.render(in: self, drawable: drawable)

        needsFullRedraw = false
        dirtyRows.removeAll()
    }

    // MARK: - Notifications

    @objc private func terminalDidUpdate() {
        // Mark as needing redraw
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }
    }

    @objc private func themeDidChange() {
        applyTheme(Settings.shared.theme)
    }

    @objc private func fontDidChange() {
        let settings = Settings.shared
        let size = CGFloat(settings.fontSize)

        if let font = NSFont(name: settings.fontFamily, size: size) {
            setFont(font)
        } else if let font = NSFont(name: "SF Mono", size: size) {
            setFont(font)
        } else {
            setFont(NSFont.monospacedSystemFont(ofSize: size, weight: .regular))
        }
    }

    // MARK: - Dirty Tracking

    func markRowDirty(_ row: Int) {
        dirtyRows.insert(row)
        setNeedsDisplay(bounds)
    }

    func markAllDirty() {
        needsFullRedraw = true
        setNeedsDisplay(bounds)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        // Update viewport when size changes
        needsFullRedraw = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Apply current theme and font
            applyTheme(Settings.shared.theme)
            fontDidChange()
        }
    }
}

// MARK: - Sync Helper

extension MetalTerminalView {
    /// Synchronize state from SwiftTerm view
    func syncFromTerminal() {
        guard let terminalView = terminalView else { return }

        let terminal = terminalView.getTerminal()

        // Sync cursor position (buffer.x = col, buffer.y = row)
        let cursorCol = terminal.buffer.x
        let cursorRow = terminal.buffer.y
        setCursor(row: cursorRow, col: cursorCol, visible: true)

        // Trigger redraw
        markAllDirty()
    }
}
