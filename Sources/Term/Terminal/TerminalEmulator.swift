import Foundation

// MARK: - Terminal Mode Flags

/// Terminal modes (DECSET/DECRST)
public struct TerminalModes: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Standard modes
    public static let insertMode = TerminalModes(rawValue: 1 << 0)        // IRM
    public static let lineFeedMode = TerminalModes(rawValue: 1 << 1)      // LNM

    // DEC private modes
    public static let cursorKeys = TerminalModes(rawValue: 1 << 2)        // DECCKM
    public static let ansiMode = TerminalModes(rawValue: 1 << 3)          // DECANM
    public static let columnMode = TerminalModes(rawValue: 1 << 4)        // DECCOLM
    public static let scrollMode = TerminalModes(rawValue: 1 << 5)        // DECSCLM
    public static let reverseScreen = TerminalModes(rawValue: 1 << 6)     // DECSCNM
    public static let originMode = TerminalModes(rawValue: 1 << 7)        // DECOM
    public static let autoWrap = TerminalModes(rawValue: 1 << 8)          // DECAWM
    public static let autoRepeat = TerminalModes(rawValue: 1 << 9)        // DECARM
    public static let cursorVisible = TerminalModes(rawValue: 1 << 10)    // DECTCEM
    public static let alternateScreen = TerminalModes(rawValue: 1 << 11)  // Alt screen
    public static let bracketedPaste = TerminalModes(rawValue: 1 << 12)   // Bracketed paste
    public static let focusEvents = TerminalModes(rawValue: 1 << 13)      // Focus reporting

    // Mouse modes
    public static let mouseButton = TerminalModes(rawValue: 1 << 14)      // 1000
    public static let mouseDrag = TerminalModes(rawValue: 1 << 15)        // 1002
    public static let mouseMotion = TerminalModes(rawValue: 1 << 16)      // 1003
    public static let mouseSGR = TerminalModes(rawValue: 1 << 17)         // 1006
    public static let mouseUTF8 = TerminalModes(rawValue: 1 << 18)        // 1005
    public static let mouseURXVT = TerminalModes(rawValue: 1 << 19)       // 1015
}

// MARK: - Terminal Delegate

public protocol TerminalEmulatorDelegate: AnyObject {
    /// Terminal title changed (OSC 0/1/2)
    func terminal(_ terminal: TerminalEmulator, titleChanged: String)

    /// Terminal bell
    func terminalBell(_ terminal: TerminalEmulator)

    /// Send data to PTY (response to terminal queries)
    func terminal(_ terminal: TerminalEmulator, send data: Data)

    /// Terminal content changed (needs redraw)
    func terminalDidUpdate(_ terminal: TerminalEmulator)

    /// Terminal resized
    func terminal(_ terminal: TerminalEmulator, sizeChanged cols: Int, rows: Int)
}

// MARK: - Terminal Emulator

/// Complete terminal emulator
public final class TerminalEmulator: TerminalParserDelegate {
    // MARK: - Properties

    public weak var delegate: TerminalEmulatorDelegate?

    /// Screen manager (main + alternate)
    private let screenManager: TerminalScreenManager

    /// Parser
    private let parser: TerminalParser

    /// Terminal modes
    public private(set) var modes: TerminalModes = [.autoWrap, .cursorVisible, .autoRepeat]

    /// Terminal title
    public private(set) var title: String = ""

    /// Icon name
    public private(set) var iconName: String = ""

    /// Number of columns
    public var cols: Int { screenManager.mainBuffer.cols }

    /// Number of rows
    public var rows: Int { screenManager.mainBuffer.rows }

    /// Active buffer
    public var buffer: TerminalBuffer { screenManager.activeBuffer }

    /// Cursor position X
    public var cursorX: Int { buffer.cursor.x }

    /// Cursor position Y
    public var cursorY: Int { buffer.cursor.y }

    /// Is cursor visible
    public var cursorVisible: Bool { modes.contains(.cursorVisible) }

    /// Is alternate screen active
    public var isAlternateScreen: Bool { screenManager.isAlternate }

    // MARK: - Initialization

    public init(cols: Int, rows: Int) {
        self.screenManager = TerminalScreenManager(cols: cols, rows: rows)
        self.parser = TerminalParser()
        self.parser.delegate = self
    }

