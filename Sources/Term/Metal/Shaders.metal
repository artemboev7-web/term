#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Structures (must match Swift)

struct CellVertex {
    float2 position;
    float2 texCoord;
};

struct CellInstance {
    float2 position;     // Grid position (col, row)
    float2 uvOffset;     // UV offset in atlas
    float2 uvSize;       // UV size in atlas
    float2 _padding0;    // Alignment padding (Swift simd_float4 requires 16-byte alignment)
    float4 fgColor;      // Foreground (text) color
    float4 bgColor;      // Background color
    uint flags;          // Style flags
    uint _padding1;      // Alignment padding
};

struct Uniforms {
    float2 viewportSize;
    float2 cellSize;
    uint2 gridSize;
    float2 atlasSize;
    float time;
    int cursorRow;
    int cursorCol;
    uint cursorStyle;    // 0=block, 1=underline, 2=bar
    uint cursorBlink;    // 1=blink enabled, 0=solid
    int selectionStartRow;
    int selectionStartCol;
    int selectionEndRow;
    int selectionEndCol;
    float2 padding;
};

// Cursor style constants
constant uint CURSOR_BLOCK     = 0;
constant uint CURSOR_UNDERLINE = 1;
constant uint CURSOR_BAR       = 2;

// Flag constants
constant uint FLAG_UNDERLINE     = 1 << 0;
constant uint FLAG_BOLD          = 1 << 1;
constant uint FLAG_ITALIC        = 1 << 2;
constant uint FLAG_STRIKETHROUGH = 1 << 3;
constant uint FLAG_CURSOR        = 1 << 4;
constant uint FLAG_INVERSE       = 1 << 5;
constant uint FLAG_DOUBLE_WIDTH  = 1 << 6;
constant uint FLAG_SELECTED      = 1 << 7;

// MARK: - Vertex Output

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 fgColor;
    float4 bgColor;
    uint flags;
    float2 cellLocalPos;  // Position within cell (0-1)
};

// MARK: - Background Vertex Shader

vertex VertexOut vertex_background(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellInstance* instances [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    // Quad vertices (2 triangles = 6 vertices)
    float2 quadPositions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),  // Triangle 1
        float2(1, 0), float2(1, 1), float2(0, 1)   // Triangle 2
    };

    CellInstance inst = instances[instanceID];
    float2 localPos = quadPositions[vertexID];

    // Calculate cell width (double for CJK)
    float cellWidth = (inst.flags & FLAG_DOUBLE_WIDTH) ? 2.0 : 1.0;

    // Convert grid position to screen coordinates
    float2 cellPixelPos = inst.position * uniforms.cellSize;
    float2 cellPixelSize = float2(uniforms.cellSize.x * cellWidth, uniforms.cellSize.y);

    // Calculate vertex position in pixels
    float2 vertexPixelPos = cellPixelPos + localPos * cellPixelSize;

    // Convert to NDC (-1 to 1, Y flipped for Metal)
    float2 ndc;
    ndc.x = (vertexPixelPos.x / uniforms.viewportSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (vertexPixelPos.y / uniforms.viewportSize.y) * 2.0;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = float2(0);  // No texture for background
    out.fgColor = inst.fgColor;
    out.bgColor = inst.bgColor;
    out.flags = inst.flags;
    out.cellLocalPos = localPos;

    return out;
}

// MARK: - Background Fragment Shader

fragment float4 fragment_background(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    float4 color = in.bgColor;

    // Selection highlighting
    if (in.flags & FLAG_SELECTED) {
        color = mix(color, float4(0.3, 0.4, 0.6, 1.0), 0.5);
    }

    // Cursor rendering
    if (in.flags & FLAG_CURSOR) {
        // Blink animation (skip if blink disabled)
        float blink = 1.0;
        if (uniforms.cursorBlink != 0) {
            blink = sin(uniforms.time * 3.0) * 0.5 + 0.5;
        }

        if (blink > 0.5) {
            if (uniforms.cursorStyle == CURSOR_BLOCK) {
                // Block cursor: fill entire cell
                color = in.fgColor;
            } else if (uniforms.cursorStyle == CURSOR_UNDERLINE) {
                // Underline cursor: bottom 2 pixels
                if (in.cellLocalPos.y > 0.85) {
                    color = in.fgColor;
                }
            } else if (uniforms.cursorStyle == CURSOR_BAR) {
                // Bar cursor: left 2 pixels
                if (in.cellLocalPos.x < 0.1) {
                    color = in.fgColor;
                }
            }
        }
    }

    return color;
}

