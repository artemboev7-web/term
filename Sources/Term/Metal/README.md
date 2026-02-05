# Metal Renderer for Term

GPU-accelerated terminal rendering using Apple Metal, inspired by Ghostty.

## Architecture

```
TerminalPaneView
├── LocalProcessTerminalView (SwiftTerm)
│   └── Handles: shell/pty, input, buffer management
└── MetalTerminalView (Metal overlay)
    ├── MetalRenderer      — Pipeline & command encoding
    ├── GlyphAtlas         — Texture atlas for glyphs
    ├── CellGrid           — Instance buffer builder
    └── Shaders.metal      — Vertex & fragment shaders
```

## Key Components

### ShaderTypes.swift
Shared data structures between Swift and Metal:
- `CellVertex` — Vertex data for quad rendering
- `CellInstance` — Per-cell data (position, colors, flags)
- `Uniforms` — Frame-level constants
- `GlyphInfo` — Glyph atlas entry

### Shaders.metal
Metal shaders:
- `vertex_background` / `fragment_background` — Cell backgrounds
- `vertex_glyph` / `fragment_glyph` — Text rendering with atlas sampling
- `fragment_decoration` — Underline/strikethrough
- `fragment_cursor` — Cursor with blink animation

### MetalRenderer.swift
Core renderer:
- Pipeline creation & management
- Buffer allocation (instances, uniforms)
- Multi-pass rendering (bg → glyphs → decorations)

### GlyphAtlas.swift
Texture atlas for glyph caching:
- CoreText rendering to CGContext
- Shelf-based bin packing algorithm
- ASCII pre-caching for instant startup
- Support for bold/italic variants

### CellGrid.swift
Builds instance data from SwiftTerm buffer:
- Color resolution (ANSI 256, TrueColor)
- Style flags (bold, italic, underline, etc.)
- Cursor and selection tracking

### MetalTerminalView.swift
MTKView subclass:
- Syncs with SwiftTerm buffer
- Theme and font updates
- 60fps render loop

### DirtyTracking.swift
Optimization for partial updates:
- Row-based dirty tracking
- Scroll region awareness
- Threshold-based full redraw

## Rendering Pipeline

```
1. Background Pass (opaque)
   └── Draw cell backgrounds with instanced quads

2. Glyph Pass (alpha blend)
   └── Sample glyph atlas, apply fg color

3. Decoration Pass (alpha blend)
   └── Underline, strikethrough lines
```

## Performance

- **Instanced rendering**: Single draw call per pass
- **Glyph atlas**: GPU texture caching
- **Partial updates**: Only redraw dirty regions
- **60 FPS target**: Smooth scrolling & animation

## Usage

Metal rendering is enabled by default. Set `useMetalRenderer = false` in
`TerminalPaneView` to fall back to SwiftTerm's native rendering.

## Building

The Metal files are included in Package.swift sources. No additional
configuration needed.

```bash
swift build
```

## Debug

For Metal debugging, use Xcode's GPU Frame Capture or
Instruments Metal System Trace.
