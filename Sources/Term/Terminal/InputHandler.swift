import AppKit

// MARK: - Input Handler

/// Handles keyboard and mouse input for terminal
public final class InputHandler {
    public weak var ptyManager: PTYManager?
    public var applicationCursorMode: Bool = false
    public var bracketedPasteMode: Bool = false

    public init() {}

    // MARK: - Keyboard

    /// Handle key event
    public func handleKeyDown(_ event: NSEvent) {
        guard let pty = ptyManager else { return }

        let modifiers = extractModifiers(event)
        let keyCode = event.keyCode

        // Check for special keys first
        if let termKey = mapKeyCode(keyCode) {
            pty.sendKey(termKey, modifiers: modifiers)
            return
        }

        // Handle modifier combinations
        if modifiers.contains(.control) {
            handleControlKey(event, modifiers: modifiers)
            return
        }

        if modifiers.contains(.alt) {
            handleAltKey(event, modifiers: modifiers)
            return
        }

        // Regular character input
        if let chars = event.characters, !chars.isEmpty {
            pty.write(chars)
        }
    }

    private func extractModifiers(_ event: NSEvent) -> TerminalModifiers {
        var mods: TerminalModifiers = []
        let flags = event.modifierFlags

        if flags.contains(.shift)   { mods.insert(.shift) }
        if flags.contains(.option)  { mods.insert(.alt) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.command) { mods.insert(.meta) }

        return mods
    }

    private func mapKeyCode(_ keyCode: UInt16) -> TerminalKey? {
        switch keyCode {
        case 0x24: return .enter      // Return
        case 0x30: return .tab        // Tab
        case 0x33: return .backspace  // Delete
        case 0x35: return .escape     // Escape
        case 0x75: return .delete     // Forward Delete

        case 0x7E: return .up         // Up Arrow
        case 0x7D: return .down       // Down Arrow
        case 0x7B: return .left       // Left Arrow
        case 0x7C: return .right      // Right Arrow

        case 0x73: return .home       // Home
        case 0x77: return .end        // End
        case 0x74: return .pageUp     // Page Up
        case 0x79: return .pageDown   // Page Down
        case 0x72: return .insert     // Insert (Help)

        case 0x7A: return .f1
        case 0x78: return .f2
        case 0x63: return .f3
        case 0x76: return .f4
        case 0x60: return .f5
        case 0x61: return .f6
        case 0x62: return .f7
        case 0x64: return .f8
        case 0x65: return .f9
        case 0x6D: return .f10
        case 0x67: return .f11
        case 0x6F: return .f12

        default: return nil
        }
    }

    private func handleControlKey(_ event: NSEvent, modifiers: TerminalModifiers) {
        guard let pty = ptyManager else { return }

        // Get the character without modifiers
        guard let chars = event.charactersIgnoringModifiers,
              let char = chars.first else { return }

        let scalar = char.unicodeScalars.first?.value ?? 0

        // Control characters: Ctrl-A = 0x01, Ctrl-Z = 0x1A
        if scalar >= 0x61 && scalar <= 0x7A {
            // a-z
            let controlChar = UInt8(scalar - 0x60)
            pty.write(Data([controlChar]))
        } else if scalar >= 0x41 && scalar <= 0x5A {
            // A-Z
            let controlChar = UInt8(scalar - 0x40)
            pty.write(Data([controlChar]))
        } else {
            switch char {
            case "@": pty.write(Data([0x00]))  // Ctrl-@
            case "[": pty.write(Data([0x1B]))  // Ctrl-[ = ESC
            case "\\": pty.write(Data([0x1C])) // Ctrl-\
            case "]": pty.write(Data([0x1D]))  // Ctrl-]
            case "^": pty.write(Data([0x1E]))  // Ctrl-^
            case "_": pty.write(Data([0x1F]))  // Ctrl-_
            case "?": pty.write(Data([0x7F]))  // Ctrl-? = DEL
            default:
                // Pass through with modifier
                if let special = mapKeyCode(event.keyCode) {
                    pty.sendKey(special, modifiers: modifiers)
                }
            }
        }
    }

    private func handleAltKey(_ event: NSEvent, modifiers: TerminalModifiers) {
        guard let pty = ptyManager else { return }

        // Alt/Option key: send ESC prefix + character
        guard let chars = event.charactersIgnoringModifiers,
              let char = chars.first else { return }

        // ESC prefix
        var data = Data([0x1B])
        data.append(Data(String(char).utf8))
        pty.write(data)
    }

    // MARK: - Paste

    /// Handle paste operation
    public func paste(_ text: String) {
        guard let pty = ptyManager else { return }

        if bracketedPasteMode {
            // Bracketed paste: ESC[200~ ... ESC[201~
            pty.write("\u{1B}[200~")
            pty.write(text)
            pty.write("\u{1B}[201~")
        } else {
            pty.write(text)
        }
    }

    // MARK: - Mouse

