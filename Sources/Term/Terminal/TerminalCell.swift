import Foundation
import simd

// MARK: - Color

/// Terminal color representation
public enum TerminalColor: Equatable {
    case `default`
    case defaultInverted
    case ansi(UInt8)          // 0-15 standard, 16-255 extended
    case rgb(UInt8, UInt8, UInt8)

    /// Convert to simd_float4 for Metal rendering
    func toFloat4(palette: [simd_float4], isBackground: Bool, defaultFg: simd_float4, defaultBg: simd_float4) -> simd_float4 {
        switch self {
        case .default:
            return isBackground ? defaultBg : defaultFg
        case .defaultInverted:
            return isBackground ? defaultFg : defaultBg
        case .ansi(let code):
            return Self.ansi256ToFloat4(Int(code), palette: palette)
        case .rgb(let r, let g, let b):
            return simd_float4(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, 1.0)
        }
    }

    private static func ansi256ToFloat4(_ code: Int, palette: [simd_float4]) -> simd_float4 {
        if code < 16 {
            return code < palette.count ? palette[code] : simd_float4(1, 1, 1, 1)
        } else if code < 232 {
            // 216-color cube (6x6x6)
            let index = code - 16
            let r = (index / 36) % 6
            let g = (index / 6) % 6
            let b = index % 6
            let toFloat: (Int) -> Float = { $0 == 0 ? 0 : Float($0 * 40 + 55) / 255.0 }
            return simd_float4(toFloat(r), toFloat(g), toFloat(b), 1.0)
        } else {
            // 24-level grayscale
            let gray = Float((code - 232) * 10 + 8) / 255.0
            return simd_float4(gray, gray, gray, 1.0)
        }
    }
}

// MARK: - Character Style

/// Text style flags
public struct CharacterStyle: OptionSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold          = CharacterStyle(rawValue: 1 << 0)
    public static let dim           = CharacterStyle(rawValue: 1 << 1)
    public static let italic        = CharacterStyle(rawValue: 1 << 2)
    public static let underline     = CharacterStyle(rawValue: 1 << 3)
    public static let blink         = CharacterStyle(rawValue: 1 << 4)
    public static let inverse       = CharacterStyle(rawValue: 1 << 5)
    public static let invisible     = CharacterStyle(rawValue: 1 << 6)
    public static let strikethrough = CharacterStyle(rawValue: 1 << 7)
    public static let doubleUnderline = CharacterStyle(rawValue: 1 << 8)
    public static let curlyUnderline  = CharacterStyle(rawValue: 1 << 9)

    public static let none: CharacterStyle = []
}

// MARK: - Cell Attribute

/// Complete cell attribute (colors + style)
public struct CellAttribute: Equatable {
    public var fg: TerminalColor
    public var bg: TerminalColor
    public var style: CharacterStyle
    public var underlineColor: TerminalColor?

    public init(
        fg: TerminalColor = .default,
        bg: TerminalColor = .default,
        style: CharacterStyle = .none,
        underlineColor: TerminalColor? = nil
    ) {
        self.fg = fg
        self.bg = bg
        self.style = style
        self.underlineColor = underlineColor
    }

    public static let `default` = CellAttribute()
}

// MARK: - Terminal Cell

/// Single cell in terminal buffer
public struct TerminalCell: Equatable {
    /// Unicode scalar value (0 = empty/space)
    public var codepoint: UInt32

    /// Display width (1 or 2 for CJK)
    public var width: UInt8

    /// Cell attributes
    public var attribute: CellAttribute

    /// Whether this is a continuation of a wide character
    public var isContinuation: Bool

    public init(
        codepoint: UInt32 = 0x20,  // space
        width: UInt8 = 1,
        attribute: CellAttribute = .default,
        isContinuation: Bool = false
    ) {
        self.codepoint = codepoint
        self.width = width
        self.attribute = attribute
        self.isContinuation = isContinuation
    }

    public static let empty = TerminalCell()
    public static let space = TerminalCell(codepoint: 0x20, width: 1)

