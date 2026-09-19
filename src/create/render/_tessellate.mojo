"""`DrawCommand`s to device-space triangles, with no GL in sight.

The GL backend's geometry is decided here rather than in `_gl_backend.mojo` so
that it is testable without a context, a window or a GPU: everything below is
arithmetic over `Float64` producing a `List[Float32]`, and
`tests/render/test_tessellate.mojo` asserts on the numbers directly.

**The transform is baked per vertex, not passed as a uniform.**
`_command.mojo` anticipates the matrix becoming a vertex-shader uniform, but a
per-command uniform forces one draw call per command, which is the whole cost
the batching exists to remove. Applying it on the CPU with the same
`create.math.matrix.apply` the CPU replay uses also means the two backends
cannot drift geometrically: a vertex here and a scanned pixel there come from
one function.

**Fill stops where the outline starts.** The CPU replay decides per pixel — a
pixel is fill *or* outline, never blended twice — so a translucent shape does
not darken under its own outline. Overlaying a full-size fill quad with a
outline ring would blend twice and diverge on every alpha edge, so a outlined
shape's fill is emitted inset to the outline's inner edge instead.

Outline width is resolved in device pixels through `outline_thickness_px` (so the
one-pixel floor is shared with the CPU path) and converted back to local units
where the ring has to follow a rotated edge.
"""

from std.math import abs, ceil, cos, max, min, sin, sqrt, pi

from create.math.matrix import Matrix, apply as mat_apply

from ._command import DrawCommand
from ._transform import pixel_scale, outline_thickness_px
from .color import Color

comptime _VERTEX_FLOATS = 9
"""`x, y, u, v, r, g, b, a, mode` — one interleaved vertex."""

comptime MODE_SOLID: Float32 = 0.0
"""Colour only — the fragment shader takes this branch without sampling, so a
solid's UVs are never read and solids batch with anything."""
comptime MODE_MASK: Float32 = 1.0
"""Glyph: the sampled red channel scales the vertex colour's alpha."""
comptime MODE_TEXTURE: Float32 = 2.0
"""Sprite: the sampled RGBA multiplies the vertex colour."""

comptime _MIN_CIRCLE_SEGMENTS = 12
comptime _MAX_CIRCLE_SEGMENTS = 256


def circle_segments(radius_px: Float64) -> Int:
    """How many segments a circle of this device radius is worth.

    One segment per pixel of radius is far finer than the eye needs and still
    cheap; the floor keeps a tiny circle from becoming a triangle, and the cap
    keeps a huge one from flooding the batch.
    """
    if radius_px <= 0.0:
        return _MIN_CIRCLE_SEGMENTS
    return max(
        _MIN_CIRCLE_SEGMENTS, min(_MAX_CIRCLE_SEGMENTS, Int(ceil(radius_px)))
    )


