import Metal
import MetalKit
import simd
import AppKit

/// GPU-accelerated terminal renderer using Metal
final class MetalRenderer {
    // MARK: - Metal Objects

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var library: MTLLibrary!

    // Render pipelines
    private var backgroundPipeline: MTLRenderPipelineState!
    private var glyphPipeline: MTLRenderPipelineState!
    private var decorationPipeline: MTLRenderPipelineState!
    private var cursorPipeline: MTLRenderPipelineState!

    // Buffers
    private var instanceBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer!

    // Glyph atlas
    var glyphAtlas: GlyphAtlas!

    // State
    private var uniforms = Uniforms(
        viewportSize: .zero,
        cellSize: simd_float2(9, 18),
        gridSize: simd_uint2(80, 24),
        atlasSize: simd_float2(2048, 2048),
        time: 0,
        cursorRow: 0,
        cursorCol: 0,
        selectionStartRow: -1,
        selectionStartCol: -1,
        selectionEndRow: -1,
        selectionEndCol: -1
    )

    private var instanceCount: Int = 0
    private var maxInstances: Int = 80 * 50  // Dynamic, grows as needed

    // MARK: - Initialization

    init?() {
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            logError("Metal is not supported on this device", context: "MetalRenderer")
            return nil
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            logError("Failed to create command queue", context: "MetalRenderer")
            return nil
        }
        self.commandQueue = commandQueue

        logInfo("Metal device: \(device.name)", context: "MetalRenderer")

