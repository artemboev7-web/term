import simd
import AppKit

// MARK: - Shared Types (Swift <-> Metal)

/// Vertex data for a single cell quad
struct CellVertex {
    var position: simd_float2    // Screen position (NDC)
    var texCoord: simd_float2    // UV coordinates in glyph atlas
}

/// Per-instance data for instanced rendering
struct CellInstance {
    var position: simd_float2    // Cell position in grid coordinates
    var uvOffset: simd_float2    // UV offset in atlas (top-left)
    var uvSize: simd_float2      // UV size in atlas
    var fgColor: simd_float4     // Foreground color (text)
    var bgColor: simd_float4     // Background color
    var flags: UInt32            // Bit flags: underline, bold, italic, strikethrough, cursor
    var padding: UInt32 = 0      // Alignment padding

    // Flag bits
    static let flagUnderline: UInt32     = 1 << 0
    static let flagBold: UInt32          = 1 << 1
    static let flagItalic: UInt32        = 1 << 2
    static let flagStrikethrough: UInt32 = 1 << 3
    static let flagCursor: UInt32        = 1 << 4
    static let flagInverse: UInt32       = 1 << 5
    static let flagDoubleWidth: UInt32   = 1 << 6  // CJK characters
    static let flagSelected: UInt32      = 1 << 7
}

/// Cursor style enum (matches Settings.CursorStyle)
enum MetalCursorStyle: UInt32 {
    case block = 0
    case underline = 1
    case bar = 2
}

/// Uniform buffer for render pass
struct Uniforms {
    var viewportSize: simd_float2     // Viewport dimensions in pixels
    var cellSize: simd_float2         // Cell size in pixels (width, height)
    var gridSize: simd_uint2          // Terminal grid size (cols, rows)
    var atlasSize: simd_float2        // Glyph atlas texture size
    var time: Float                   // For cursor blink animation
    var cursorRow: Int32              // Cursor position
    var cursorCol: Int32
    var cursorStyle: UInt32 = 0       // 0=block, 1=underline, 2=bar
    var cursorBlink: UInt32 = 1       // 1=blink enabled, 0=solid
    var selectionStartRow: Int32      // Selection range
    var selectionStartCol: Int32
    var selectionEndRow: Int32
    var selectionEndCol: Int32
    var padding: simd_float2 = .zero  // Alignment
}

// MARK: - Glyph Atlas Entry

/// Information about a glyph in the atlas
struct GlyphInfo {
    var uvOffset: simd_float2     // Top-left UV in atlas
    var uvSize: simd_float2       // Size in UV coordinates
    var bearing: simd_float2      // Glyph bearing (offset from baseline)
    var advance: Float            // Horizontal advance
    var width: UInt16             // 1 for normal, 2 for CJK
    var height: UInt16            // Glyph height in pixels
}

/// Key for glyph cache lookup
struct GlyphKey: Hashable {
    let codepoint: UInt32
    let flags: UInt32  // bold, italic

    init(codepoint: UInt32, bold: Bool = false, italic: Bool = false) {
        self.codepoint = codepoint
        var f: UInt32 = 0
        if bold { f |= CellInstance.flagBold }
        if italic { f |= CellInstance.flagItalic }
        self.flags = f
    }
}

// MARK: - Color Helpers

extension simd_float4 {
    /// Create from NSColor (normalized 0-1)
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        self.init(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent)
        )
    }

    /// Create from RGB components (0-255)
    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.init(
            Float(r) / 255.0,
            Float(g) / 255.0,
            Float(b) / 255.0,
            Float(a) / 255.0
        )
    }

    /// Create from 16-bit color components
    init(r16: UInt16, g16: UInt16, b16: UInt16) {
        self.init(
            Float(r16) / 65535.0,
            Float(g16) / 65535.0,
            Float(b16) / 65535.0,
            1.0
        )
    }
}