    // MARK: - Input

    /// Process input from PTY
    public func feed(_ data: Data) {
        parser.parse(data)
        delegate?.terminalDidUpdate(self)
    }

    /// Process input string
    public func feed(_ string: String) {
        feed(Data(string.utf8))
    }

    // MARK: - Resize

    /// Resize terminal
    public func resize(cols: Int, rows: Int) {
        screenManager.resize(cols: cols, rows: rows)
        delegate?.terminal(self, sizeChanged: cols, rows: rows)
        delegate?.terminalDidUpdate(self)
    }

    // MARK: - Buffer Access

    /// Get line at row
    public func getLine(row: Int) -> TerminalLine? {
        return buffer.getLine(row: row)
    }

    /// Get cell at position
    public func getCell(row: Int, col: Int) -> TerminalCell {
        return buffer[row, col]
    }

    // MARK: - Parser Delegate

    public func parser(_ parser: TerminalParser, print char: Character) {
        buffer.writeChar(char)
    }

    public func parser(_ parser: TerminalParser, execute control: UInt8) {
        handleControl(control)
    }

    public func parser(_ parser: TerminalParser, csi: CSIParams) {
        handleCSI(csi)
    }

    public func parser(_ parser: TerminalParser, esc: UInt8, intermediates: [UInt8]) {
        handleEscape(esc, intermediates: intermediates)
    }

    public func parser(_ parser: TerminalParser, osc: Int, content: String) {
        handleOSC(osc, content: content)
    }

    public func parser(_ parser: TerminalParser, dcs: String) {
        // DCS sequences (DECRQSS, etc.) - mostly ignored
    }

    // MARK: - Control Characters

    private func handleControl(_ control: UInt8) {
        switch control {
        case 0x00: // NUL
            break
        case 0x07: // BEL
            delegate?.terminalBell(self)
        case 0x08: // BS
            buffer.moveCursorBy(dx: -1)
        case 0x09: // HT
            buffer.tab()
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            buffer.lineFeed()
        case 0x0D: // CR
            buffer.carriageReturn()
        case 0x0E: // SO (Shift Out)
            break // Charset switching - not implemented
        case 0x0F: // SI (Shift In)
            break
        case 0x84: // IND
            buffer.lineFeed()
        case 0x85: // NEL
            buffer.carriageReturn()
            buffer.lineFeed()
        case 0x88: // HTS
            buffer.tabStops.insert(buffer.cursor.x)
        case 0x8D: // RI
            buffer.reverseIndex()
        default:
            break
        }
    }

    // MARK: - Escape Sequences

    private func handleEscape(_ byte: UInt8, intermediates: [UInt8]) {
        if intermediates.isEmpty {
            switch byte {
            case 0x37: // ESC 7 = DECSC
                buffer.saveCursor()
            case 0x38: // ESC 8 = DECRC
                buffer.restoreCursor()
            case 0x44: // ESC D = IND
                buffer.lineFeed()
            case 0x45: // ESC E = NEL
                buffer.carriageReturn()
                buffer.lineFeed()
            case 0x48: // ESC H = HTS
                buffer.tabStops.insert(buffer.cursor.x)
            case 0x4D: // ESC M = RI
                buffer.reverseIndex()
            case 0x63: // ESC c = RIS (full reset)
                reset()
            default:
                break
            }
        } else if intermediates == [0x23] { // ESC #
            // Line attributes (double-width, etc.) - ignore
        } else if intermediates == [0x28] || intermediates == [0x29] ||
                  intermediates == [0x2A] || intermediates == [0x2B] {
            // Charset designation (G0-G3) - ignore
        }
    }

    // MARK: - CSI Sequences

