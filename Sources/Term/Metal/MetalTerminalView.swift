import MetalKit
import AppKit
import QuartzCore

/// Metal-accelerated terminal view that renders our terminal buffer
final class MetalTerminalView: MTKView {
    // MARK: - Properties

    private var renderer: MetalRenderer?
    private var cellGrid: CellGrid?

    // Reference to terminal emulator
    weak var terminal: TerminalEmulator?

    // Selection manager
    let selectionManager = SelectionManager()

    // Dirty tracking
    private var dirtyTracker: DirtyTracker?
    private var needsFullRedraw: Bool = true

    // Display link for vsync
    private var displayLink: CVDisplayLink?
    private var displayLinkRunning: Bool = false

    // Triple buffering
    private var instanceBuffers: [MTLBuffer] = []
    private var currentBufferIndex: Int = 0
    private let bufferCount = 3
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    // Frame timing
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fps: Double = 0

    // Cursor animation
    private var cursorBlinkTimer: Timer?
    private var cursorVisible: Bool = true
    private let cursorBlinkInterval: TimeInterval = 0.5

    // MARK: - Initialization

    init?(frame: NSRect, terminal: TerminalEmulator) {
        // Create renderer first
        guard let renderer = MetalRenderer() else {
            logError("Failed to create MetalRenderer", context: "MetalTerminalView")
            return nil
        }

        self.renderer = renderer
        self.terminal = terminal
        self.cellGrid = CellGrid(glyphAtlas: renderer.glyphAtlas)
        self.cellGrid?.selectionManager = selectionManager

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

        // Manual rendering via CVDisplayLink
        enableSetNeedsDisplay = true
        isPaused = false
        preferredFramesPerSecond = 60

        // Enable layer-backed view
        wantsLayer = true
        layer?.isOpaque = true

        // Initialize dirty tracker
        if let terminal = terminal {
            dirtyTracker = DirtyTracker(rows: terminal.rows, cols: terminal.cols)
        }

        // Setup triple buffering
        setupTripleBuffering()

        // Don't use CVDisplayLink - let MTKView handle rendering internally
        // setupDisplayLink()

        // Setup cursor blink
        setupCursorBlink()

        // Subscribe to notifications
        setupObservers()

        logInfo("MetalTerminalView initialized with triple buffering", context: "MetalTerminalView")
    }

    /// Current max instances capacity
    private var maxInstances: Int = 0

    private func setupTripleBuffering() {
        reallocateBuffers(cols: 80, rows: 50)
    }

    /// Reallocate instance buffers when terminal size exceeds current capacity
    private func reallocateBuffers(cols: Int, rows: Int) {
        guard let device = renderer?.device else { return }

        let needed = cols * rows
        // Only grow, never shrink (with 20% headroom)
        guard needed > maxInstances else { return }
        maxInstances = Int(Double(needed) * 1.2)

        let bufferSize = MemoryLayout<CellInstance>.stride * maxInstances

        instanceBuffers.removeAll()
        for i in 0..<bufferCount {
            guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                logError("Failed to create instance buffer \(i)", context: "MetalTerminalView")
                continue
            }
            buffer.label = "Instance Buffer \(i)"
            instanceBuffers.append(buffer)
        }