    /// Get character from codepoint
    public var character: Character {
        if let scalar = UnicodeScalar(codepoint) {
            return Character(scalar)
        }
        return " "
    }
}

// MARK: - Terminal Line

/// Single line in terminal buffer
public final class TerminalLine {
    public var cells: [TerminalCell]
    public var isWrapped: Bool

    public init(cols: Int, attribute: CellAttribute = .default) {
        self.cells = Array(repeating: TerminalCell(attribute: attribute), count: cols)
        self.isWrapped = false
    }

    public subscript(col: Int) -> TerminalCell {
        get {
            guard col >= 0 && col < cells.count else { return .empty }
            return cells[col]
        }
        set {
            guard col >= 0 && col < cells.count else { return }
            cells[col] = newValue
        }
    }

    public var count: Int { cells.count }

    /// Resize line to new column count
    public func resize(to cols: Int, attribute: CellAttribute = .default) {
        if cols > cells.count {
            cells.append(contentsOf: Array(repeating: TerminalCell(attribute: attribute), count: cols - cells.count))
        } else if cols < cells.count {
            cells.removeLast(cells.count - cols)
        }
    }

    /// Clear line with attribute
    public func clear(with attribute: CellAttribute = .default) {
        for i in 0..<cells.count {
            cells[i] = TerminalCell(attribute: attribute)
        }
        isWrapped = false
    }

    /// Clear from column to end
    public func clearFrom(_ col: Int, with attribute: CellAttribute = .default) {
        for i in col..<cells.count {
            cells[i] = TerminalCell(attribute: attribute)
        }
    }

    /// Clear from start to column
    public func clearTo(_ col: Int, with attribute: CellAttribute = .default) {
        for i in 0...min(col, cells.count - 1) {
            cells[i] = TerminalCell(attribute: attribute)
        }
    }

    /// Copy line
    public func copy() -> TerminalLine {
        let line = TerminalLine(cols: cells.count)
        line.cells = cells
        line.isWrapped = isWrapped
        return line
    }

    /// Insert characters at position, shifting right
    public func insertCharacters(at col: Int, count: Int, attribute: CellAttribute = .default) {
        guard col >= 0 && col < cells.count && count > 0 else { return }
        let insertCells = Array(repeating: TerminalCell(attribute: attribute), count: count)
        cells.insert(contentsOf: insertCells, at: col)
        cells.removeLast(min(count, cells.count - col))
    }

    /// Delete characters at position, shifting left
    public func deleteCharacters(at col: Int, count: Int, attribute: CellAttribute = .default) {
        guard col >= 0 && col < cells.count && count > 0 else { return }
        let deleteCount = min(count, cells.count - col)
        cells.removeSubrange(col..<(col + deleteCount))
        cells.append(contentsOf: Array(repeating: TerminalCell(attribute: attribute), count: deleteCount))
    }
}

// MARK: - Unicode Width

extension UnicodeScalar {
    /// Check if this is a wide (CJK) character
    var isWide: Bool {
        let v = value
        // CJK ranges (simplified)
        return (v >= 0x1100 && v <= 0x115F) ||   // Hangul Jamo
               (v >= 0x2E80 && v <= 0x9FFF) ||   // CJK
               (v >= 0xAC00 && v <= 0xD7A3) ||   // Hangul Syllables
               (v >= 0xF900 && v <= 0xFAFF) ||   // CJK Compatibility
               (v >= 0xFE10 && v <= 0xFE1F) ||   // Vertical Forms
               (v >= 0xFE30 && v <= 0xFE6F) ||   // CJK Compatibility Forms
               (v >= 0xFF00 && v <= 0xFF60) ||   // Fullwidth Forms
               (v >= 0xFFE0 && v <= 0xFFE6) ||   // Fullwidth Signs
               (v >= 0x20000 && v <= 0x2FFFF) || // CJK Extension B+
               (v >= 0x30000 && v <= 0x3FFFF)    // CJK Extension G+
    }

    /// Character display width (1 or 2)
    var displayWidth: Int {
        isWide ? 2 : 1
    }
}