    private func handleCSI(_ csi: CSIParams) {
        let isPrivate = csi.intermediates.first == 0x3F  // ?

        switch (isPrivate, csi.finalByte) {
        // Cursor movement
        case (false, 0x41): // CUU - Cursor Up
            buffer.moveCursorBy(dy: -csi.param(0, default: 1))

        case (false, 0x42): // CUD - Cursor Down
            buffer.moveCursorBy(dy: csi.param(0, default: 1))

        case (false, 0x43): // CUF - Cursor Forward
            buffer.moveCursorBy(dx: csi.param(0, default: 1))

        case (false, 0x44): // CUB - Cursor Back
            buffer.moveCursorBy(dx: -csi.param(0, default: 1))

        case (false, 0x45): // CNL - Cursor Next Line
            buffer.moveCursor(to: 0, y: buffer.cursor.y + csi.param(0, default: 1))

        case (false, 0x46): // CPL - Cursor Previous Line
            buffer.moveCursor(to: 0, y: buffer.cursor.y - csi.param(0, default: 1))

        case (false, 0x47): // CHA - Cursor Horizontal Absolute
            buffer.moveCursor(to: csi.param(0, default: 1) - 1, y: buffer.cursor.y)

        case (false, 0x48), (false, 0x66): // CUP/HVP - Cursor Position
            buffer.moveCursor(to: csi.param(1, default: 1) - 1, y: csi.param(0, default: 1) - 1)

        case (false, 0x49): // CHT - Cursor Horizontal Tab
            for _ in 0..<csi.param(0, default: 1) {
                buffer.tab()
            }

        // Erase
        case (false, 0x4A): // ED - Erase in Display
            handleEraseDisplay(csi.param(0, default: 0))

        case (false, 0x4B): // EL - Erase in Line
            handleEraseLine(csi.param(0, default: 0))

        case (false, 0x58): // ECH - Erase Characters
            buffer.eraseCharacters(csi.param(0, default: 1))

        // Insert/Delete
        case (false, 0x4C): // IL - Insert Lines
            buffer.insertLines(csi.param(0, default: 1))

        case (false, 0x4D): // DL - Delete Lines
            buffer.deleteLines(csi.param(0, default: 1))

        case (false, 0x50): // DCH - Delete Characters
            buffer.deleteCharacters(csi.param(0, default: 1))

        case (false, 0x40): // ICH - Insert Characters
            buffer.insertCharacters(csi.param(0, default: 1))

        // Scroll
        case (false, 0x53): // SU - Scroll Up
            buffer.scrollUp(count: csi.param(0, default: 1))

        case (false, 0x54): // SD - Scroll Down
            buffer.scrollDown(count: csi.param(0, default: 1))

        // Tab
        case (false, 0x5A): // CBT - Cursor Backward Tab
            for _ in 0..<csi.param(0, default: 1) {
                buffer.backTab()
            }

        case (false, 0x67): // TBC - Tab Clear
            handleTabClear(csi.param(0, default: 0))

        // SGR - Select Graphic Rendition
        case (false, 0x6D): // SGR
            handleSGR(csi.params)

        // Scroll region
        case (false, 0x72): // DECSTBM - Set Scrolling Region
            let top = csi.param(0, default: 1) - 1
            let bottom = csi.param(1, default: rows) - 1
            buffer.scrollRegion = ScrollRegion(top: max(0, top), bottom: min(rows - 1, bottom))
            buffer.moveCursor(to: 0, y: 0)

        // Mode set/reset
        case (true, 0x68): // DECSET
            handleDECSET(csi.params)

        case (true, 0x6C): // DECRST
            handleDECRST(csi.params)

        case (false, 0x68): // SM - Set Mode
            handleSetMode(csi.params)

        case (false, 0x6C): // RM - Reset Mode
            handleResetMode(csi.params)

        // Device status
        case (false, 0x6E): // DSR - Device Status Report
            handleDSR(csi.param(0, default: 0))

        case (true, 0x6E): // DECDSR
            handleDECDSR(csi.param(0, default: 0))

        // Cursor save/restore
        case (false, 0x73): // SCOSC - Save Cursor
            buffer.saveCursor()

        case (false, 0x75): // SCORC - Restore Cursor
            buffer.restoreCursor()

        // Column position
        case (false, 0x60): // HPA - Horizontal Position Absolute
            buffer.moveCursor(to: csi.param(0, default: 1) - 1, y: buffer.cursor.y)

        case (false, 0x64): // VPA - Vertical Position Absolute
            buffer.moveCursor(to: buffer.cursor.x, y: csi.param(0, default: 1) - 1)

        // Repeat
        case (false, 0x62): // REP - Repeat
            // Repeat last printed character - skip for now
            break

        // Device attributes
        case (false, 0x63): // DA - Primary Device Attributes
            if csi.params.isEmpty || csi.params[0] == 0 {
                // Report VT220
                let response = "\u{1B}[?62;1;2;4;6;9;15;22c"
                delegate?.terminal(self, send: Data(response.utf8))
            }

        case (true, 0x63): // Secondary DA
            // Report version
            let response = "\u{1B}[>0;1;0c"
            delegate?.terminal(self, send: Data(response.utf8))

        default:
            break
        }
    }