        // Setup pipelines
        do {
            try setupPipelines()
            try setupBuffers()
            setupGlyphAtlas()
            logInfo("MetalRenderer initialized successfully", context: "MetalRenderer")
        } catch {
            logError("Failed to setup MetalRenderer: \(error)", context: "MetalRenderer")
            return nil
        }
    }

    // MARK: - Setup

    private func setupPipelines() throws {
        // Load shader library from source
        let source = try loadShaderSource()
        library = try device.makeLibrary(source: source, options: nil)

        // Pixel format for rendering
        let pixelFormat: MTLPixelFormat = .bgra8Unorm

        // Background pipeline (opaque)
        backgroundPipeline = try createPipeline(
            vertexFunction: "vertex_background",
            fragmentFunction: "fragment_background",
            pixelFormat: pixelFormat,
            blendEnabled: false,
            label: "Background"
        )

        // Glyph pipeline (alpha blending)
        glyphPipeline = try createPipeline(
            vertexFunction: "vertex_glyph",
            fragmentFunction: "fragment_glyph",
            pixelFormat: pixelFormat,
            blendEnabled: true,
            label: "Glyph"
        )

        // Decoration pipeline (underline, strikethrough)
        decorationPipeline = try createPipeline(
            vertexFunction: "vertex_glyph",
            fragmentFunction: "fragment_decoration",
            pixelFormat: pixelFormat,
            blendEnabled: true,
            label: "Decoration"
        )

        // Cursor pipeline
        cursorPipeline = try createPipeline(
            vertexFunction: "vertex_background",
            fragmentFunction: "fragment_cursor",
            pixelFormat: pixelFormat,
            blendEnabled: true,
            label: "Cursor"
        )

        logDebug("Render pipelines created", context: "MetalRenderer")
    }

    private func createPipeline(
        vertexFunction: String,
        fragmentFunction: String,
        pixelFormat: MTLPixelFormat,
        blendEnabled: Bool,
        label: String
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label

        guard let vertexFunc = library.makeFunction(name: vertexFunction),
              let fragmentFunc = library.makeFunction(name: fragmentFunction) else {
            throw MetalError.shaderNotFound("\(vertexFunction) or \(fragmentFunction)")
        }

        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        if blendEnabled {
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func loadShaderSource() throws -> String {
        // Try bundle resource first (for packaged app)
        if let bundlePath = Bundle.main.path(forResource: "Shaders", ofType: "metal") {
            return try String(contentsOfFile: bundlePath, encoding: .utf8)
        }

        // Try bundle resourceURL (for Swift PM resources)
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Shaders.metal"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return try String(contentsOfFile: resourceURL.path, encoding: .utf8)
        }

        // Development fallback paths
        let fallbackPaths = [
            // Mac development
            NSString("~/Projects/term/Sources/Term/Metal/Shaders.metal").expandingTildeInPath,
            // Linux VM
            "/root/Projects/term/Sources/Term/Metal/Shaders.metal",
            // Relative to executable
            "./Sources/Term/Metal/Shaders.metal"
        ]

        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                logDebug("Loading shaders from: \(path)", context: "MetalRenderer")
                return try String(contentsOfFile: path, encoding: .utf8)
            }
        }

        throw MetalError.shaderNotFound("Shaders.metal")
    }

    private func setupBuffers() throws {
        // Instance buffer for cell data
        let instanceSize = MemoryLayout<CellInstance>.stride * maxInstances
        guard let buffer = device.makeBuffer(length: instanceSize, options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed("instance buffer")
        }
        instanceBuffer = buffer
        instanceBuffer?.label = "Cell Instances"

        // Uniform buffer
        let uniformSize = MemoryLayout<Uniforms>.stride
        guard let uniBuffer = device.makeBuffer(length: uniformSize, options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed("uniform buffer")
        }
        uniformBuffer = uniBuffer
        uniformBuffer.label = "Uniforms"

        logDebug("Buffers created: instances=\(instanceSize)B, uniforms=\(uniformSize)B", context: "MetalRenderer")
    }

    private func setupGlyphAtlas() {
        glyphAtlas = GlyphAtlas(device: device, size: 2048)
        uniforms.atlasSize = simd_float2(Float(glyphAtlas.size), Float(glyphAtlas.size))
    }

    // MARK: - Configuration

    func setCellSize(_ width: CGFloat, _ height: CGFloat) {
        uniforms.cellSize = simd_float2(Float(width), Float(height))
    }

    func setGridSize(cols: Int, rows: Int) {
        uniforms.gridSize = simd_uint2(UInt32(cols), UInt32(rows))
    }

    func setCursor(row: Int, col: Int) {
        uniforms.cursorRow = Int32(row)
        uniforms.cursorCol = Int32(col)
    }

    func setCursorStyle(_ style: MetalCursorStyle) {
        uniforms.cursorStyle = style.rawValue
    }

    func setCursorBlink(_ enabled: Bool) {
        uniforms.cursorBlink = enabled ? 1 : 0
    }

    func setSelection(startRow: Int, startCol: Int, endRow: Int, endCol: Int) {
        uniforms.selectionStartRow = Int32(startRow)
        uniforms.selectionStartCol = Int32(startCol)
        uniforms.selectionEndRow = Int32(endRow)
        uniforms.selectionEndCol = Int32(endCol)
    }

    func clearSelection() {
        uniforms.selectionStartRow = -1
        uniforms.selectionStartCol = -1
        uniforms.selectionEndRow = -1
        uniforms.selectionEndCol = -1
    }

    // MARK: - Rendering

    func updateInstances(_ instances: [CellInstance]) {
        guard let buffer = instanceBuffer else { return }

        instanceCount = min(instances.count, maxInstances)
        if instanceCount == 0 { return }

        let ptr = buffer.contents().bindMemory(to: CellInstance.self, capacity: maxInstances)
        for i in 0..<instanceCount {
            ptr[i] = instances[i]
        }
    }

    func render(in view: MTKView, drawable: CAMetalDrawable) {
        // Update time for animations
        uniforms.time += 1.0 / 60.0  // Assuming 60fps

        // Use bounds (points) not drawableSize (pixels) — cellSize is in points
        uniforms.viewportSize = simd_float2(
            Float(view.bounds.width),
            Float(view.bounds.height)
        )

        // Update uniforms buffer
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Terminal Render"

        // Render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.label = "Terminal Encoder"

        if instanceCount > 0 {
            // Pass 1: Backgrounds
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)

            // Pass 2: Glyphs
            if let atlasTexture = glyphAtlas.texture {
                encoder.setRenderPipelineState(glyphPipeline)
                encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(atlasTexture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
            }

            // Pass 3: Decorations (underline, strikethrough)
            encoder.setRenderPipelineState(decorationPipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Render with external instance buffer (for triple buffering)
    func renderWithBuffer(in view: MTKView, drawable: CAMetalDrawable, instanceBuffer: MTLBuffer?, instanceCount: Int, onComplete: (() -> Void)? = nil) {
        guard let instanceBuffer = instanceBuffer, instanceCount > 0 else {
            onComplete?()
            return
        }

        // Update time for animations
        uniforms.time += 1.0 / 60.0

        // Use bounds (points) not drawableSize (pixels) — cellSize is in points
        uniforms.viewportSize = simd_float2(
            Float(view.bounds.width),
            Float(view.bounds.height)
        )

        // Update uniforms buffer
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Terminal Render (Triple Buffer)"

        // Synchronize glyph atlas texture if needed (macOS .managed storage)
        glyphAtlas.synchronizeIfNeeded(commandBuffer: commandBuffer)

        // Render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = view.clearColor

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.label = "Terminal Encoder"

        // Pass 1: Backgrounds
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)

        // Pass 2: Glyphs
        if let atlasTexture = glyphAtlas.texture {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        // Pass 3: Decorations (underline, strikethrough)
        encoder.setRenderPipelineState(decorationPipeline)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)

        encoder.endEncoding()

        // Signal completion for triple buffer synchronization
        if let onComplete {
            commandBuffer.addCompletedHandler { _ in onComplete() }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Font Configuration

    func setFont(_ font: NSFont) {
        glyphAtlas.setFont(font)

        // Update cell size based on font metrics
        let fontAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let charSize = NSString("W").size(withAttributes: fontAttributes)
        setCellSize(charSize.width, charSize.height)

        logDebug("Font set: \(font.fontName) \(font.pointSize)pt, cell: \(charSize)", context: "MetalRenderer")
    }
}

// MARK: - Errors

enum MetalError: Error, LocalizedError {
    case shaderNotFound(String)
    case bufferCreationFailed(String)
    case pipelineCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .shaderNotFound(let name):
            return "Shader not found: \(name)"
        case .bufferCreationFailed(let name):
            return "Failed to create buffer: \(name)"
        case .pipelineCreationFailed(let name):
            return "Failed to create pipeline: \(name)"
        }
    }
}
