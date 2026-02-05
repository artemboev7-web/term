import Foundation

// MARK: - Cursor State

/// Cursor position and state
public struct CursorState {
    public var x: Int = 0
    public var y: Int = 0
    public var attribute: CellAttribute = .default
    public var originMode: Bool = false  // DECOM
    public var autoWrap: Bool = true     // DECAWM
    public var wrapNext: Bool = false    // Pending wrap

    public init() {}
}

// MARK: - Saved Cursor

/// Saved cursor state (DECSC/DECRC)
public struct SavedCursor {
    public var x: Int
    public var y: Int
    public var attribute: CellAttribute
    public var originMode: Bool
    public var autoWrap: Bool
    public var charset: Int  // G0-G3 selection
}

// MARK: - Scroll Region

/// Scroll region (DECSTBM)
public struct ScrollRegion {
    public var top: Int
    public var bottom: Int

    public init(top: Int, bottom: Int) {
        self.top = top
        self.bottom = bottom
    }
}

// MARK: - Terminal Buffer

/// Main terminal buffer with scrollback
public final class TerminalBuffer {
    // MARK: - Properties

    /// Number of columns
    public private(set) var cols: Int

    /// Number of rows (visible area)
    public private(set) var rows: Int

    /// Visible lines (main buffer)
    public private(set) var lines: [TerminalLine]

    /// Scrollback buffer
    public private(set) var scrollback: [TerminalLine]

    /// Maximum scrollback lines
    public var maxScrollback: Int = 10000

    /// Cursor state
    public var cursor: CursorState = CursorState()

    /// Saved cursor (DECSC)
    public var savedCursor: SavedCursor?

    /// Scroll region
    public var scrollRegion: ScrollRegion

    /// Tab stops
    public var tabStops: Set<Int> = []

    /// Current attribute for new characters
    public var currentAttribute: CellAttribute = .default

    /// Scroll position (0 = bottom, positive = scrolled up)
    public var scrollOffset: Int = 0

