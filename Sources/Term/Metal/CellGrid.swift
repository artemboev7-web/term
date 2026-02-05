import simd
import SwiftTerm
import AppKit

/// Builds cell instances from SwiftTerm buffer for Metal rendering
final class CellGrid {
    // MARK: - Properties

    private let glyphAtlas: GlyphAtlas
    private var instances: [CellInstance] = []

    // Default colors (updated from theme)
    var defaultFgColor: simd_float4 = simd_float4(0.93, 0.93, 0.95, 1.0)
    var defaultBgColor: simd_float4 = simd_float4(0.04, 0.04, 0.05, 1.0)
    var cursorColor: simd_float4 = simd_float4(0.55, 0.36, 1.0, 1.0)
    var selectionColor: simd_float4 = simd_float4(0.35, 0.25, 0.55, 0.4)

    // Cursor state
    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var cursorVisible: Bool = true

    // Selection state
    var selectionStart: (row: Int, col: Int)?
    var selectionEnd: (row: Int, col: Int)?

    // ANSI color palette (16 basic colors)
    private var palette: [simd_float4] = []

    // MARK: - Initialization

    init(glyphAtlas: GlyphAtlas) {
        self.glyphAtlas = glyphAtlas
        setupDefaultPalette()
    }

    private func setupDefaultPalette() {
        // Default ANSI colors (can be updated from theme)
        palette = [
            simd_float4(0.10, 0.10, 0.12, 1.0),  // 0: Black
            simd_float4(0.95, 0.35, 0.45, 1.0),  // 1: Red
            simd_float4(0.30, 0.85, 0.55, 1.0),  // 2: Green
            simd_float4(1.00, 0.85, 0.35, 1.0),  // 3: Yellow
            simd_float4(0.40, 0.60, 1.00, 1.0),  // 4: Blue
            simd_float4(0.75, 0.45, 1.00, 1.0),  // 5: Magenta
            simd_float4(0.30, 0.85, 0.90, 1.0),  // 6: Cyan
            simd_float4(0.85, 0.85, 0.88, 1.0),  // 7: White
            simd_float4(0.40, 0.40, 0.45, 1.0),  // 8: Bright Black
            simd_float4(1.00, 0.50, 0.55, 1.0),  // 9: Bright Red
            simd_float4(0.45, 1.00, 0.65, 1.0),  // 10: Bright Green
            simd_float4(1.00, 0.92, 0.50, 1.0),  // 11: Bright Yellow
            simd_float4(0.55, 0.75, 1.00, 1.0),  // 12: Bright Blue
            simd_float4(0.85, 0.60, 1.00, 1.0),  // 13: Bright Magenta
            simd_float4(0.50, 1.00, 0.95, 1.0),  // 14: Bright Cyan
            simd_float4(1.00, 1.00, 1.00, 1.0),  // 15: Bright White
        ]
    }

    // MARK: - Theme

    func applyTheme(_ theme: Theme) {
        defaultFgColor = simd_float4(theme.foreground)
        defaultBgColor = simd_float4(theme.background)
        cursorColor = simd_float4(theme.cursor)
        selectionColor = simd_float4(theme.selection)

        // Update palette
        let themeColors: [NSColor] = [
            theme.black, theme.red, theme.green, theme.yellow,
            theme.blue, theme.magenta, theme.cyan, theme.white,
            theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
            theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite
        ]

        for (i, color) in themeColors.enumerated() {
            palette[i] = simd_float4(color)
        }
    }

    // MARK: - Building Instances

    func buildInstances(from terminal: Terminal, rows: Int, cols: Int) -> [CellInstance] {
        instances.removeAll(keepingCapacity: true)
        instances.reserveCapacity(rows * cols)

        for row in 0..<rows {
            guard let line = terminal.getLine(row: row) else { continue }

            var col = 0
            while col < cols {
                let charData = line[col]
                let instance = buildCellInstance(charData: charData, row: row, col: col)
                instances.append(instance)

                // Skip next cell for double-width characters
                if charData.width == 2 {
                    col += 2
                } else {
                    col += 1
                }
            }
        }

        return instances
    }