// MARK: - Glyph Vertex Shader

vertex VertexOut vertex_glyph(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellInstance* instances [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    float2 quadPositions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    // Texture coords match quad positions (no flip needed)
    // Both Metal texture and our atlas have origin at top-left
    float2 quadTexCoords[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    CellInstance inst = instances[instanceID];
    float2 localPos = quadPositions[vertexID];

    // Cell width for CJK
    float cellWidth = (inst.flags & FLAG_DOUBLE_WIDTH) ? 2.0 : 1.0;

    // Screen position
    float2 cellPixelPos = inst.position * uniforms.cellSize;
    float2 cellPixelSize = float2(uniforms.cellSize.x * cellWidth, uniforms.cellSize.y);
    float2 vertexPixelPos = cellPixelPos + localPos * cellPixelSize;

    // NDC
    float2 ndc;
    ndc.x = (vertexPixelPos.x / uniforms.viewportSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (vertexPixelPos.y / uniforms.viewportSize.y) * 2.0;

    // Texture coordinates in atlas
    float2 texCoord = inst.uvOffset + quadTexCoords[vertexID] * inst.uvSize;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = texCoord;
    out.fgColor = inst.fgColor;
    out.bgColor = inst.bgColor;
    out.flags = inst.flags;
    out.cellLocalPos = localPos;

    return out;
}

// MARK: - Glyph Fragment Shader

fragment float4 fragment_glyph(
    VertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Sample glyph alpha from atlas
    float alpha = glyphAtlas.sample(texSampler, in.texCoord).r;

    // DEBUG: Visualize alpha as white to verify glyph sampling works
    // return float4(alpha, alpha, alpha, 1.0);  // Shows glyph alpha as grayscale

    // DEBUG: Show UV coordinates as colors
    // return float4(in.texCoord.x * 20.0, in.texCoord.y * 20.0, alpha, 1.0);

    // Text color
    float4 textColor = in.fgColor;

    // Inverse video (cursor or selection)
    if ((in.flags & FLAG_CURSOR) || (in.flags & FLAG_INVERSE)) {
        textColor = in.bgColor;
    }

    // Discard fully transparent pixels
    if (alpha < 0.01) {
        discard_fragment();
    }

    return float4(textColor.rgb, textColor.a * alpha);
}

// MARK: - Decoration Fragment Shader (underline, strikethrough)

fragment float4 fragment_decoration(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    float4 color = float4(0);

    // Underline: bottom 1-2 pixels
    if (in.flags & FLAG_UNDERLINE) {
        if (in.cellLocalPos.y > 0.9) {
            color = in.fgColor;
        }
    }

    // Strikethrough: middle line
    if (in.flags & FLAG_STRIKETHROUGH) {
        if (in.cellLocalPos.y > 0.45 && in.cellLocalPos.y < 0.55) {
            color = in.fgColor;
        }
    }

    if (color.a < 0.01) {
        discard_fragment();
    }

    return color;
}

// MARK: - Cursor Shader (separate pass for cursor outline)

fragment float4 fragment_cursor(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    if (!(in.flags & FLAG_CURSOR)) {
        discard_fragment();
    }

    // Blink
    float blink = sin(uniforms.time * 3.0) * 0.5 + 0.5;
    if (blink < 0.5) {
        discard_fragment();
    }

    // Block cursor: fill entire cell
    return in.fgColor;
}

// MARK: - Simple Test Shader (for debugging)

struct TestVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex TestVertexOut vertex_test(
    uint vertexID [[vertex_id]],
    constant float2* positions [[buffer(0)]],
    constant float4* colors [[buffer(1)]]
) {
    TestVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.color = colors[vertexID];
    return out;
}

fragment float4 fragment_test(TestVertexOut in [[stage_in]]) {
    return in.color;
}
