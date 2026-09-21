"""`RenderCommand`s to device-space triangles, with no GL in sight.

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

from ._command import RenderCommand
from ._fillet import corner_fillet, rect_corner_radius, triangle_corner_radius
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


def _corner_fan(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    ccx: Float64,
    ccy: Float64,
    r: Float64,
    angle0: Float64,
    span: Float64,
    n: Int,
    color: Color,
):
    """A solid fan of `n` segments sweeping `span` radians from `angle0`,
    every vertex mapped individually so a sheared corner still comes out as
    a genuine ellipse arc. The rect's corners always sweep a fixed quarter
    turn (`span = pi/2`); the triangle's sweep `pi - theta` per vertex, so
    `span` is a parameter here rather than the quarter turn this used to
    hardcode."""
    var step = span / Float64(n)
    var centre = mat_apply(m, ccx, ccy)
    for i in range(n):
        var a0 = angle0 + Float64(i) * step
        var a1 = angle0 + Float64(i + 1) * step
        var p0 = mat_apply(m, ccx + cos(a0) * r, ccy + sin(a0) * r)
        var p1 = mat_apply(m, ccx + cos(a1) * r, ccy + sin(a1) * r)
        vb.triangle(centre[0], centre[1], p0[0], p0[1], p1[0], p1[1], color)


def _corner_ring_fan(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    ccx: Float64,
    ccy: Float64,
    r_outer: Float64,
    r_inner: Float64,
    angle0: Float64,
    n: Int,
    color: Color,
):
    """A quarter annulus between `r_inner` and `r_outer`, same centre —
    degenerates to a solid `_corner_fan` when the inset radius has
    collapsed, matching `emit_circle`'s own solid-disc fallback."""
    if r_inner <= 0.0:
        _corner_fan(vb, m, ccx, ccy, r_outer, angle0, pi / 2.0, n, color)
        return
    var step = (pi / 2.0) / Float64(n)
    for i in range(n):
        var a0 = angle0 + Float64(i) * step
        var a1 = angle0 + Float64(i + 1) * step
        var o0 = mat_apply(m, ccx + cos(a0) * r_outer, ccy + sin(a0) * r_outer)
        var o1 = mat_apply(m, ccx + cos(a1) * r_outer, ccy + sin(a1) * r_outer)
        var i0 = mat_apply(m, ccx + cos(a0) * r_inner, ccy + sin(a0) * r_inner)
        var i1 = mat_apply(m, ccx + cos(a1) * r_inner, ccy + sin(a1) * r_inner)
        vb.quad(i0[0], i0[1], o0[0], o0[1], o1[0], o1[1], i1[0], i1[1], color)


def _rounded_rect_fill(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    r: Float64,
    sf: Float64,
    color: Color,
):
    """The local-space cross decomposition: a full-height centre band, a
    shorter band on each side, and a quarter-circle fan at each corner —
    the same split `_backend.mojo::_rect`'s uniform branch uses, cheap here
    because every vertex is mapped individually anyway."""
    _mapped_quad(vb, m, x0 + r, y0, x1 - r, y1, color)
    _mapped_quad(vb, m, x0, y0 + r, x0 + r, y1 - r, color)
    _mapped_quad(vb, m, x1 - r, y0 + r, x1, y1 - r, color)
    var n = _arc_segments(r * sf, pi / 2.0)
    _corner_fan(vb, m, x0 + r, y0 + r, r, pi, pi / 2.0, n, color)
    _corner_fan(vb, m, x1 - r, y0 + r, r, 3.0 * pi / 2.0, pi / 2.0, n, color)
    _corner_fan(vb, m, x1 - r, y1 - r, r, 0.0, pi / 2.0, n, color)
    _corner_fan(vb, m, x0 + r, y1 - r, r, pi / 2.0, pi / 2.0, n, color)


