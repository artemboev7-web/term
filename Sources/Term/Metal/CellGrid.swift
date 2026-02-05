import simd
import AppKit

/// Builds cell instances from terminal buffer for Metal rendering
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

    // Selection manager reference
    var selectionManager: SelectionManager?

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

    // Debug: track build calls
    private var buildCount: Int = 0

    func buildInstances(from terminal: TerminalEmulator, rows: Int, cols: Int) -> [CellInstance] {
        instances.removeAll(keepingCapacity: true)
        instances.reserveCapacity(rows * cols)

        var linesProcessed = 0
        for row in 0..<rows {
            guard let line = terminal.getLine(row: row) else { continue }
            linesProcessed += 1

            var col = 0
            while col < cols {
                let cell = line[col]
                let instance = buildCellInstance(cell: cell, row: row, col: col)
                instances.append(instance)

                // Skip next cell for double-width characters
                if cell.width == 2 {
                    col += 2
                } else {
                    col += 1
                }
            }
        }

        // Log first few builds for debugging
        buildCount += 1
        if buildCount <= 3 {
            logDebug("buildInstances[\(buildCount)]: \(instances.count) instances from \(linesProcessed)/\(rows) lines", context: "CellGrid")
        }

        return instances
    }

    private func buildCellInstance(cell: TerminalCell, row: Int, col: Int) -> CellInstance {
        // Get codepoint
        let codepoint = cell.codepoint

        // Determine colors from attribute
        let (fgColor, bgColor) = resolveColors(attribute: cell.attribute)

        // Check style flags
        let style = cell.attribute.style
        let isBold = style.contains(.bold)
        let isItalic = style.contains(.italic)
        let isUnderline = style.contains(.underline)
        let isStrikethrough = style.contains(.strikethrough)
        let isInverse = style.contains(.inverse)

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
        if isStrikethrough {
            flags |= CellInstance.flagStrikethrough
        }
        if isInverse {
            flags |= CellInstance.flagInverse
        }
        if cell.width == 2 {
            flags |= CellInstance.flagDoubleWidth
        }

        // Check if cursor is here
        if row == cursorRow && col == cursorCol && cursorVisible {
            flags |= CellInstance.flagCursor
        }

        // Check if selected
        if let selection = selectionManager, selection.isSelected(row: row, col: col) {
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

    private func resolveColors(attribute: CellAttribute) -> (fg: simd_float4, bg: simd_float4) {
        var fgColor = resolveColor(attribute.fg, isBackground: false)
        var bgColor = resolveColor(attribute.bg, isBackground: true)

        // Handle inverse
        if attribute.style.contains(.inverse) {
            swap(&fgColor, &bgColor)
        }

        // Handle dim
        if attribute.style.contains(.dim) {
            fgColor = simd_float4(fgColor.x * 0.5, fgColor.y * 0.5, fgColor.z * 0.5, fgColor.w)
        }

        return (fgColor, bgColor)
    }

    private func resolveColor(_ color: TerminalColor, isBackground: Bool) -> simd_float4 {
        return color.toFloat4(
            palette: palette,
            isBackground: isBackground,
            defaultFg: defaultFgColor,
            defaultBg: defaultBgColor
        )
    }
}