        logDebug("Allocated \(instanceBuffers.count) instance buffers for \(maxInstances) instances", context: "MetalTerminalView")
    }

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard let displayLink = link else {
            logWarning("Failed to create CVDisplayLink, falling back to timer", context: "MetalTerminalView")
            setupFallbackTimer()
            return
        }

        self.displayLink = displayLink

        // Set output callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, context in
            guard let context = context else { return kCVReturnSuccess }
            let view = Unmanaged<MetalTerminalView>.fromOpaque(context).takeUnretainedValue()
            view.displayLinkCallback()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())

        // Start display link
        CVDisplayLinkStart(displayLink)
        displayLinkRunning = true

        logDebug("CVDisplayLink started", context: "MetalTerminalView")
    }

    private func setupFallbackTimer() {
        // Fallback to 60fps timer if display link fails
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func setupCursorBlink() {
        let timer = Timer(timeInterval: cursorBlinkInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorVisible.toggle()
            self.cellGrid?.cursorVisible = self.cursorVisible
        }
        // Use .common mode so timer fires during event tracking (resize, modal)
        RunLoop.current.add(timer, forMode: .common)
        cursorBlinkTimer = timer
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(terminalDidUpdate),
            name: NSNotification.Name("TerminalContentChanged"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeChanged,
            object: nil
        )

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

        // Window focus for cursor blink
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    deinit {
        // Stop display link
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        cursorBlinkTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        logDebug("MetalTerminalView deallocated", context: "MetalTerminalView")
    }

    // MARK: - Display Link Callback

    private func displayLinkCallback() {
        // Dispatch to main thread for rendering
        DispatchQueue.main.async { [weak self] in
            self?.renderFrame()
        }
    }

    // MARK: - Configuration

    func setFont(_ font: NSFont) {
        renderer?.setFont(font)
        needsFullRedraw = true
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
    }

    func applySettings() {
        let settings = Settings.shared

        // Cursor style
        let metalStyle: MetalCursorStyle
        switch settings.cursorStyle {
        case .block: metalStyle = .block
        case .underline: metalStyle = .underline
        case .bar: metalStyle = .bar
        }
        renderer?.setCursorStyle(metalStyle)
        renderer?.setCursorBlink(settings.cursorBlink)

        needsFullRedraw = true
    }

    func setCursor(row: Int, col: Int, visible: Bool) {
        cellGrid?.cursorRow = row
        cellGrid?.cursorCol = col
        cellGrid?.cursorVisible = visible && cursorVisible
        renderer?.setCursor(row: row, col: col)
    }

    func setSelection(start: (row: Int, col: Int)?, end: (row: Int, col: Int)?) {
        if let s = start, let e = end {
            selectionManager.start = s
            selectionManager.end = e
            renderer?.setSelection(startRow: s.row, startCol: s.col, endRow: e.row, endCol: e.col)
        } else {
            selectionManager.clearSelection()
            renderer?.clearSelection()
        }
        needsFullRedraw = true
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        renderFrame()
    }

    private func renderFrame() {
        guard let renderer = renderer else {
            logDebug("renderFrame: no renderer", context: "MetalTerminalView")
            return
        }
        guard let cellGrid = cellGrid else {
            logDebug("renderFrame: no cellGrid", context: "MetalTerminalView")
            return
        }
        guard let terminal = terminal else {
            logDebug("renderFrame: no terminal", context: "MetalTerminalView")
            return
        }
        guard let drawable = currentDrawable else {
            // Log only occasionally to avoid spam
            if frameCount % 60 == 0 {
                logDebug("renderFrame: no drawable (view may not be visible)", context: "MetalTerminalView")
            }
            return
        }

        // Update FPS counter
        updateFPSCounter()

        // Get terminal state
        let rows = terminal.rows
        let cols = terminal.cols

        // Ensure buffers are large enough for current terminal size
        reallocateBuffers(cols: cols, rows: rows)

        // Skip if nothing changed
        if let tracker = dirtyTracker, tracker.isClean && !needsFullRedraw {
            return
        }

        // Log first render
        if frameCount == 1 {
            logInfo("First render: \(cols)x\(rows), viewport: \(drawableSize)", context: "MetalTerminalView")
        }

        // Update renderer configuration
        renderer.setGridSize(cols: cols, rows: rows)

        // Sync cursor position
        let cursorCol = terminal.cursorX
        let cursorRow = terminal.cursorY
        setCursor(row: cursorRow, col: cursorCol, visible: terminal.cursorVisible)

        // Build cell instances
        let instances = cellGrid.buildInstances(from: terminal, rows: rows, cols: cols)

        // Wait for a free buffer slot (GPU must finish with the oldest buffer)
        inflightSemaphore.wait()

        // Get next buffer for triple buffering
        let instanceBuffer = getNextInstanceBuffer()

        // Update GPU buffer
        updateInstanceBuffer(instanceBuffer, with: instances)

        // Render with the current buffer, signal semaphore on GPU completion
        renderer.renderWithBuffer(in: self, drawable: drawable, instanceBuffer: instanceBuffer, instanceCount: instances.count) { [weak self] in
            self?.inflightSemaphore.signal()
        }

        // Reset dirty state
        needsFullRedraw = false
        dirtyTracker?.markClean()
    }

    private func getNextInstanceBuffer() -> MTLBuffer? {
        guard !instanceBuffers.isEmpty else { return nil }
        let buffer = instanceBuffers[currentBufferIndex]
        currentBufferIndex = (currentBufferIndex + 1) % bufferCount
        return buffer
    }

    private func updateInstanceBuffer(_ buffer: MTLBuffer?, with instances: [CellInstance]) {
        guard let buffer = buffer else { return }

        let count = min(instances.count, buffer.length / MemoryLayout<CellInstance>.stride)
        let ptr = buffer.contents().bindMemory(to: CellInstance.self, capacity: count)

        for i in 0..<count {
            ptr[i] = instances[i]
        }
    }

    private func updateFPSCounter() {
        frameCount += 1
        let now = CACurrentMediaTime()

        // Initialize on first frame to avoid FPS: 0.0 log
        if lastFrameTime == 0 {
            lastFrameTime = now
            return
        }

        if now - lastFrameTime >= 1.0 {
            fps = Double(frameCount) / (now - lastFrameTime)
            frameCount = 0
            lastFrameTime = now

            // Log FPS periodically for debugging
            if fps < 55 {
                logDebug("FPS: \(String(format: "%.1f", fps))", context: "MetalTerminalView")
            }
        }
    }

    // MARK: - Notifications

    @objc private func terminalDidUpdate() {
        dirtyTracker?.markFullyDirty()
        needsFullRedraw = true
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

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        // Resume cursor blink when window is active
        cursorBlinkTimer?.fireDate = Date()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        // Show solid cursor when window is inactive
        cursorVisible = true
        cellGrid?.cursorVisible = true
    }

    // MARK: - Dirty Tracking

    func markRowDirty(_ row: Int) {
        dirtyTracker?.markDirty(row: row)
    }

    func markRowsDirty(_ range: Range<Int>) {
        dirtyTracker?.markDirty(rows: range)
    }

    func markAllDirty() {
        dirtyTracker?.markFullyDirty()
        needsFullRedraw = true
        setNeedsDisplay(bounds)
    }

    func markScrollRegion(top: Int, bottom: Int, scrolled: Int) {
        dirtyTracker?.markScrollRegion(top: top, bottom: bottom, scrolled: scrolled)
    }

    // MARK: - Layout

    private var lastTrackedRows: Int = 0
    private var lastTrackedCols: Int = 0

    override func layout() {
        super.layout()

        // Only recreate dirty tracker if terminal dimensions actually changed
        if let terminal = terminal,
           (terminal.rows != lastTrackedRows || terminal.cols != lastTrackedCols) {
            lastTrackedRows = terminal.rows
            lastTrackedCols = terminal.cols
            dirtyTracker = DirtyTracker(rows: terminal.rows, cols: terminal.cols)
        }

        needsFullRedraw = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Apply current theme and cursor settings (font already set during setup)
            applyTheme(Settings.shared.theme)
            applySettings()

            // Update display link for this window's display
            if let displayLink = displayLink, let screen = window?.screen {
                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                CVDisplayLinkSetCurrentCGDisplay(displayLink, displayID)
            }

            // Force initial render when added to window
            needsFullRedraw = true
            setNeedsDisplay(bounds)
            logDebug("View added to window, forcing initial render", context: "MetalTerminalView")
        }
    }

    // MARK: - Public API

    /// Get current FPS for debugging
    var currentFPS: Double { fps }

    /// Pause/resume rendering
    func pauseRendering() {
        if let displayLink = displayLink, displayLinkRunning {
            CVDisplayLinkStop(displayLink)
            displayLinkRunning = false
        }
    }

    func resumeRendering() {
        if let displayLink = displayLink, !displayLinkRunning {
            CVDisplayLinkStart(displayLink)
            displayLinkRunning = true
        }
    }

    /// Get selected text
    func getSelectedText() -> String {
        guard let terminal = terminal else { return "" }
        return selectionManager.getSelectedText(from: terminal)
    }
}

// MARK: - Event Handling

extension MetalTerminalView {
    // Rendering only — input is handled by parent TerminalPaneView
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through all mouse events to parent TerminalPaneView
        return nil
    }
}

// MARK: - Sync Helper

extension MetalTerminalView {
    /// Synchronize state from terminal
    func syncFromTerminal() {
        guard let terminal = terminal else { return }

        // Sync cursor position
        setCursor(row: terminal.cursorY, col: terminal.cursorX, visible: cursorVisible)

        // Trigger redraw
        markAllDirty()
    }
}