def _arc_segments(radius_px: Float64, span: Float64) -> Int:
    """How many segments one fillet arc is worth.

    `circle_segments` prorated by how much of a full turn the arc actually
    sweeps, with the same floor so a tiny sliver still reads as a curve
    rather than a corner cut off with a single straight edge.
    """
    var full = circle_segments(radius_px)
    var frac = abs(span) / (2.0 * pi)
    return max(_MIN_CIRCLE_SEGMENTS // 4, Int(ceil(Float64(full) * frac)))


struct VertexBuffer(Movable):
    """The frame's triangles, interleaved and ready to upload.

    One reused `List[Float32]`: `clear()` keeps the capacity, so a steady
    frame allocates nothing after the first.
    """

    var data: List[Float32]

    def __init__(out self):
        self.data = List[Float32]()

    def clear(mut self):
        """Drop the vertices, keep the allocation."""
        self.data.clear()

    def count(self) -> Int:
        """Vertices, not floats."""
        return len(self.data) // _VERTEX_FLOATS

    def push(
        mut self,
        x: Float64,
        y: Float64,
        u: Float64,
        v: Float64,
        color: Color,
        mode: Float32,
    ):
        """One vertex, already in device pixels."""
        self.data.append(Float32(x))
        self.data.append(Float32(y))
        self.data.append(Float32(u))
        self.data.append(Float32(v))
        self.data.append(Float32(Int(color.r)) / 255.0)
        self.data.append(Float32(Int(color.g)) / 255.0)
        self.data.append(Float32(Int(color.b)) / 255.0)
        self.data.append(Float32(Int(color.a)) / 255.0)
        self.data.append(mode)

    def triangle(
        mut self,
        ax: Float64,
        ay: Float64,
        bx: Float64,
        by: Float64,
        cx: Float64,
        cy: Float64,
        color: Color,
    ):
        """A solid triangle. `MODE_SOLID` never samples, so the UVs are
        unread and left at the origin."""
        self.push(ax, ay, 0.0, 0.0, color, MODE_SOLID)
        self.push(bx, by, 0.0, 0.0, color, MODE_SOLID)
        self.push(cx, cy, 0.0, 0.0, color, MODE_SOLID)

    def quad(
        mut self,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
        x2: Float64,
        y2: Float64,
        x3: Float64,
        y3: Float64,
        color: Color,
    ):
        """A solid quad as two triangles, corners in order around the edge."""
        self.triangle(x0, y0, x1, y1, x2, y2, color)
        self.triangle(x0, y0, x2, y2, x3, y3, color)


def _mapped_quad(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    color: Color,
):
    """The local axis-aligned box `[x0, x1] x [y0, y1]`, mapped by `m`.

    All four corners go through `m`, so a rotated box stays a rotated box
    rather than being re-derived as an axis-aligned device rect.
    """
    var a = mat_apply(m, x0, y0)
    var b = mat_apply(m, x1, y0)
    var c = mat_apply(m, x1, y1)
    var d = mat_apply(m, x0, y1)
    vb.quad(a[0], a[1], b[0], b[1], c[0], c[1], d[0], d[1], color)


def _segment_quad(
    mut vb: VertexBuffer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    width: Float64,
    color: Color,
):
    """A `width`-thick quad along the device segment `(x0, y0)`-`(x1, y1)`.

    Device space, because a outlined *edge* is a pixel-width band about a
    mapped line — unlike a outlined box's ring, which has to follow the shape
    in local space to survive a rotation.
    """
    var dx = x1 - x0
    var dy = y1 - y0
    var length = sqrt(dx * dx + dy * dy)
    if length == 0.0:
        return
    var nx = -dy / length * width / 2.0
    var ny = dx / length * width / 2.0
    vb.quad(
        x0 + nx,
        y0 + ny,
        x1 + nx,
        y1 + ny,
        x1 - nx,
        y1 - ny,
        x0 - nx,
        y0 - ny,
        color,
    )


def emit_rect(mut vb: VertexBuffer, c: DrawCommand, scale: Float64):
    """Fill quad plus, when outlined, a four-quad ring inset from the edge."""
    var m = c.transform
    var lx0 = c.geom[0] - c.geom[2] / 2.0
    var ly0 = c.geom[1] - c.geom[3] / 2.0
    var lx1 = c.geom[0] + c.geom[2] / 2.0
    var ly1 = c.geom[1] + c.geom[3] / 2.0

    if not c.style.outline_visible():
        if c.style.fill_enabled:
            _mapped_quad(vb, m, lx0, ly0, lx1, ly1, c.style.fill_color)
        return

    # The ring is built in local units so it follows a rotated edge, but its
    # thickness is decided in pixels so the CPU path's one-pixel floor holds.
    var sw = Float64(outline_thickness_px(c.style, m, scale)) / pixel_scale(
        m, scale
    )
    var ix0 = lx0 + sw
    var iy0 = ly0 + sw
    var ix1 = lx1 - sw
    var iy1 = ly1 - sw
    if ix0 >= ix1 or iy0 >= iy1:
        # Thicker than the rectangle: all outline, no interior left to fill.
        _mapped_quad(vb, m, lx0, ly0, lx1, ly1, c.style.outline_color)
        return

    if c.style.fill_enabled:
        # Inset, not full-size: see the module docstring on double blending.
        _mapped_quad(vb, m, ix0, iy0, ix1, iy1, c.style.fill_color)
    var sc = c.style.outline_color
    _mapped_quad(vb, m, lx0, ly0, lx1, iy0, sc)
    _mapped_quad(vb, m, lx0, iy1, lx1, ly1, sc)
    _mapped_quad(vb, m, lx0, iy0, ix0, iy1, sc)
    _mapped_quad(vb, m, ix1, iy0, lx1, iy1, sc)


def emit_circle(mut vb: VertexBuffer, c: DrawCommand, scale: Float64):
    """A fan for the fill and a ring of quads for the outline.

    Both are generated in local space and mapped per vertex, so a non-uniform
    transform turns the circle into the ellipse it should be.
    """
    var m = c.transform
    var cx = c.geom[0]
    var cy = c.geom[1]
    var r = c.geom[2]
    if r <= 0.0:
        return
    var sf = pixel_scale(m, scale)
    var n = circle_segments(r * sf)
    var step = 2.0 * pi / Float64(n)

    var inner = r - Float64(outline_thickness_px(c.style, m, scale)) / sf
    var outlined = c.style.outline_visible() and inner > 0.0
    # Matching the CPU replay: with a outline at least as wide as the radius,
    # a fill wins the whole disc and no ring is drawn at all.
    var solid_all = c.style.outline_visible() and inner <= 0.0
    var fill_r = inner if outlined else r
    var fill_c = c.style.fill_color
    var fill_on = c.style.fill_enabled
    if solid_all and not fill_on:
        fill_on = True
        fill_c = c.style.outline_color
        fill_r = r

    var centre = mat_apply(m, cx, cy)
    for i in range(n):
        var a0 = Float64(i) * step
        var a1 = Float64(i + 1) * step
        var c0 = cos(a0)
        var s0 = sin(a0)
        var c1 = cos(a1)
        var s1 = sin(a1)
        if fill_on:
            var p0 = mat_apply(m, cx + c0 * fill_r, cy + s0 * fill_r)
            var p1 = mat_apply(m, cx + c1 * fill_r, cy + s1 * fill_r)
            vb.triangle(
                centre[0], centre[1], p0[0], p0[1], p1[0], p1[1], fill_c
            )
        if outlined:
            var o0 = mat_apply(m, cx + c0 * r, cy + s0 * r)
            var o1 = mat_apply(m, cx + c1 * r, cy + s1 * r)
            var i0 = mat_apply(m, cx + c0 * inner, cy + s0 * inner)
            var i1 = mat_apply(m, cx + c1 * inner, cy + s1 * inner)
            vb.quad(
                i0[0],
                i0[1],
                o0[0],
                o0[1],
                o1[0],
                o1[1],
                i1[0],
                i1[1],
                c.style.outline_color,
            )


def emit_line(mut vb: VertexBuffer, c: DrawCommand, scale: Float64):
    """One quad. A line has no interior, so `fill` never applies."""
    if not c.style.outline_visible():
        return
    var m = c.transform
    var p0 = mat_apply(m, c.geom[0], c.geom[1])
    var p1 = mat_apply(m, c.geom[2], c.geom[3])
    _segment_quad(
        vb,
        p0[0],
        p0[1],
        p1[0],
        p1[1],
        Float64(outline_thickness_px(c.style, m, scale)),
        c.style.outline_color,
    )


def emit_triangle(mut vb: VertexBuffer, c: DrawCommand, scale: Float64):
    """The mapped triangle, plus a quad per edge when outlined.

    The outline is three edge quads rather than an inset triangle, matching the
    CPU replay, which outlines a triangle with three `line_pixels` calls.
    """
    var m = c.transform
    var p1 = mat_apply(m, c.geom[0], c.geom[1])
    var p2 = mat_apply(m, c.geom[2], c.geom[3])
    var p3 = mat_apply(m, c.geom[4], c.geom[5])
    if c.style.fill_enabled:
        vb.triangle(
            p1[0], p1[1], p2[0], p2[1], p3[0], p3[1], c.style.fill_color
        )
    if c.style.outline_visible():
        var w = Float64(outline_thickness_px(c.style, m, scale))
        var sc = c.style.outline_color
        _segment_quad(vb, p1[0], p1[1], p2[0], p2[1], w, sc)
        _segment_quad(vb, p2[0], p2[1], p3[0], p3[1], w, sc)
        _segment_quad(vb, p3[0], p3[1], p1[0], p1[1], w, sc)


def emit_letterbox(
    mut vb: VertexBuffer, c: DrawCommand, width: Int, height: Int
):
    """The bars outside the device content rect — the one untransformed kind.

    `geom` is already in framebuffer pixels (see `letterbox_command`), so the
    command's matrix is the identity and applying it would be meaningless
    rather than merely redundant. `width` and `height` are the drawable's, not
    the viewport's: the bars have to reach the real edge of the frame.
    """
    var cx0 = c.geom[0]
    var cy0 = c.geom[1]
    var cx1 = c.geom[2]
    var cy1 = c.geom[3]
    var w = Float64(width)
    var h = Float64(height)
    var col = c.style.fill_color
    if cy0 > 0.0:
        vb.quad(0.0, 0.0, w, 0.0, w, cy0, 0.0, cy0, col)
    if cy1 < h:
        vb.quad(0.0, cy1, w, cy1, w, h, 0.0, h, col)
    if cx0 > 0.0:
        vb.quad(0.0, cy0, cx0, cy0, cx0, cy1, 0.0, cy1, col)
    if cx1 < w:
        vb.quad(cx1, cy0, w, cy0, w, cy1, cx1, cy1, col)


def emit_sprite(mut vb: VertexBuffer, c: DrawCommand, scale: Float64):
    """One textured quad, axis-aligned in device space.

    Deliberately not a `_mapped_quad`: the CPU replay maps the anchor and then
    blits an upright rectangle around it, so a rotated transform turns a
    sprite's *position* but not the sprite. Mapping four corners here would
    rotate the image too and the two backends would diverge. The rounding
    matches `Backend._sprite`'s for the same reason.

    `v` grows with device y, which grows downward, so row 0 of the image
    lands at the top of the quad and the sprite is not flipped.
    """
    var m = c.transform
    var p = mat_apply(m, c.geom[0], c.geom[1])
    var sf = pixel_scale(m, scale)
    var dw = Float64(max(Int(c.geom[2] * sf + 0.5), 1))
    var dh = Float64(max(Int(c.geom[3] * sf + 0.5), 1))
    var x0 = Float64(Int(p[0]) - Int(dw) // 2)
    var y0 = Float64(Int(p[1]) - Int(dh) // 2)
    var x1 = x0 + dw
    var y1 = y0 + dh
    # White, so `MODE_TEXTURE`'s multiply passes the sampled pixels through.
    var tint = Color.WHITE
    vb.push(x0, y0, 0.0, 0.0, tint, MODE_TEXTURE)
    vb.push(x1, y0, 1.0, 0.0, tint, MODE_TEXTURE)
    vb.push(x1, y1, 1.0, 1.0, tint, MODE_TEXTURE)
    vb.push(x0, y0, 0.0, 0.0, tint, MODE_TEXTURE)
    vb.push(x1, y1, 1.0, 1.0, tint, MODE_TEXTURE)
    vb.push(x0, y1, 0.0, 1.0, tint, MODE_TEXTURE)


def emit_glyph(
    mut vb: VertexBuffer,
    x: Float64,
    y: Float64,
    w: Float64,
    h: Float64,
    u0: Float64,
    v0: Float64,
    u1: Float64,
    v1: Float64,
    color: Color,
):
    """One glyph quad in device pixels, sampling `[u0, u1] x [v0, v1]`.

    The rect is already placed — `TextRenderer.layout` decided where, which is
    why nothing about alignment or pen advance appears here. `MODE_MASK` makes
    the sampled coverage scale the colour's alpha, matching `blit_glyph`.
    """
    vb.push(x, y, u0, v0, color, MODE_MASK)
    vb.push(x + w, y, u1, v0, color, MODE_MASK)
    vb.push(x + w, y + h, u1, v1, color, MODE_MASK)
    vb.push(x, y, u0, v0, color, MODE_MASK)
    vb.push(x + w, y + h, u1, v1, color, MODE_MASK)
    vb.push(x, y + h, u0, v1, color, MODE_MASK)