    // MARK: - Initialization

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        self.scrollRegion = ScrollRegion(top: 0, bottom: rows - 1)
        self.lines = (0..<rows).map { _ in TerminalLine(cols: cols) }
        self.scrollback = []
        setupDefaultTabStops()
    }

    private func setupDefaultTabStops() {
        tabStops.removeAll()
        for i in stride(from: 8, to: cols, by: 8) {
            tabStops.insert(i)
        }
    }

    // MARK: - Line Access

    /// Get line at row (0 = top of visible area)
    public func getLine(row: Int) -> TerminalLine? {
        guard row >= 0 && row < rows else { return nil }
        return lines[row]
    }

    /// Get cell at position
    public subscript(row: Int, col: Int) -> TerminalCell {
        get {
            guard let line = getLine(row: row) else { return .empty }
            return line[col]
        }
        set {
            guard row >= 0 && row < rows else { return }
            lines[row][col] = newValue
        }
    }

    /// Get line from scrollback (negative row) or visible area
    public func getLineWithScrollback(row: Int) -> TerminalLine? {
        if row < 0 {
            let scrollbackIndex = scrollback.count + row
            guard scrollbackIndex >= 0 && scrollbackIndex < scrollback.count else { return nil }
            return scrollback[scrollbackIndex]
        }
        return getLine(row: row)
    }

    // MARK: - Cursor Movement

    /// Move cursor to position (clamped to bounds)
    public func moveCursor(to x: Int, y: Int) {
        let (minY, maxY) = cursor.originMode
            ? (scrollRegion.top, scrollRegion.bottom)
            : (0, rows - 1)

        cursor.x = max(0, min(x, cols - 1))
        cursor.y = max(minY, min(y, maxY))
        cursor.wrapNext = false
    }

    /// Move cursor relative
    public func moveCursorBy(dx: Int = 0, dy: Int = 0) {
        moveCursor(to: cursor.x + dx, y: cursor.y + dy)
    }

    /// Carriage return
    public func carriageReturn() {
        cursor.x = 0
        cursor.wrapNext = false
    }

    /// Line feed (with scrolling if needed)
    public func lineFeed() {
        cursor.wrapNext = false
        if cursor.y == scrollRegion.bottom {
            scrollUp(count: 1)
        } else if cursor.y < rows - 1 {
            cursor.y += 1
        }
    }

    /// Reverse index (scroll down if at top)
    public func reverseIndex() {
        cursor.wrapNext = false
        if cursor.y == scrollRegion.top {
            scrollDown(count: 1)
        } else if cursor.y > 0 {
            cursor.y -= 1
        }
    }

    /// Tab forward
    public func tab() {
        cursor.wrapNext = false
        let sortedTabs = tabStops.sorted()
        if let nextTab = sortedTabs.first(where: { $0 > cursor.x }) {
            cursor.x = min(nextTab, cols - 1)
        } else {
            cursor.x = cols - 1
        }
    }

    /// Tab backward
    public func backTab() {
        cursor.wrapNext = false
        let sortedTabs = tabStops.sorted().reversed()
        if let prevTab = sortedTabs.first(where: { $0 < cursor.x }) {
            cursor.x = prevTab
        } else {
            cursor.x = 0
        }
    }

    // MARK: - Writing

    /// Write character at cursor position
    public func writeChar(_ char: Character) {
        guard let scalar = char.unicodeScalars.first else { return }
        let codepoint = scalar.value
        let width = scalar.displayWidth

        // Handle wrap
        if cursor.wrapNext {
            if cursor.autoWrap {
                lines[cursor.y].isWrapped = true
                carriageReturn()
                lineFeed()
            }
            cursor.wrapNext = false
        }

        // Check if we need to wrap
        if cursor.x + width > cols {
            if cursor.autoWrap {
                lines[cursor.y].isWrapped = true
                carriageReturn()
                lineFeed()
            } else {
                cursor.x = cols - width
            }
        }

        // Write the character
        let cell = TerminalCell(
            codepoint: codepoint,
            width: UInt8(width),
            attribute: currentAttribute
        )
        lines[cursor.y][cursor.x] = cell

        // For wide characters, mark next cell as continuation
        if width == 2 && cursor.x + 1 < cols {
            var continuation = TerminalCell.empty
            continuation.isContinuation = true
            continuation.attribute = currentAttribute
            lines[cursor.y][cursor.x + 1] = continuation
        }

        // Advance cursor
        cursor.x += width
        if cursor.x >= cols {
            cursor.x = cols - 1
            cursor.wrapNext = true
        }
    }

    /// Write string at cursor
    public func writeString(_ string: String) {
        for char in string {
            writeChar(char)
        }
    }

    // MARK: - Scrolling

    /// Scroll up within scroll region
    public func scrollUp(count: Int) {
        guard count > 0 else { return }
        let top = scrollRegion.top
        let bottom = scrollRegion.bottom

        // Move lines to scrollback if scrolling from top
        if top == 0 {
            for i in 0..<min(count, bottom + 1) {
                scrollback.append(lines[i].copy())
            }
            // Trim scrollback
            while scrollback.count > maxScrollback {
                scrollback.removeFirst()
            }
        }

        // Shift lines up
        for i in top..<(bottom - count + 1) {
            lines[i] = lines[i + count]
        }

        // Clear bottom lines
        for i in (bottom - count + 1)...bottom {
            lines[i] = TerminalLine(cols: cols, attribute: currentAttribute)
        }
    }

    /// Scroll down within scroll region
    public func scrollDown(count: Int) {
        guard count > 0 else { return }
        let top = scrollRegion.top
        let bottom = scrollRegion.bottom

        // Shift lines down
        for i in stride(from: bottom, through: top + count, by: -1) {
            lines[i] = lines[i - count]
        }

        // Clear top lines
        for i in top..<(top + count) {
            lines[i] = TerminalLine(cols: cols, attribute: currentAttribute)
        }
    }

    // MARK: - Erasing

    /// Erase in display
    public enum EraseMode {
        case toEnd       // From cursor to end
        case toStart     // From start to cursor
        case all         // Entire screen
        case scrollback  // Scrollback buffer
    }

    public func eraseInDisplay(_ mode: EraseMode) {
        switch mode {
        case .toEnd:
            lines[cursor.y].clearFrom(cursor.x, with: currentAttribute)
            for i in (cursor.y + 1)..<rows {
                lines[i].clear(with: currentAttribute)
            }

        case .toStart:
            for i in 0..<cursor.y {
                lines[i].clear(with: currentAttribute)
            }
            lines[cursor.y].clearTo(cursor.x, with: currentAttribute)

        case .all:
            for line in lines {
                line.clear(with: currentAttribute)
            }

        case .scrollback:
            scrollback.removeAll()
        }
    }

    /// Erase in line
    public func eraseInLine(_ mode: EraseMode) {
        switch mode {
        case .toEnd:
            lines[cursor.y].clearFrom(cursor.x, with: currentAttribute)
        case .toStart:
            lines[cursor.y].clearTo(cursor.x, with: currentAttribute)
        case .all, .scrollback:
            lines[cursor.y].clear(with: currentAttribute)
        }
    }

    /// Erase characters
    public func eraseCharacters(_ count: Int) {
        let line = lines[cursor.y]
        for i in cursor.x..<min(cursor.x + count, cols) {
            line[i] = TerminalCell(attribute: currentAttribute)
        }
    }

    // MARK: - Insert/Delete

    /// Insert blank lines at cursor
    public func insertLines(_ count: Int) {
        guard cursor.y >= scrollRegion.top && cursor.y <= scrollRegion.bottom else { return }

        let insertCount = min(count, scrollRegion.bottom - cursor.y + 1)
        for i in stride(from: scrollRegion.bottom, through: cursor.y + insertCount, by: -1) {
            lines[i] = lines[i - insertCount]
        }
        for i in cursor.y..<(cursor.y + insertCount) {
            lines[i] = TerminalLine(cols: cols, attribute: currentAttribute)
        }
    }

    /// Delete lines at cursor
    public func deleteLines(_ count: Int) {
        guard cursor.y >= scrollRegion.top && cursor.y <= scrollRegion.bottom else { return }

        let deleteCount = min(count, scrollRegion.bottom - cursor.y + 1)
        for i in cursor.y..<(scrollRegion.bottom - deleteCount + 1) {
            lines[i] = lines[i + deleteCount]
        }
        for i in (scrollRegion.bottom - deleteCount + 1)...scrollRegion.bottom {
            lines[i] = TerminalLine(cols: cols, attribute: currentAttribute)
        }
    }

    /// Insert blank characters at cursor
    public func insertCharacters(_ count: Int) {
        lines[cursor.y].insertCharacters(at: cursor.x, count: count, attribute: currentAttribute)
    }

    /// Delete characters at cursor
    public func deleteCharacters(_ count: Int) {
        lines[cursor.y].deleteCharacters(at: cursor.x, count: count, attribute: currentAttribute)
    }

    // MARK: - Cursor Save/Restore

    /// Save cursor state (DECSC)
    public func saveCursor() {
        savedCursor = SavedCursor(
            x: cursor.x,
            y: cursor.y,
            attribute: currentAttribute,
            originMode: cursor.originMode,
            autoWrap: cursor.autoWrap,
            charset: 0
        )
    }

    /// Restore cursor state (DECRC)
    public func restoreCursor() {
        guard let saved = savedCursor else { return }
        cursor.x = saved.x
        cursor.y = saved.y
        currentAttribute = saved.attribute
        cursor.originMode = saved.originMode
        cursor.autoWrap = saved.autoWrap
    }

    // MARK: - Resize

    /// Resize buffer
    public func resize(cols: Int, rows: Int) {
        let oldCols = self.cols
        let oldRows = self.rows

        self.cols = cols
        self.rows = rows
        self.scrollRegion = ScrollRegion(top: 0, bottom: rows - 1)

        // Resize existing lines
        for line in lines {
            line.resize(to: cols, attribute: currentAttribute)
        }

        // Add or remove rows
        if rows > oldRows {
            for _ in oldRows..<rows {
                lines.append(TerminalLine(cols: cols, attribute: currentAttribute))
            }
        } else if rows < oldRows {
            // Move excess lines to scrollback
            let excess = oldRows - rows
            for i in 0..<excess {
                if !lines[i].cells.allSatisfy({ $0.codepoint == 0x20 }) {
                    scrollback.append(lines[i])
                }
            }
            lines.removeFirst(excess)
        }

        // Resize scrollback
        for line in scrollback {
            line.resize(to: cols)
        }

        // Reset tab stops
        setupDefaultTabStops()

        // Clamp cursor
        cursor.x = min(cursor.x, cols - 1)
        cursor.y = min(cursor.y, rows - 1)
    }

    // MARK: - Reset

    /// Full reset
    public func reset() {
        cursor = CursorState()
        savedCursor = nil
        currentAttribute = .default
        scrollRegion = ScrollRegion(top: 0, bottom: rows - 1)
        scrollOffset = 0

        for line in lines {
            line.clear()
        }

        setupDefaultTabStops()
    }
}

// MARK: - Alternate Screen Buffer

/// Manages main and alternate screen buffers
public final class TerminalScreenManager {
    public let mainBuffer: TerminalBuffer
    public private(set) var altBuffer: TerminalBuffer?
    public private(set) var isAlternate: Bool = false

    public var activeBuffer: TerminalBuffer {
        isAlternate ? (altBuffer ?? mainBuffer) : mainBuffer
    }

    public init(cols: Int, rows: Int) {
        self.mainBuffer = TerminalBuffer(cols: cols, rows: rows)
    }

    /// Switch to alternate screen buffer
    public func enterAlternateScreen() {
        guard !isAlternate else { return }
        altBuffer = TerminalBuffer(cols: mainBuffer.cols, rows: mainBuffer.rows)
        altBuffer?.maxScrollback = 0  // No scrollback in alt screen
        isAlternate = true
    }

    /// Return to main screen buffer
    public func exitAlternateScreen() {
        guard isAlternate else { return }
        altBuffer = nil
        isAlternate = false
    }

    /// Resize both buffers
    public func resize(cols: Int, rows: Int) {
        mainBuffer.resize(cols: cols, rows: rows)
        altBuffer?.resize(cols: cols, rows: rows)
    }
}