def _rounded_rect_ring(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    ix0: Float64,
    iy0: Float64,
    ix1: Float64,
    iy1: Float64,
    r: Float64,
    inner_r: Float64,
    sf: Float64,
    color: Color,
):
    """The outline ring's own cross decomposition: four straight bands
    between the tangent points, plus a corner annulus fan at each corner.
    Inner and outer corner centres coincide (insetting by `sw` shrinks the
    radius by exactly `sw` too), so each corner is one concentric fan."""
    _mapped_quad(vb, m, x0 + r, iy1, x1 - r, y1, color)
    _mapped_quad(vb, m, x0 + r, y0, x1 - r, iy0, color)
    _mapped_quad(vb, m, x0, y0 + r, ix0, y1 - r, color)
    _mapped_quad(vb, m, ix1, y0 + r, x1, y1 - r, color)
    var n = _arc_segments(r * sf, pi / 2.0)
    _corner_ring_fan(vb, m, x0 + r, y0 + r, r, inner_r, pi, n, color)
    _corner_ring_fan(
        vb, m, x1 - r, y0 + r, r, inner_r, 3.0 * pi / 2.0, n, color
    )
    _corner_ring_fan(vb, m, x1 - r, y1 - r, r, inner_r, 0.0, n, color)
    _corner_ring_fan(vb, m, x0 + r, y1 - r, r, inner_r, pi / 2.0, n, color)


def emit_rect(mut vb: VertexBuffer, c: RenderCommand, scale: Float64):
    """Fill quad plus, when outlined, a four-quad ring inset from the edge.

    Rounded corners need no uniform/non-uniform split like
    `_backend.mojo::_rect` does: every vertex here is already mapped
    individually, so a sheared rounded corner comes out as the ellipse arc
    it should be for free, exactly as `emit_circle` already relies on.
    """
    var m = c.transform
    var lx0 = c.geom[0] - c.geom[2] / 2.0
    var ly0 = c.geom[1] - c.geom[3] / 2.0
    var lx1 = c.geom[0] + c.geom[2] / 2.0
    var ly1 = c.geom[1] + c.geom[3] / 2.0
    var r = rect_corner_radius(
        Float64(c.style.corner_radius), c.geom[2], c.geom[3]
    )

    if r <= 0.0:
        if not c.style.outline_visible():
            if c.style.fill_visible():
                _mapped_quad(vb, m, lx0, ly0, lx1, ly1, c.style.fill_color)
            return

        # The ring is built in local units so it follows a rotated edge, but
        # its thickness is decided in pixels so the CPU path's one-pixel
        # floor holds.
        var sw = Float64(outline_thickness_px(c.style, m, scale)) / pixel_scale(
            m, scale
        )
        var ix0 = lx0 + sw
        var iy0 = ly0 + sw
        var ix1 = lx1 - sw
        var iy1 = ly1 - sw
        if ix0 >= ix1 or iy0 >= iy1:
            # Thicker than the rectangle: all outline, nothing left to fill.
            _mapped_quad(vb, m, lx0, ly0, lx1, ly1, c.style.outline_color)
            return

        if c.style.fill_visible():
            # Inset, not full-size: see the module docstring on double
            # blending.
            _mapped_quad(vb, m, ix0, iy0, ix1, iy1, c.style.fill_color)
        var sc = c.style.outline_color
        _mapped_quad(vb, m, lx0, ly0, lx1, iy0, sc)
        _mapped_quad(vb, m, lx0, iy1, lx1, ly1, sc)
        _mapped_quad(vb, m, lx0, iy0, ix0, iy1, sc)
        _mapped_quad(vb, m, ix1, iy0, lx1, iy1, sc)
        return

    var sf = pixel_scale(m, scale)
    if not c.style.outline_visible():
        if c.style.fill_visible():
            _rounded_rect_fill(
                vb, m, lx0, ly0, lx1, ly1, r, sf, c.style.fill_color
            )
        return

    var sw = Float64(outline_thickness_px(c.style, m, scale)) / sf
    var ix0 = lx0 + sw
    var iy0 = ly0 + sw
    var ix1 = lx1 - sw
    var iy1 = ly1 - sw
    if ix0 >= ix1 or iy0 >= iy1:
        # Thicker than the rectangle: all outline, nothing left to fill.
        _rounded_rect_fill(
            vb, m, lx0, ly0, lx1, ly1, r, sf, c.style.outline_color
        )
        return

    var inner_r = r - sw
    if c.style.fill_visible():
        if inner_r > 0.0:
            _rounded_rect_fill(
                vb, m, ix0, iy0, ix1, iy1, inner_r, sf, c.style.fill_color
            )
        else:
            # The inset silhouette has collapsed: a sharp inner rect, same
            # fallback `emit_rect`'s own sharp path takes at `ix0 >= ix1`.
            _mapped_quad(vb, m, ix0, iy0, ix1, iy1, c.style.fill_color)
    _rounded_rect_ring(
        vb,
        m,
        lx0,
        ly0,
        lx1,
        ly1,
        ix0,
        iy0,
        ix1,
        iy1,
        r,
        inner_r,
        sf,
        c.style.outline_color,
    )


