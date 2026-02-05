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
    ├── DirtyTracker       — Partial update tracking
    └── Shaders.metal      — Vertex & fragment shaders
```

## Key Components

### ShaderTypes.swift
Shared data structures between Swift and Metal:
- `CellVertex` — Vertex data for quad rendering
- `CellInstance` — Per-cell data (position, colors, flags)
- `Uniforms` — Frame-level constants (cursor style, selection)
- `GlyphInfo` — Glyph atlas entry
- `MetalCursorStyle` — Block, underline, bar

### Shaders.metal
Metal shaders:
- `vertex_background` / `fragment_background` — Cell backgrounds with cursor
- `vertex_glyph` / `fragment_glyph` — Text rendering with atlas sampling
- `fragment_decoration` — Underline/strikethrough

### MetalRenderer.swift
Core renderer:
- Pipeline creation & management
- Buffer allocation (instances, uniforms)
- Multi-pass rendering (bg → glyphs → decorations)
- `renderWithBuffer()` for triple buffering

### GlyphAtlas.swift
Texture atlas for glyph caching:
- CoreText rendering to CGContext
- Shelf-based bin packing algorithm
- ASCII pre-caching for instant startup
- Support for bold/italic variants
- CJK double-width detection

### CellGrid.swift
Builds instance data from SwiftTerm buffer:
- Color resolution (ANSI 256, TrueColor)
- Style flags (bold, italic, underline, etc.)
- Cursor and selection tracking
- Theme color palette

### MetalTerminalView.swift
MTKView subclass:
- **CVDisplayLink** for vsync-synchronized rendering
- **Triple buffering** with rotating instance buffers
- Cursor blink with window focus awareness
- FPS counter for debugging
- Dirty tracking integration

### DirtyTracking.swift
Optimization for partial updates:
- Row-based dirty tracking
- Scroll region awareness
- Threshold-based full redraw
- Region merging

## Rendering Pipeline

```
1. Background Pass (opaque)
   └── Draw cell backgrounds
   └── Cursor rendering (block/underline/bar)
   └── Selection highlighting

2. Glyph Pass (alpha blend)
   └── Sample glyph atlas
   └── Apply fg color with inverse handling

3. Decoration Pass (alpha blend)
   └── Underline lines
   └── Strikethrough lines
```

## Performance Features

- **CVDisplayLink**: Vsync-synchronized, no timer jitter
- **Triple Buffering**: CPU writes while GPU reads
- **Instanced Rendering**: Single draw call per pass
- **Glyph Atlas**: GPU texture caching
- **Partial Updates**: Only redraw dirty regions
- **FPS Monitoring**: Log warnings when < 55 FPS

## Cursor Styles

| Style | Description |
|-------|-------------|
| Block | Full cell filled (default) |
| Underline | Bottom 2 pixels |
| Bar | Left 2 pixels (I-beam) |

Configured via `Settings.shared.cursorStyle` and `Settings.shared.cursorBlink`.

## Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `useMetalRenderer` | Bool | true | Enable GPU rendering |
| `cursorStyle` | CursorStyle | .block | Cursor appearance |
| `cursorBlink` | Bool | true | Cursor blink animation |

Settings changes emit notifications for runtime updates.

## Usage

Metal rendering is enabled by default. Toggle via Settings:

```swift
Settings.shared.useMetalRenderer = false  // Switch to SwiftTerm
Settings.shared.useMetalRenderer = true   // Switch to Metal
```

Or programmatically on a pane:

```swift
pane.setMetalRendererEnabled(false)
```

## Building

```bash
cd /path/to/term
swift build
```

## Debugging

```swift
// Get current FPS
let fps = metalView.currentFPS

// Pause/resume rendering
metalView.pauseRendering()
metalView.resumeRendering()
```

For GPU profiling, use Xcode's Metal System Trace in Instruments.

## Fallback

If Metal is unavailable (old hardware, VM), the view automatically
falls back to SwiftTerm's native NSView-based rendering.