    // MARK: - Erase Handlers

    private func handleEraseDisplay(_ mode: Int) {
        switch mode {
        case 0: buffer.eraseInDisplay(.toEnd)
        case 1: buffer.eraseInDisplay(.toStart)
        case 2: buffer.eraseInDisplay(.all)
        case 3: buffer.eraseInDisplay(.scrollback)
        default: break
        }
    }

    private func handleEraseLine(_ mode: Int) {
        switch mode {
        case 0: buffer.eraseInLine(.toEnd)
        case 1: buffer.eraseInLine(.toStart)
        case 2: buffer.eraseInLine(.all)
        default: break
        }
    }

    private func handleTabClear(_ mode: Int) {
        switch mode {
        case 0: buffer.tabStops.remove(buffer.cursor.x)
        case 3: buffer.tabStops.removeAll()
        default: break
        }
    }

    // MARK: - SGR (Colors/Styles)

    private func handleSGR(_ params: [Int]) {
        var i = 0
        let params = params.isEmpty ? [0] : params

        while i < params.count {
            let p = params[i]

            switch p {
            case 0:
                buffer.currentAttribute = .default

            case 1:
                buffer.currentAttribute.style.insert(.bold)
            case 2:
                buffer.currentAttribute.style.insert(.dim)
            case 3:
                buffer.currentAttribute.style.insert(.italic)
            case 4:
                buffer.currentAttribute.style.insert(.underline)
            case 5, 6:
                buffer.currentAttribute.style.insert(.blink)
            case 7:
                buffer.currentAttribute.style.insert(.inverse)
            case 8:
                buffer.currentAttribute.style.insert(.invisible)
            case 9:
                buffer.currentAttribute.style.insert(.strikethrough)

            case 21:
                buffer.currentAttribute.style.insert(.doubleUnderline)
            case 22:
                buffer.currentAttribute.style.remove([.bold, .dim])
            case 23:
                buffer.currentAttribute.style.remove(.italic)
            case 24:
                buffer.currentAttribute.style.remove([.underline, .doubleUnderline, .curlyUnderline])
            case 25:
                buffer.currentAttribute.style.remove(.blink)
            case 27:
                buffer.currentAttribute.style.remove(.inverse)
            case 28:
                buffer.currentAttribute.style.remove(.invisible)
            case 29:
                buffer.currentAttribute.style.remove(.strikethrough)

            // Foreground colors
            case 30...37:
                buffer.currentAttribute.fg = .ansi(UInt8(p - 30))
            case 38:
                if let color = parseExtendedColor(params, from: &i) {
                    buffer.currentAttribute.fg = color
                }
            case 39:
                buffer.currentAttribute.fg = .default
            case 90...97:
                buffer.currentAttribute.fg = .ansi(UInt8(p - 90 + 8))

            // Background colors
            case 40...47:
                buffer.currentAttribute.bg = .ansi(UInt8(p - 40))
            case 48:
                if let color = parseExtendedColor(params, from: &i) {
                    buffer.currentAttribute.bg = color
                }
            case 49:
                buffer.currentAttribute.bg = .default
            case 100...107:
                buffer.currentAttribute.bg = .ansi(UInt8(p - 100 + 8))

            default:
                break
            }

            i += 1
        }
    }

    private func parseExtendedColor(_ params: [Int], from i: inout Int) -> TerminalColor? {
        guard i + 1 < params.count else { return nil }

        let type = params[i + 1]

        switch type {
        case 2: // RGB
            guard i + 4 < params.count else { return nil }
            let r = UInt8(clamping: params[i + 2])
            let g = UInt8(clamping: params[i + 3])
            let b = UInt8(clamping: params[i + 4])
            i += 4
            return .rgb(r, g, b)

        case 5: // 256 color
            guard i + 2 < params.count else { return nil }
            let code = UInt8(clamping: params[i + 2])
            i += 2
            return .ansi(code)

        default:
            return nil
        }
    }