    /// Mouse button state
    public struct MouseState {
        public var button: Int = 0  // 0=left, 1=middle, 2=right
        public var x: Int = 0
        public var y: Int = 0
        public var pressed: Bool = false
        public var modifiers: TerminalModifiers = []
    }

    /// Handle mouse event
    public func handleMouse(
        _ state: MouseState,
        mode: MouseMode,
        sgrMode: Bool
    ) {
        guard let pty = ptyManager else { return }

        // Encode mouse event
        let sequence: String

        if sgrMode {
            // SGR mode (1006)
            let button = encodeButton(state.button, pressed: state.pressed, modifiers: state.modifiers)
            let terminator = state.pressed ? "M" : "m"
            sequence = "\u{1B}[<\(button);\(state.x + 1);\(state.y + 1)\(terminator)"
        } else {
            // Normal mode (X10/1000)
            let button = encodeButton(state.button, pressed: state.pressed, modifiers: state.modifiers)
            let cb = min(button + 32, 255)
            let cx = min(state.x + 33, 255)
            let cy = min(state.y + 33, 255)
            sequence = "\u{1B}[M\(Character(UnicodeScalar(cb)!))\(Character(UnicodeScalar(cx)!))\(Character(UnicodeScalar(cy)!))"
        }

        pty.write(sequence)
    }

    private func encodeButton(_ button: Int, pressed: Bool, modifiers: TerminalModifiers) -> Int {
        var code = button

        if !pressed {
            code = 3  // Release
        }

        if modifiers.contains(.shift)   { code += 4 }
        if modifiers.contains(.alt)     { code += 8 }
        if modifiers.contains(.control) { code += 16 }

        return code
    }

    /// Handle scroll wheel
    public func handleScroll(
        deltaY: Int,
        x: Int,
        y: Int,
        sgrMode: Bool
    ) {
        guard let pty = ptyManager else { return }

        // Scroll is button 4 (up) or 5 (down) + 64
        let button = deltaY < 0 ? 64 : 65

        if sgrMode {
            let sequence = "\u{1B}[<\(button);\(x + 1);\(y + 1)M"
            pty.write(sequence)
        } else {
            let cb = min(button + 32, 255)
            let cx = min(x + 33, 255)
            let cy = min(y + 33, 255)
            let sequence = "\u{1B}[M\(Character(UnicodeScalar(cb)!))\(Character(UnicodeScalar(cx)!))\(Character(UnicodeScalar(cy)!))"
            pty.write(sequence)
        }
    }
}

// MARK: - Mouse Mode

public enum MouseMode {
    case none
    case button   // 1000
    case drag     // 1002
    case motion   // 1003
}

// MARK: - Selection Manager

/// Manages text selection in terminal
public final class SelectionManager {
    public var start: (row: Int, col: Int)?
    public var end: (row: Int, col: Int)?

    public var isActive: Bool {
        return start != nil && end != nil
    }

    public init() {}

    /// Start selection
    public func startSelection(row: Int, col: Int) {
        start = (row, col)
        end = (row, col)
    }

    /// Update selection
    public func updateSelection(row: Int, col: Int) {
        end = (row, col)
    }

    /// End selection
    public func endSelection() {
        // Selection stays active until cleared
    }

    /// Clear selection
    public func clearSelection() {
        start = nil
        end = nil
    }

    /// Get selected text from terminal
    public func getSelectedText(from terminal: TerminalEmulator) -> String {
        guard let start = start, let end = end else { return "" }

        // Normalize selection direction
        let (startRow, startCol, endRow, endCol): (Int, Int, Int, Int)
        if start.row < end.row || (start.row == end.row && start.col <= end.col) {
            (startRow, startCol, endRow, endCol) = (start.row, start.col, end.row, end.col)
        } else {
            (startRow, startCol, endRow, endCol) = (end.row, end.col, start.row, start.col)
        }

        var result = ""

        for row in startRow...endRow {
            guard let line = terminal.getLine(row: row) else { continue }

            let colStart = (row == startRow) ? startCol : 0
            let colEnd = (row == endRow) ? endCol : line.count - 1

            for col in colStart...colEnd {
                let cell = line[col]
                if !cell.isContinuation {
                    result.append(cell.character)
                }
            }

            // Add newline between rows (but not after last row)
            if row < endRow && !line.isWrapped {
                result.append("\n")
            }
        }

        return result
    }

    /// Check if cell is selected
    public func isSelected(row: Int, col: Int) -> Bool {
        guard let start = start, let end = end else { return false }

        let (startRow, startCol, endRow, endCol): (Int, Int, Int, Int)
        if start.row < end.row || (start.row == end.row && start.col <= end.col) {
            (startRow, startCol, endRow, endCol) = (start.row, start.col, end.row, end.col)
        } else {
            (startRow, startCol, endRow, endCol) = (end.row, end.col, start.row, start.col)
        }

        if row < startRow || row > endRow { return false }
        if row == startRow && col < startCol { return false }
        if row == endRow && col > endCol { return false }

        return true
    }
}