def emit_circle(mut vb: VertexBuffer, c: RenderCommand, scale: Float64):
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
    # a fill wins the whole disc and no ring is rendered at all.
    var solid_all = c.style.outline_visible() and inner <= 0.0
    var fill_r = inner if outlined else r
    var fill_c = c.style.fill_color
    var fill_on = c.style.fill_visible()
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


def emit_line(mut vb: VertexBuffer, c: RenderCommand, scale: Float64):
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


def _fillet_arc_span(
    f: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ]
) -> Float64:
    """The signed sweep from a fillet's `angle_in` to its `angle_out`,
    normalised to `[-pi, pi]` — matches `_backend.mojo::_render_fillet_arc`'s
    own normalisation so the two backends walk the identical arc."""
    var delta = f[7] - f[6]
    if delta > pi:
        delta -= 2.0 * pi
    if delta < -pi:
        delta += 2.0 * pi
    return delta


def _rounded_triangle_fill(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    cx: Float64,
    cy: Float64,
    f0: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    f1: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    f2: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    r: Float64,
    sf: Float64,
    color: Color,
):
    """The eroded hexagon (a centroid fan over the six tangent points) union
    a corner fan per vertex — the same (eroded triangle) union (3 fillet
    discs) decomposition `_backend.mojo::_triangle`'s uniform branch uses,
    cheap here because every vertex is mapped individually anyway. Full
    size, not inset — the fill is unaffected by whether an outline is
    rendered, exactly as the unrounded triangle's own fill is."""
    var centre = mat_apply(m, cx, cy)
    var tx0 = f0[2]
    var ty0 = f0[3]
    var tx1 = f0[4]
    var ty1 = f0[5]
    var tx2 = f1[2]
    var ty2 = f1[3]
    var tx3 = f1[4]
    var ty3 = f1[5]
    var tx4 = f2[2]
    var ty4 = f2[3]
    var tx5 = f2[4]
    var ty5 = f2[5]
    var hx = List[Float64]()
    var hy = List[Float64]()
    hx.append(tx0)
    hy.append(ty0)
    hx.append(tx1)
    hy.append(ty1)
    hx.append(tx2)
    hy.append(ty2)
    hx.append(tx3)
    hy.append(ty3)
    hx.append(tx4)
    hy.append(ty4)
    hx.append(tx5)
    hy.append(ty5)
    for i in range(6):
        var j = (i + 1) % 6
        var pa = mat_apply(m, hx[i], hy[i])
        var pb = mat_apply(m, hx[j], hy[j])
        vb.triangle(centre[0], centre[1], pa[0], pa[1], pb[0], pb[1], color)

    var span0 = _fillet_arc_span(f0)
    var span1 = _fillet_arc_span(f1)
    var span2 = _fillet_arc_span(f2)
    _corner_fan(
        vb,
        m,
        f0[0],
        f0[1],
        r,
        f0[6],
        span0,
        _arc_segments(r * sf, span0),
        color,
    )
    _corner_fan(
        vb,
        m,
        f1[0],
        f1[1],
        r,
        f1[6],
        span1,
        _arc_segments(r * sf, span1),
        color,
    )
    _corner_fan(
        vb,
        m,
        f2[0],
        f2[1],
        r,
        f2[6],
        span2,
        _arc_segments(r * sf, span2),
        color,
    )


def _rounded_triangle_corner_outline(
    mut vb: VertexBuffer,
    m: Matrix[3, 3],
    f: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    r: Float64,
    sf: Float64,
    width: Float64,
    color: Color,
):
    """One rounded corner's outline arc as a fan of thick segments between
    mapped arc samples, mirroring `_backend.mojo::_render_fillet_arc_mapped`'s
    centred device-space band exactly — not a filled sector, so it matches
    the straight edge bands' own convention rather than the rounded rect's
    inset ring."""
    var cx = f[0]
    var cy = f[1]
    var angle_in = f[6]
    var span = _fillet_arc_span(f)
    var n = _arc_segments(r * sf, span)
    var prev = mat_apply(m, cx + r * cos(angle_in), cy + r * sin(angle_in))
    for i in range(1, n + 1):
        var t = Float64(i) / Float64(n)
        var ang = angle_in + span * t
        var cur = mat_apply(m, cx + r * cos(ang), cy + r * sin(ang))
        _segment_quad(vb, prev[0], prev[1], cur[0], cur[1], width, color)
        prev = cur