    // MARK: - Mode Handlers

    private func handleDECSET(_ params: [Int]) {
        for p in params {
            switch p {
            case 1:   modes.insert(.cursorKeys)
            case 6:   modes.insert(.originMode); buffer.cursor.originMode = true
            case 7:   modes.insert(.autoWrap); buffer.cursor.autoWrap = true
            case 25:  modes.insert(.cursorVisible)
            case 1000: modes.insert(.mouseButton)
            case 1002: modes.insert(.mouseDrag)
            case 1003: modes.insert(.mouseMotion)
            case 1005: modes.insert(.mouseUTF8)
            case 1006: modes.insert(.mouseSGR)
            case 1015: modes.insert(.mouseURXVT)
            case 1047, 1049:
                screenManager.enterAlternateScreen()
                modes.insert(.alternateScreen)
                if p == 1049 { buffer.saveCursor() }
            case 2004: modes.insert(.bracketedPaste)
            case 1004: modes.insert(.focusEvents)
            default: break
            }
        }
    }

    private func handleDECRST(_ params: [Int]) {
        for p in params {
            switch p {
            case 1:   modes.remove(.cursorKeys)
            case 6:   modes.remove(.originMode); buffer.cursor.originMode = false
            case 7:   modes.remove(.autoWrap); buffer.cursor.autoWrap = false
            case 25:  modes.remove(.cursorVisible)
            case 1000: modes.remove(.mouseButton)
            case 1002: modes.remove(.mouseDrag)
            case 1003: modes.remove(.mouseMotion)
            case 1005: modes.remove(.mouseUTF8)
            case 1006: modes.remove(.mouseSGR)
            case 1015: modes.remove(.mouseURXVT)
            case 1047:
                screenManager.exitAlternateScreen()
                modes.remove(.alternateScreen)
            case 1049:
                screenManager.exitAlternateScreen()
                modes.remove(.alternateScreen)
                buffer.restoreCursor()
            case 2004: modes.remove(.bracketedPaste)
            case 1004: modes.remove(.focusEvents)
            default: break
            }
        }
    }

    private func handleSetMode(_ params: [Int]) {
        for p in params {
            switch p {
            case 4: modes.insert(.insertMode)
            case 20: modes.insert(.lineFeedMode)
            default: break
            }
        }
    }

    private func handleResetMode(_ params: [Int]) {
        for p in params {
            switch p {
            case 4: modes.remove(.insertMode)
            case 20: modes.remove(.lineFeedMode)
            default: break
            }
        }
    }

    // MARK: - Device Status

    private func handleDSR(_ param: Int) {
        switch param {
        case 5: // Status report
            delegate?.terminal(self, send: Data("\u{1B}[0n".utf8))
        case 6: // Cursor position
            let response = "\u{1B}[\(buffer.cursor.y + 1);\(buffer.cursor.x + 1)R"
            delegate?.terminal(self, send: Data(response.utf8))
        default:
            break
        }
    }

    private func handleDECDSR(_ param: Int) {
        switch param {
        case 6: // Extended cursor position
            let response = "\u{1B}[?\(buffer.cursor.y + 1);\(buffer.cursor.x + 1)R"
            delegate?.terminal(self, send: Data(response.utf8))
        default:
            break
        }
    }

    // MARK: - OSC Sequences

    private func handleOSC(_ code: Int, content: String) {
        switch code {
        case 0: // Set icon name and window title
            title = content
            iconName = content
            delegate?.terminal(self, titleChanged: content)

        case 1: // Set icon name
            iconName = content

        case 2: // Set window title
            title = content
            delegate?.terminal(self, titleChanged: content)

        case 4: // Change color palette
            // Format: 4;index;spec
            break

        case 10, 11, 12: // Foreground/background/cursor color
            break

        case 52: // Clipboard
            // Format: 52;c;base64data
            // Security-sensitive
            break

        case 104: // Reset color
            break

        case 112: // Reset cursor color
            break

        default:
            break
        }
    }

    // MARK: - Reset

    public func reset() {
        parser.reset()
        screenManager.mainBuffer.reset()
        screenManager.exitAlternateScreen()
        modes = [.autoWrap, .cursorVisible, .autoRepeat]
        title = ""
        iconName = ""
        delegate?.terminalDidUpdate(self)
    }
}
