import Metal
import CoreText
import CoreGraphics
import AppKit
import simd
import UniformTypeIdentifiers

/// Texture atlas for glyph caching
final class GlyphAtlas {
    // MARK: - Properties

    let device: MTLDevice
    let size: Int
    private(set) var texture: MTLTexture?

    private var glyphCache: [GlyphKey: GlyphInfo] = [:]
    private var font: NSFont
    private var packer: RectanglePacker

    // CoreGraphics context for rendering glyphs
    private var cgContext: CGContext?
    private var contextData: UnsafeMutableRawPointer?

    // Metrics
    private var cellWidth: CGFloat = 9
    private var cellHeight: CGFloat = 18
    private var ascent: CGFloat = 14
    private var descent: CGFloat = 4

    // MARK: - Initialization

    init(device: MTLDevice, size: Int = 2048) {
        self.device = device
        self.size = size
        self.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        self.packer = RectanglePacker(width: size, height: size)

        createTexture()
        createContext()
        calculateMetrics()

        // Pre-cache ASCII characters
        precacheASCII()

        logInfo("GlyphAtlas created: \(size)x\(size)", context: "GlyphAtlas")
    }

    deinit {
        if let data = contextData {
            data.deallocate()
        }
    }

    // MARK: - Setup

    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,  // Single-channel for alpha
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        // Use .shared on Apple Silicon (unified memory), .managed on Intel
        // .shared is simpler and doesn't require synchronize()
        #if arch(arm64)
        descriptor.storageMode = .shared
        let storageDesc = "shared"
        #else
        descriptor.storageMode = .managed
        let storageDesc = "managed"
        #endif

        texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Glyph Atlas"

        // Clear texture to black (transparent)
        clearTexture()