def emit_triangle(mut vb: VertexBuffer, c: RenderCommand, scale: Float64):
    """The mapped triangle, plus a quad per edge when outlined.

    The outline is three edge quads rather than an inset triangle, matching the
    CPU replay, which outlines a triangle with three `line_pixels` calls.

    Rounded corners need no uniform/non-uniform split like
    `_backend.mojo::_triangle` does: every vertex here is already mapped
    individually, so a sheared rounded corner comes out as the ellipse arc
    it should be for free, exactly as `emit_rect` already relies on.
    """
    var m = c.transform
    var lx1 = c.geom[0]
    var ly1 = c.geom[1]
    var lx2 = c.geom[2]
    var ly2 = c.geom[3]
    var lx3 = c.geom[4]
    var ly3 = c.geom[5]
    var r = triangle_corner_radius(
        Float64(c.style.corner_radius), lx1, ly1, lx2, ly2, lx3, ly3
    )

    if r <= 0.0:
        var p1 = mat_apply(m, lx1, ly1)
        var p2 = mat_apply(m, lx2, ly2)
        var p3 = mat_apply(m, lx3, ly3)
        if c.style.fill_visible():
            vb.triangle(
                p1[0], p1[1], p2[0], p2[1], p3[0], p3[1], c.style.fill_color
            )
        if c.style.outline_visible():
            var w = Float64(outline_thickness_px(c.style, m, scale))
            var sc = c.style.outline_color
            _segment_quad(vb, p1[0], p1[1], p2[0], p2[1], w, sc)
            _segment_quad(vb, p2[0], p2[1], p3[0], p3[1], w, sc)
            _segment_quad(vb, p3[0], p3[1], p1[0], p1[1], w, sc)
        return

    # Corner `i`'s prev/next follow the winding order `p1 -> p2 -> p3 ->
    # p1`, matching `_backend.mojo::_triangle`'s own layout exactly, so the
    # two backends cannot disagree on which tangent point sits on which
    # edge.
    var f0 = corner_fillet(lx1, ly1, lx3, ly3, lx2, ly2, r)
    var f1 = corner_fillet(lx2, ly2, lx1, ly1, lx3, ly3, r)
    var f2 = corner_fillet(lx3, ly3, lx2, ly2, lx1, ly1, r)
    var cx = (lx1 + lx2 + lx3) / 3.0
    var cy = (ly1 + ly2 + ly3) / 3.0
    var sf = pixel_scale(m, scale)

    if c.style.fill_visible():
        _rounded_triangle_fill(
            vb, m, cx, cy, f0, f1, f2, r, sf, c.style.fill_color
        )

    if c.style.outline_visible():
        var w = Float64(outline_thickness_px(c.style, m, scale))
        var sc = c.style.outline_color
        var t_f0_out = mat_apply(m, f0[4], f0[5])
        var t_f1_in = mat_apply(m, f1[2], f1[3])
        var t_f1_out = mat_apply(m, f1[4], f1[5])
        var t_f2_in = mat_apply(m, f2[2], f2[3])
        var t_f2_out = mat_apply(m, f2[4], f2[5])
        var t_f0_in = mat_apply(m, f0[2], f0[3])
        _segment_quad(
            vb, t_f0_out[0], t_f0_out[1], t_f1_in[0], t_f1_in[1], w, sc
        )
        _segment_quad(
            vb, t_f1_out[0], t_f1_out[1], t_f2_in[0], t_f2_in[1], w, sc
        )
        _segment_quad(
            vb, t_f2_out[0], t_f2_out[1], t_f0_in[0], t_f0_in[1], w, sc
        )
        _rounded_triangle_corner_outline(vb, m, f0, r, sf, w, sc)
        _rounded_triangle_corner_outline(vb, m, f1, r, sf, w, sc)
        _rounded_triangle_corner_outline(vb, m, f2, r, sf, w, sc)


def emit_letterbox(
    mut vb: VertexBuffer, c: RenderCommand, width: Int, height: Int
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


def emit_sprite(mut vb: VertexBuffer, c: RenderCommand, scale: Float64):
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