    private func buildCellInstance(charData: CharData, row: Int, col: Int) -> CellInstance {
        // Get codepoint
        let codepoint = UInt32(bitPattern: charData.code)

        // Determine colors from attribute
        let (fgColor, bgColor) = resolveColors(attribute: charData.attribute)

        // Check style flags using rawValue (CharacterStyle is OptionSet)
        let styleRaw = charData.attribute.style.rawValue
        let isBold = (styleRaw & CharacterStyle.bold.rawValue) != 0
        let isItalic = (styleRaw & CharacterStyle.italic.rawValue) != 0
        let isUnderline = (styleRaw & CharacterStyle.underline.rawValue) != 0
        let isCrossedOut = (styleRaw & CharacterStyle.crossedOut.rawValue) != 0
        let isInverse = (styleRaw & CharacterStyle.inverse.rawValue) != 0

        let glyphInfo = glyphAtlas.getGlyph(codepoint: codepoint, bold: isBold, italic: isItalic)

        // Build flags
        var flags: UInt32 = 0
        if isUnderline {
            flags |= CellInstance.flagUnderline
        }
        if isBold {
            flags |= CellInstance.flagBold
        }
        if isItalic {
            flags |= CellInstance.flagItalic
        }
        if isCrossedOut {
            flags |= CellInstance.flagStrikethrough
        }
        if isInverse {
            flags |= CellInstance.flagInverse
        }
        if charData.width == 2 {
            flags |= CellInstance.flagDoubleWidth
        }

        // Check if cursor is here
        if row == cursorRow && col == cursorCol && cursorVisible {
            flags |= CellInstance.flagCursor
        }

        // Check if selected
        if isSelected(row: row, col: col) {
            flags |= CellInstance.flagSelected
        }

        return CellInstance(
            position: simd_float2(Float(col), Float(row)),
            uvOffset: glyphInfo?.uvOffset ?? .zero,
            uvSize: glyphInfo?.uvSize ?? .zero,
            fgColor: fgColor,
            bgColor: bgColor,
            flags: flags
        )
    }

    // MARK: - Color Resolution

    private func resolveColors(attribute: Attribute) -> (fg: simd_float4, bg: simd_float4) {
        var fgColor = resolveColor(attribute.fg, isBackground: false)
        var bgColor = resolveColor(attribute.bg, isBackground: true)

        let styleRaw = attribute.style.rawValue

        // Handle inverse
        if (styleRaw & CharacterStyle.inverse.rawValue) != 0 {
            swap(&fgColor, &bgColor)
        }

        // Handle dim
        if (styleRaw & CharacterStyle.dim.rawValue) != 0 {
            fgColor = simd_float4(fgColor.x * 0.5, fgColor.y * 0.5, fgColor.z * 0.5, fgColor.w)
        }

        return (fgColor, bgColor)
    }

    private func resolveColor(_ color: SwiftTerm.Color, isBackground: Bool) -> simd_float4 {
        switch color {
        case .defaultColor:
            return isBackground ? defaultBgColor : defaultFgColor

        case .defaultInvertedColor:
            return isBackground ? defaultFgColor : defaultBgColor

        case .ansi256(let code):
            return ansi256ToColor(Int(code))

        case .trueColor(let r, let g, let b):
            return simd_float4(r: UInt8(r), g: UInt8(g), b: UInt8(b))
        }
    }

    private func ansi256ToColor(_ code: Int) -> simd_float4 {
        if code < 16 {
            // Standard ANSI colors
            return palette[code]
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

    // MARK: - Selection

    private func isSelected(row: Int, col: Int) -> Bool {
        guard let start = selectionStart, let end = selectionEnd else {
            return false
        }

        // Normalize selection direction
        let (startRow, startCol, endRow, endCol): (Int, Int, Int, Int)
        if start.row < end.row || (start.row == end.row && start.col <= end.col) {
            (startRow, startCol, endRow, endCol) = (start.row, start.col, end.row, end.col)
        } else {
            (startRow, startCol, endRow, endCol) = (end.row, end.col, start.row, start.col)
        }

        // Check if cell is within selection
        if row < startRow || row > endRow {
            return false
        }
        if row == startRow && col < startCol {
            return false
        }
        if row == endRow && col > endCol {
            return false
        }
        return true
    }
}