        logDebug("Atlas texture created (storageMode: \(storageDesc))", context: "GlyphAtlas")
    }

    private func clearTexture() {
        guard let texture = texture else { return }

        let bytesPerRow = size
        let data = [UInt8](repeating: 0, count: size * size)

        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: size, height: size, depth: 1)),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
    }

    private func createContext() {
        let bytesPerRow = size
        let totalBytes = size * size

        // Allocate memory for context
        contextData = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 8)
        memset(contextData, 0, totalBytes)

        // Create grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        cgContext = CGContext(
            data: contextData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        cgContext?.setAllowsAntialiasing(true)
        cgContext?.setShouldAntialias(true)
        cgContext?.setAllowsFontSmoothing(true)
        cgContext?.setShouldSmoothFonts(true)
    }

    private func calculateMetrics() {
        let ctFont = font as CTFont

        // Get font metrics
        ascent = CTFontGetAscent(ctFont)
        descent = CTFontGetDescent(ctFont)
        let leading = CTFontGetLeading(ctFont)

        cellHeight = ceil(ascent + descent + leading)

        // Calculate cell width from 'M' character
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let charSize = NSString("M").size(withAttributes: attributes)
        cellWidth = ceil(charSize.width)

        logDebug("Font metrics: cell=\(cellWidth)x\(cellHeight), ascent=\(ascent), descent=\(descent)", context: "GlyphAtlas")
    }

    // MARK: - Font

    func setFont(_ newFont: NSFont) {
        font = newFont
        calculateMetrics()

        // Clear cache and re-render
        glyphCache.removeAll()
        packer = RectanglePacker(width: size, height: size)
        clearTexture()

        // Re-cache ASCII
        precacheASCII()

        logInfo("Font changed: \(font.fontName) \(font.pointSize)pt", context: "GlyphAtlas")
    }

    // MARK: - Glyph Access

    func getGlyph(codepoint: UInt32, bold: Bool = false, italic: Bool = false) -> GlyphInfo? {
        let key = GlyphKey(codepoint: codepoint, bold: bold, italic: italic)

        // Return cached glyph
        if let cached = glyphCache[key] {
            return cached
        }

        // Render and cache new glyph
        return renderGlyph(key: key)
    }

    func getCellSize() -> (width: CGFloat, height: CGFloat) {
        return (cellWidth, cellHeight)
    }

    // MARK: - Rendering

    private func precacheASCII() {
        // Pre-cache printable ASCII (32-126)
        for codepoint: UInt32 in 32...126 {
            _ = getGlyph(codepoint: codepoint)
        }
        logDebug("Pre-cached \(glyphCache.count) ASCII glyphs", context: "GlyphAtlas")
    }

    private func renderGlyph(key: GlyphKey) -> GlyphInfo? {
        guard let context = cgContext, let texture = texture else { return nil }

        // Get font variant (NSFontManager.convert returns non-optional NSFont)
        var renderFont = font
        if key.flags & CellInstance.flagBold != 0 {
            renderFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if key.flags & CellInstance.flagItalic != 0 {
            renderFont = NSFontManager.shared.convert(renderFont, toHaveTrait: .italicFontMask)
        }

        let ctFont = renderFont as CTFont

        // Get glyph for codepoint
        var glyph: CGGlyph = 0
        var codepoints = [UniChar](repeating: 0, count: 2)
        let scalar = UnicodeScalar(key.codepoint)!
        let utf16 = String(scalar).utf16
        for (i, unit) in utf16.enumerated() where i < 2 {
            codepoints[i] = unit
        }

        let success = CTFontGetGlyphsForCharacters(ctFont, codepoints, &glyph, utf16.count)
        if !success || glyph == 0 {
            // Fallback to .notdef or space
            return createEmptyGlyph(key: key)
        }

        // Get glyph bounding box
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyph, &boundingRect, 1)

        var advance: CGSize = .zero
        CTFontGetAdvancesForGlyphs(ctFont, .default, &glyph, &advance, 1)

        // Calculate glyph size with padding
        let padding: CGFloat = 2
        let glyphWidth = Int(ceil(max(boundingRect.width, advance.width) + padding * 2))
        let glyphHeight = Int(ceil(cellHeight + padding * 2))

        // Allocate space in atlas
        var rect = packer.pack(width: glyphWidth, height: glyphHeight)
        if rect == nil {
            // Atlas full — evict all and rebuild ASCII cache
            logWarning("Atlas full, evicting \(glyphCache.count) glyphs", context: "GlyphAtlas")
            glyphCache.removeAll()
            packer = RectanglePacker(width: size, height: size)
            clearTexture()
            precacheASCII()
            rect = packer.pack(width: glyphWidth, height: glyphHeight)
        }
        guard let rect else {
            logError("Cannot allocate glyph after eviction", context: "GlyphAtlas")
            return nil
        }

        // Render glyph to context
        // IMPORTANT: CGContext has origin at bottom-left (y=0 at bottom)
        // but memory row 0 = visual top. Packer uses top-down coords (y=0 at top).
        // We need to convert packer coords to CG coords.
        context.saveGState()

        // Convert packer Y (top-down) to CGContext Y (bottom-up)
        // Packer rect.y=0 means top of atlas, which in CG coords is y=size-height
        let cgRectY = CGFloat(size - rect.y - glyphHeight)

        // Clear the glyph area in CG coordinates
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: CGFloat(rect.x), y: cgRectY, width: CGFloat(glyphWidth), height: CGFloat(glyphHeight)))

        // Set text color (white)
        context.setFillColor(gray: 1, alpha: 1)

        // Calculate position for baseline in CG coordinates
        // Baseline should be at cgRectY + padding + descent from bottom of glyph rect
        let x = CGFloat(rect.x) + padding - boundingRect.origin.x
        let y = cgRectY + padding + descent

        // Draw glyph
        var position = CGPoint(x: x, y: y)
        CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)

        context.restoreGState()

        // Copy rendered data to texture
        updateTexture(rect: rect, width: glyphWidth, height: glyphHeight)

        // Create glyph info - UV coordinates match texture position
        let info = GlyphInfo(
            uvOffset: simd_float2(Float(rect.x) / Float(size), Float(rect.y) / Float(size)),
            uvSize: simd_float2(Float(glyphWidth) / Float(size), Float(glyphHeight) / Float(size)),
            bearing: simd_float2(Float(boundingRect.origin.x), Float(boundingRect.origin.y)),
            advance: Float(advance.width),
            width: isDoubleWidth(key.codepoint) ? 2 : 1,
            height: UInt16(glyphHeight)
        )

        glyphCache[key] = info

        // Debug: log first few non-space glyphs
        if glyphCache.count <= 5 && key.codepoint > 32 {
            logDebug("Rendered glyph '\(UnicodeScalar(key.codepoint)!)' at rect(\(rect.x),\(rect.y)) uv(\(info.uvOffset.x),\(info.uvOffset.y)) size(\(info.uvSize.x),\(info.uvSize.y))", context: "GlyphAtlas")
        }

        return info
    }

    private func createEmptyGlyph(key: GlyphKey) -> GlyphInfo {
        // Return info for empty space
        let info = GlyphInfo(
            uvOffset: .zero,
            uvSize: .zero,
            bearing: .zero,
            advance: Float(cellWidth),
            width: 1,
            height: UInt16(cellHeight)
        )
        glyphCache[key] = info
        return info
    }

    private func updateTexture(rect: PackedRect, width: Int, height: Int) {
        guard let texture = texture, let data = contextData else { return }

        let srcBytesPerRow = size

        // CGContext memory layout: row 0 = visual TOP of context
        // We drew glyph at CG coords (rect.x, size - rect.y - height) which means:
        // - CG y coordinate starts at (size - rect.y - height)
        // - In memory, this corresponds to rows starting from rect.y (top-down)
        //
        // Memory row formula: memRow = size - 1 - cgY
        // For cgY = size - rect.y - height: memRow = size - 1 - (size - rect.y - height) = rect.y + height - 1
        // For cgY = size - rect.y - 1:      memRow = size - 1 - (size - rect.y - 1) = rect.y
        //
        // So the glyph occupies memory rows [rect.y, rect.y + height - 1] from top to bottom

        // Copy glyph data from CGContext memory directly (no flip needed, both are top-down)
        var glyphData = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let memRow = rect.y + row
            let srcRowOffset = memRow * srcBytesPerRow + rect.x
            let dstRowOffset = row * width
            let srcPtr = data.advanced(by: srcRowOffset).bindMemory(to: UInt8.self, capacity: width)
            for col in 0..<width {
                glyphData[dstRowOffset + col] = srcPtr[col]
            }
        }

        // Upload to texture at rect position (rect is in packer coordinates, top-left origin)
        // Metal texture also has origin at top-left, so coordinates match
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: rect.x, y: rect.y, z: 0),
                size: MTLSize(width: width, height: height, depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: glyphData,
            bytesPerRow: width
        )

        // Synchronize managed texture for GPU access (required on macOS with .managed storage)
        needsSynchronize = true
    }

    // MARK: - GPU Synchronization

    /// Flag indicating texture needs GPU sync
    private(set) var needsSynchronize: Bool = false

    /// Synchronize texture to GPU (call before rendering)
    /// Only needed on Intel Macs with .managed storage mode
    func synchronizeIfNeeded(commandBuffer: MTLCommandBuffer) {
        #if arch(arm64)
        // Apple Silicon uses .shared storage - no sync needed
        needsSynchronize = false
        return
        #else
        guard needsSynchronize, let texture = texture else { return }

        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.synchronize(resource: texture)
            blitEncoder.endEncoding()
        }
        needsSynchronize = false
        #endif
    }

    // MARK: - Debug

    /// Save glyph atlas texture to PNG for debugging
    func saveAtlasToPNG(path: String = "/tmp/glyph_atlas.png") {
        logDebug("Saving atlas to PNG: \(path)", context: "GlyphAtlas")

        guard let texture = texture else {
            logError("No texture to save", context: "GlyphAtlas")
            return
        }

        // Read texture data
        logDebug("Reading texture data \(texture.width)x\(texture.height)", context: "GlyphAtlas")
        let bytesPerRow = size
        var data = [UInt8](repeating: 0, count: size * size)
        texture.getBytes(
            &data,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: size, height: size, depth: 1)
            ),
            mipmapLevel: 0
        )

        // Convert grayscale to RGBA for PNG
        var rgbaData = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let gray = data[i]
            rgbaData[i * 4 + 0] = gray  // R
            rgbaData[i * 4 + 1] = gray  // G
            rgbaData[i * 4 + 2] = gray  // B
            rgbaData[i * 4 + 3] = 255   // A
        }

        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgbaData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            logError("Failed to create CGContext for PNG", context: "GlyphAtlas")
            return
        }

        guard let image = context.makeImage() else {
            logError("Failed to create CGImage", context: "GlyphAtlas")
            return
        }

        // Save as PNG
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            logError("Failed to create image destination", context: "GlyphAtlas")
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) {
            logInfo("Saved atlas to \(path)", context: "GlyphAtlas")
        } else {
            logError("Failed to finalize PNG", context: "GlyphAtlas")
        }
    }

    // MARK: - Helpers

    private func isDoubleWidth(_ codepoint: UInt32) -> Bool {
        // CJK and other double-width characters
        // Simplified check for common ranges
        return (0x1100...0x115F).contains(codepoint) ||  // Hangul Jamo
               (0x2E80...0x9FFF).contains(codepoint) ||  // CJK
               (0xAC00...0xD7A3).contains(codepoint) ||  // Hangul Syllables
               (0xF900...0xFAFF).contains(codepoint) ||  // CJK Compatibility
               (0xFE10...0xFE1F).contains(codepoint) ||  // Vertical Forms
               (0xFF00...0xFF60).contains(codepoint) ||  // Fullwidth
               (0x20000...0x2FFFF).contains(codepoint)   // CJK Extension B+
    }
}

// MARK: - Rectangle Packer (Simple Shelf Algorithm)

struct PackedRect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

final class RectanglePacker {
    private let width: Int
    private let height: Int

    // Shelf-based packing
    private var currentX: Int = 0
    private var currentY: Int = 0
    private var shelfHeight: Int = 0

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func pack(width w: Int, height h: Int) -> PackedRect? {
        // Check if fits in current shelf
        if currentX + w <= width && currentY + h <= height {
            let rect = PackedRect(x: currentX, y: currentY, width: w, height: h)
            currentX += w
            shelfHeight = max(shelfHeight, h)
            return rect
        }

        // Try next shelf
        currentX = 0
        currentY += shelfHeight
        shelfHeight = 0

        if currentY + h > height {
            return nil  // Atlas full
        }

        if w > width {
            return nil  // Too wide
        }

        let rect = PackedRect(x: currentX, y: currentY, width: w, height: h)
        currentX = w
        shelfHeight = h
        return rect
    }

    func reset() {
        currentX = 0
        currentY = 0
        shelfHeight = 0
    }
}
