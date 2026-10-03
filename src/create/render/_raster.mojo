from std.collections import Optional
from std.math import max, min, abs, ceil, floor, sqrt
from std.sys import is_big_endian

from create.color.blend_mode import BlendMode
from create.color.color import Color
from .font import _GlyphInfo
from create.color.gradient import Gradient, _DeviceMapping
from .surface import Surface
from create.math.point2d import Point2D


def _blend_lanes[
    w: Int
](
    src: SIMD[DType.uint32, w],
    dst: SIMD[DType.uint32, w],
    a: UInt32,
    mode: BlendMode,
) -> SIMD[DType.uint32, w]:
    """`w // 4` RGBA pixels of `dst` with `src` composited by `mode`.

    Lanes are widened bytes, 0 to 255. `src` carries `255` in its alpha lanes
    rather than the colour's alpha, as in `fill_span`, and `a` is the alpha
    itself. Every mode is the lerp from `dst` towards its blend result by
    `a`, except `ADD` and `SUBTRACT`, which add or take away `src * a`
    outright; the alpha lanes composite source-over in every mode. The one
    formula for all modes but `NORMAL`, so `blend` and `fill_span` cannot
    disagree about one.
    """
    var av = SIMD[DType.uint32, w](a)
    var iav = SIMD[DType.uint32, w](255 - a)
    var over = (src * av + dst * iav) // 255
    var out = over
    if mode == BlendMode.ADD:
        out = min(dst + src * av // 255, SIMD[DType.uint32, w](255))
    elif mode == BlendMode.SUBTRACT:
        out = dst - min(dst, src * av // 255)
    elif mode == BlendMode.MULTIPLY:
        out = ((src * dst // 255) * av + dst * iav) // 255
    elif mode == BlendMode.SCREEN:
        out = ((src + dst - src * dst // 255) * av + dst * iav) // 255
    var alpha_lane = SIMD[DType.bool, w](fill=False)
    comptime for i in range(3, w, 4):
        alpha_lane[i] = True
    return alpha_lane.select(over, out)


def _blend_pixel[
    o: Origin[mut=True]
](s: Surface[o], off: Int, c: Color, mode: BlendMode):
    """Composite one pixel by a non-`NORMAL` mode, through `_blend_lanes`."""
    var px = s.px
    var src = SIMD[DType.uint8, 4](c.r, c.g, c.b, 255).cast[DType.uint32]()
    var dst = px.unsafe_load[width=4](offset=off).cast[DType.uint32]()
    var out = _blend_lanes[4](src, dst, UInt32(c.a), mode)
    px.unsafe_store[width=4](offset=off, val=out.cast[DType.uint8]())


def blend[
    o: Origin[mut=True], //, clipped: Bool = True
](s: Surface[o], off: Int, c: Color):
    """Composite one color into the framebuffer at `off`, by the surface's
    blend mode, if the surface's clip keeps it.

    Under `NORMAL`, fully opaque and fully transparent colors skip the
    read-back, so the common case costs no more than a raw store;
    `Color.over` owns the mixing. Any other mode goes through `_blend_lanes`.

    `clipped=False` skips the clip test, for a per-pixel loop that has
    checked once that `s` has no clip — the test alone cost a sprite blit
    ~15%.
    """
    if c.a == 0:
        return
    comptime if clipped:
        if s._clip and not _clip_keeps(s, off):
            return
    if s._blend_mode != BlendMode.NORMAL:
        _blend_pixel(s, off, c, s._blend_mode)
        return
    var px = s.px
    if c.a == 255:
        px[unsafe_offset=off] = c.r
        px[unsafe_offset=off + 1] = c.g
        px[unsafe_offset=off + 2] = c.b
        px[unsafe_offset=off + 3] = 255
        return
    var out = c.over(
        Color(
            px[unsafe_offset=off],
            px[unsafe_offset=off + 1],
            px[unsafe_offset=off + 2],
            px[unsafe_offset=off + 3],
        )
    )
    px[unsafe_offset=off] = out.r
    px[unsafe_offset=off + 1] = out.g
    px[unsafe_offset=off + 2] = out.b
    px[unsafe_offset=off + 3] = out.a


@no_inline
def _clip_keeps[o: Origin[mut=True]](s: Surface[o], off: Int) -> Bool:
    """Whether the pixel at byte offset `off` lies inside `s`'s clip."""
    var index = off // 4
    var row = index // s.width
    var x = index - row * s.width
    ref rows = s._clip.value()[]
    for k in range(rows.starts[row], rows.starts[row + 1]):
        if x < rows.spans[2 * k]:
            return False
        if x < rows.spans[2 * k + 1]:
            return True
    return False


def _packed(c: Color) -> UInt32:
    """`c` as one word whose bytes land in the framebuffer's r, g, b, a order.

    Composed by endianness rather than assumed: a 32-bit store writes the low
    byte to the lowest address on a little-endian target and to the highest on
    a big-endian one, while the framebuffer is r, g, b, a ascending either way.
    """

    comptime if is_big_endian():
        return (
            (UInt32(c.r) << 24)
            | (UInt32(c.g) << 16)
            | (UInt32(c.b) << 8)
            | UInt32(c.a)
        )
    return (
        UInt32(c.r)
        | (UInt32(c.g) << 8)
        | (UInt32(c.b) << 16)
        | (UInt32(c.a) << 24)
    )


def _word_aligned[o: Origin[mut=True]](s: Surface[o]) -> Bool:
    """Whether whole pixels can be stored a word at a time.

    Every pixel sits at a multiple of four bytes from the base, so the base
    settles it for the entire buffer. Both framebuffers in the repo satisfy
    this — a `List[UInt8]` and an SDL window buffer are each malloc-aligned —
    but neither guarantees it by contract, and a 32-bit store through a
    misaligned pointer is undefined, not merely slow.
    """
    return Int(s.px) % 4 == 0


@always_inline
def fill_span[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, c: Color):
    """Composite `count` consecutive pixels starting at byte offset `off`.

    The caller has already clipped to the surface and worked out the covered
    run; this does no bounds checking of its own. An opaque fill is one word
    per pixel, not four bytes, and the alpha test is hoisted out of the loop
    rather than left to `blend` — together worth ~4x on a run of any length.
    Both branches then process four pixels (16 bytes) at a time through
    `SIMD`, for another ~4x: the opaque path is a vector splat of the packed
    word, and the alpha path widens both source and destination to `uint32`
    lanes, computes `(src*a + dst*ia) // 255` across all sixteen bytes at
    once, and narrows back. The source vector's alpha lane carries `255`
    rather than `c.a`, which is what makes one blend formula correct for
    both the colour lanes and the alpha lane — see
    `test_fill_span_alpha_matches_over_exhaustively`. A tail of fewer than
    four pixels falls back to the scalar loop. Every rasteriser that
    produces a horizontal run of pixels goes through this one loop; none of
    this may be re-open-coded at a call site.

    A surface blend mode other than `NORMAL` takes neither branch: it has no
    opaque shortcut, and runs the same four-pixel `SIMD` loop through
    `_blend_lanes`.

    A clipped surface cuts the run into its pieces inside the clip first,
    and a recording one paints nothing and notes the run instead; see
    `Surface._clip`. The run must lie within one row.
    """
    if c.a == 0:
        return
    if s._clip or s._recording:
        _fill_span_clipped(s, off, count, c)
        return
    _fill_run(s, off, count, c)


@no_inline
def _fill_span_clipped[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, c: Color):
    """`fill_span` on a clipped or recording surface. Out of line and
    calling `_fill_run` rather than `fill_span`, so the unclipped path stays
    small and non-recursive enough to inline into every raster loop."""
    var index = off // 4
    var row = index // s.width
    var x0 = index - row * s.width
    if s._recording:
        _record_run(s, row, x0, count, _color_key(c))
        return
    ref rows = s._clip.value()[]
    for k in range(rows.starts[row], rows.starts[row + 1]):
        var lo = max(x0, rows.spans[2 * k])
        var hi = min(x0 + count, rows.spans[2 * k + 1])
        if hi > lo:
            _fill_run(s, (row * s.width + lo) * 4, hi - lo, c)


comptime GRADIENT_KEY = -1
"""The paint key a recording surface notes for a gradient fill's runs; a
solid colour's is `_color_key` of it, never negative."""


def _color_key(c: Color) -> Int:
    """`c` as a recorded run's paint key, which `_key_color` reverses."""
    return (Int(c.r) << 24) | (Int(c.g) << 16) | (Int(c.b) << 8) | Int(c.a)


def _key_color(key: Int) -> Color:
    return Color(
        UInt8((key >> 24) & 255),
        UInt8((key >> 16) & 255),
        UInt8((key >> 8) & 255),
        UInt8(key & 255),
    )


def _record_run[
    o: Origin[mut=True]
](s: Surface[o], row: Int, x0: Int, count: Int, key: Int):
    """Note the run on a recording surface as `(row, lo, hi, key)`."""
    if count > 0:
        ref runs = s._recording.value()[]
        runs.append(row)
        runs.append(x0)
        runs.append(x0 + count)
        runs.append(key)


def _fill_run[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, c: Color):
    """`fill_span`'s loops, for a run already inside the clip."""
    var px = s.px
    var mode = s._blend_mode
    if mode != BlendMode.NORMAL:
        var one = SIMD[DType.uint8, 4](c.r, c.g, c.b, 255)
        var two = one.join(one)
        var src = two.join(two).cast[DType.uint32]()
        var j = 0
        while j + 4 <= count:
            var o2 = off + j * 4
            var dst = px.unsafe_load[width=16](offset=o2).cast[DType.uint32]()
            var out = _blend_lanes[16](src, dst, UInt32(c.a), mode)
            px.unsafe_store[width=16](offset=o2, val=out.cast[DType.uint8]())
            j += 4
        while j < count:
            _blend_pixel(s, off + j * 4, c, mode)
            j += 1
        return
    if c.a == 255 and _word_aligned(s):
        var w = px.unsafe_bitcast[UInt32]()
        var v = _packed(c)
        var i0 = off // 4
        var vv = SIMD[DType.uint32, 4](v, v, v, v)
        var i = 0
        while i + 4 <= count:
            w.unsafe_store[width=4](offset=i0 + i, val=vv)
            i += 4
        while i < count:
            w[unsafe_offset=i0 + i] = v
            i += 1
        return
    if c.a == 255:
        for i in range(count):
            var o2 = off + i * 4
            px[unsafe_offset=o2] = c.r
            px[unsafe_offset=o2 + 1] = c.g
            px[unsafe_offset=o2 + 2] = c.b
            px[unsafe_offset=o2 + 3] = 255
        return
    var a = UInt32(c.a)
    var ia = UInt32(255 - Int(c.a))
    var a4 = SIMD[DType.uint32, 16](a)
    var ia4 = SIMD[DType.uint32, 16](ia)
    var one_px = SIMD[DType.uint8, 4](c.r, c.g, c.b, 255)
    var two_px = one_px.join(one_px)
    var src4 = two_px.join(two_px).cast[DType.uint32]()
    var i = 0
    while i + 4 <= count:
        var o2 = off + i * 4
        var dst = px.unsafe_load[width=16](offset=o2).cast[DType.uint32]()
        var out = ((src4 * a4 + dst * ia4) // 255).cast[DType.uint8]()
        px.unsafe_store[width=16](offset=o2, val=out)
        i += 4
    while i < count:
        var o2 = off + i * 4
        var out = c.over(
            Color(
                px[unsafe_offset=o2],
                px[unsafe_offset=o2 + 1],
                px[unsafe_offset=o2 + 2],
                px[unsafe_offset=o2 + 3],
            )
        )
        px[unsafe_offset=o2] = out.r
        px[unsafe_offset=o2 + 1] = out.g
        px[unsafe_offset=o2 + 2] = out.b
        px[unsafe_offset=o2 + 3] = out.a
        i += 1


@fieldwise_init
struct _Shader(Copyable, ImplicitlyCopyable, Movable):
    """A gradient placed in device pixels: what a gradient fill samples."""

    var gradient: Gradient
    var mapping: _DeviceMapping


struct FillPaint(Copyable, ImplicitlyCopyable, Movable):
    """What a fill's runs paint: one colour, or a gradient sampled per pixel.

    `fill_span`, `fill_pixels`, `fill_quad` and `fill_triangle` take one, and
    a `Color` converts implicitly, so a caller painting an outline or a
    shadow passes its colour as before; only the fill-colour call sites build
    a gradient one. The choice is made once per run, never per pixel of a
    solid fill, and a solid one is no more than its colour and a flag.
    """

    var color: Color
    var shader: Optional[_Shader]

    @implicit
    @always_inline
    def __init__(out self, color: Color):
        self.color = color
        self.shader = None

    def __init__(out self, gradient: Gradient, mapping: _DeviceMapping):
        self.color = Color.TRANSPARENT
        self.shader = _Shader(gradient, mapping)

    def _paints_nothing(self) -> Bool:
        if self.shader:
            return not self.shader.value().gradient._visible()
        return self.color.a == 0


def _shade_span[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, gradient: Gradient, m: _DeviceMapping):
    """`fill_span` for a gradient: each pixel's colour from its centre's
    parameter, composited one at a time through `blend`. The parameter's
    inputs step by a constant per pixel along the row, so only a radial
    gradient pays a `sqrt` per pixel."""
    var index = off // 4
    var y = index // s.width
    var x0 = index - y * s.width
    var xc = Float64(x0) + 0.5
    var yc = Float64(y) + 0.5
    var u = m.u[0] * xc + m.u[1] * yc + m.u[2]
    var v = m.v[0] * xc + m.v[1] * yc + m.v[2]
    for i in range(count):
        var t = sqrt(u * u + v * v) if m.radial else u
        blend(s, off + i * 4, gradient._sample(t, x0 + i, y))
        u += m.u[0]
        v += m.v[0]


@always_inline
def fill_span[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, paint: FillPaint):
    """`fill_span` for a `FillPaint`: the colour's own loop, or the
    gradient's."""
    if paint.shader and s._recording:
        if paint.shader.value().gradient._visible():
            var index = off // 4
            var row = index // s.width
            _record_run(s, row, index - row * s.width, count, GRADIENT_KEY)
        return
    if paint.shader and s._clip:
        _shade_span_clipped(s, off, count, paint)
        return
    if paint.shader:
        ref shader = paint.shader.value()
        _shade_span(s, off, count, shader.gradient, shader.mapping)
    else:
        fill_span(s, off, count, paint.color)


@no_inline
def _shade_span_clipped[
    o: Origin[mut=True]
](s: Surface[o], off: Int, count: Int, paint: FillPaint):
    """A gradient `fill_span` on a clipped surface, cut once here so
    `_shade_span`'s per-pixel `blend` need not test."""
    var u = s._with_clip(None)
    var index = off // 4
    var row = index // s.width
    var x0 = index - row * s.width
    ref rows = s._clip.value()[]
    ref shader = paint.shader.value()
    for k in range(rows.starts[row], rows.starts[row + 1]):
        var lo = max(x0, rows.spans[2 * k])
        var hi = min(x0 + count, rows.spans[2 * k + 1])
        if hi > lo:
            _shade_span(
                u,
                (row * s.width + lo) * 4,
                hi - lo,
                shader.gradient,
                shader.mapping,
            )


def fill_all[o: Origin[mut=True]](s: Surface[o], c: Color):
    """Composite `c` over every pixel the surface's clip keeps."""
    if s._clip:
        for row in range(s.height):
            fill_span(s, row * s.width * 4, s.width, c)
        return
    fill_span(s, 0, s.width * s.height, c)


def fill_pixels[
    o: Origin[mut=True]
](s: Surface[o], x0: Int, y0: Int, x1: Int, y1: Int, c: FillPaint):
    """Fill the half-open device-space rect `[x0, x1) x [y0, y1)`, clipped.

    Clipped once for the whole rect, then one `fill_span` per row.
    """
    if c._paints_nothing():
        return
    var W = s.width
    var r0 = max(y0, 0)
    var r1 = min(y1, s.height)
    var c0 = max(x0, 0)
    var c1 = min(x1, W)
    if c1 <= c0:
        return
    if not c.shader:
        # Solid, decided once for the whole rect rather than per row.
        var color = c.color
        for row in range(r0, r1):
            fill_span(s, (row * W + c0) * 4, c1 - c0, color)
        return
    for row in range(r0, r1):
        fill_span(s, (row * W + c0) * 4, c1 - c0, c)


def line_pixels[
    o: Origin[mut=True]
](
    s: Surface[o],
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    c: Color,
    outline_thickness: Int,
):
    """Stroke the device segment `(x0, y0)`-`(x1, y1)` as an
    `outline_thickness`-wide band with butt ends.

    The band is the same quad `_tessellate.mojo::_segment_quad` hands the
    GPU — the segment pushed out by half the thickness along its normal —
    and a pixel is covered when its centre is: each row's covered run is the
    quad's span at the row's centre line, filled once through `fill_span`.
    So a slanted band is as wide across as a level one, and each pixel is
    composited exactly once under alpha. Ties follow a half-open rule (a
    centre on the left or top edge is in, on the right or bottom edge out),
    so two bands sharing an edge don't both paint it. A zero-length segment
    paints nothing, as on the GPU.
    """
    if c.a == 0 or outline_thickness <= 0:
        return
    var dx = x1 - x0
    var dy = y1 - y0
    var length = sqrt(dx * dx + dy * dy)
    if length == 0.0:
        return
    var half = Float64(outline_thickness) / 2.0
    var nx = -dy / length * half
    var ny = dx / length * half
    var qx: Array[Float64, 4] = [x0 + nx, x1 + nx, x1 - nx, x0 - nx]
    var qy: Array[Float64, 4] = [y0 + ny, y1 + ny, y1 - ny, y0 - ny]
    fill_quad(s, qx, qy, c)


def fill_quad[
    o: Origin[mut=True]
](s: Surface[o], qx: Array[Float64, 4], qy: Array[Float64, 4], c: FillPaint):
    """Fill the convex device quad with corners `(qx[i], qy[i])`, in order
    around its edge, by pixel centre.

    Each row's covered run is the quad's span at the row's centre line,
    filled once through `fill_span`. Ties follow a half-open rule (a centre
    on the left or top edge is in, on the right or bottom edge out), so two
    quads sharing an edge never both paint a pixel on it — which is what
    lets a strip of them composite once under alpha. Each edge is
    interpolated from its lower end whichever way the quad walks it, so two
    quads sharing it compute bit-identical crossings.
    """
    var y_lo = min(min(qy[0], qy[1]), min(qy[2], qy[3]))
    var y_hi = max(max(qy[0], qy[1]), max(qy[2], qy[3]))
    var W = s.width
    # Rows whose centre `row + 0.5` lies in `[y_lo, y_hi)`.
    var r0 = max(Int(ceil(y_lo - 0.5)), 0)
    var r1 = min(Int(ceil(y_hi - 0.5)), s.height)
    # Each edge from its lower end, with its slope worked out once rather
    # than divided out per row; `fill_convex` does exactly the same, so the
    # two agree to the bit on an edge they share.
    var ex = Array[Float64, 4](fill=0.0)
    var ey0 = Array[Float64, 4](fill=0.0)
    var ey1 = Array[Float64, 4](fill=0.0)
    var slope = Array[Float64, 4](fill=0.0)
    for i in range(4):
        var e = _edge(qx[i], qy[i], qx[(i + 1) % 4], qy[(i + 1) % 4])
        ex[i] = e[0]
        ey0[i] = e[1]
        ey1[i] = e[2]
        slope[i] = e[3]
    for row in range(r0, r1):
        var yc = Float64(row) + 0.5
        var lo = Float64.MAX
        var hi = -Float64.MAX
        for i in range(4):
            # Half-open in y, so a vertex on the centre line counts once
            # and a level edge not at all.
            if ey0[i] <= yc and yc < ey1[i]:
                var x = ex[i] + slope[i] * (yc - ey0[i])
                lo = min(lo, x)
                hi = max(hi, x)
        # Columns whose centre `col + 0.5` lies in `[lo, hi)`.
        var c0 = max(Int(ceil(lo - 0.5)), 0)
        var c1 = min(Int(ceil(hi - 0.5)), W)
        if c1 > c0:
            fill_span(s, (row * W + c0) * 4, c1 - c0, c)


@always_inline
def _edge(
    ax: Float64, ay: Float64, bx: Float64, by: Float64
) -> Tuple[Float64, Float64, Float64, Float64]:
    """An edge as `fill_quad` and `fill_convex` walk it: its lower end's
    x, the lower and upper y, and x per unit y (0 for a level edge, which no
    row centre crosses)."""
    if by < ay:
        return (bx, by, ay, (ax - bx) / (ay - by))
    if by == ay:
        return (ax, ay, by, 0.0)
    return (ax, ay, by, (bx - ax) / (by - ay))


def fill_convex[
    o: Origin[mut=True]
](s: Surface[o], corners: List[Point2D], c: FillPaint):
    """Fill the convex device polygon `corners`, in order around its edge,
    by pixel centre: `fill_quad` for any number of corners, with the same
    rules — each row's span at its centre line, half-open in x and y, each
    edge interpolated from its lower end — so a polygon and a quad sharing
    an edge compute the same crossings and composite it once.
    """
    var n = len(corners)
    if n < 3:
        return
    var y_lo = Float64.MAX
    var y_hi = -Float64.MAX
    for p in corners:
        y_lo = min(y_lo, p.y)
        y_hi = max(y_hi, p.y)
    var W = s.width
    var r0 = max(Int(ceil(y_lo - 0.5)), 0)
    var r1 = min(Int(ceil(y_hi - 0.5)), s.height)
    var edges = List[Tuple[Float64, Float64, Float64, Float64]](capacity=n)
    for i in range(n):
        var a = corners[i]
        var b = corners[(i + 1) % n]
        edges.append(_edge(a.x, a.y, b.x, b.y))
    for row in range(r0, r1):
        var yc = Float64(row) + 0.5
        var lo = Float64.MAX
        var hi = -Float64.MAX
        for ref e in edges:
            if e[1] <= yc and yc < e[2]:
                var x = e[0] + e[3] * (yc - e[1])
                lo = min(lo, x)
                hi = max(hi, x)
        var c0 = max(Int(ceil(lo - 0.5)), 0)
        var c1 = min(Int(ceil(hi - 0.5)), W)
        if c1 > c0:
            fill_span(s, (row * W + c0) * 4, c1 - c0, c)


def fill_triangle[
    o: Origin[mut=True]
](
    s: Surface[o],
    x1: Float64,
    y1: Float64,
    x2: Float64,
    y2: Float64,
    x3: Float64,
    y3: Float64,
    c: FillPaint,
):
    """Fill a device-space triangle by scanline span.

    Vertices are sorted by y into a top-to-bottom chain; each integer row
    between them intersects the long edge (top to bottom vertex) and
    whichever short edge is active for that row (top-to-mid, then
    mid-to-bottom), giving one `fill_span` per row instead of a per-pixel
    three-edge sign test. The split at the mid vertex is exact — each row
    is produced by exactly one of the two sub-loops — so a horizontal top
    or bottom edge (mid vertex level with an end) degenerates cleanly by
    skipping the sub-loop whose edge has zero height, rather than dividing
    by zero. This is not bit-exact with the old per-pixel test: an edge
    pixel may land in a different column, which is why the gate for this
    change is `test_gl_parity.mojo` and a dilation-bound comparison against
    the retired algorithm, not byte equality.
    """
    var W = s.width
    var H = s.height

    var ax = x1
    var ay = y1
    var bx = x2
    var by = y2
    var cx = x3
    var cy = y3
    if ay > by:
        var tx = ax
        var ty = ay
        ax = bx
        ay = by
        bx = tx
        by = ty
    if by > cy:
        var tx = bx
        var ty = by
        bx = cx
        by = cy
        cx = tx
        cy = ty
    if ay > by:
        var tx = ax
        var ty = ay
        ax = bx
        ay = by
        bx = tx
        by = ty

    if cy == ay:
        return  # Zero-height triangle: nothing to paint.

    var long_dy = cy - ay

    if by > ay:
        var r0 = max(Int(ceil(ay)), 0)
        var r1 = min(Int(floor(by)), H - 1)
        var short_dy = by - ay
        for row in range(r0, r1 + 1):
            var t_long = (Float64(row) - ay) / long_dy
            var x_long = ax + (cx - ax) * t_long
            var t_short = (Float64(row) - ay) / short_dy
            var x_short = ax + (bx - ax) * t_short
            var lo_x = min(x_long, x_short)
            var hi_x = max(x_long, x_short)
            var col_lo = max(Int(ceil(lo_x)), 0)
            var col_hi = min(Int(floor(hi_x)), W - 1)
            if col_hi >= col_lo:
                fill_span(s, (row * W + col_lo) * 4, col_hi - col_lo + 1, c)

    if cy > by:
        var r0 = max(Int(floor(by)) + 1 if by > ay else Int(ceil(ay)), 0)
        var r1 = min(Int(floor(cy)), H - 1)
        var short_dy = cy - by
        for row in range(r0, r1 + 1):
            var t_long = (Float64(row) - ay) / long_dy
            var x_long = ax + (cx - ax) * t_long
            var t_short = (Float64(row) - by) / short_dy
            var x_short = bx + (cx - bx) * t_short
            var lo_x = min(x_long, x_short)
            var hi_x = max(x_long, x_short)
            var col_lo = max(Int(ceil(lo_x)), 0)
            var col_hi = min(Int(floor(hi_x)), W - 1)
            if col_hi >= col_lo:
                fill_span(s, (row * W + col_lo) * 4, col_hi - col_lo + 1, c)


def _silhouette(tint: Color, alpha: UInt8) -> Color:
    """`tint` with its alpha scaled by a texel's, rounded like `blend`."""
    var a = (UInt32(tint.a) * UInt32(alpha) + 127) // 255
    return Color(tint.r, tint.g, tint.b, UInt8(a))


@always_inline
def _faded(texel: UInt8, alpha: UInt8) -> UInt8:
    """A texel's alpha under a sprite's opacity `alpha`."""
    if alpha == 255:
        return texel
    return UInt8(Int(texel) * Int(alpha) // 255)


def blit_sprite[
    o: Origin[mut=True], so: Origin
](
    s: Surface[o],
    src: Pointer[UInt8, so],
    sw: Int,
    sh: Int,
    x0: Int,
    y0: Int,
    dw: Int,
    dh: Int,
    tint: Optional[Color] = None,
    alpha: UInt8 = 255,
):
    """Blit the `sw` x `sh` RGBA buffer at `src` into the device rect at
    `(x0, y0)` sized `dw` x `dh`; see `_blit_sprite`."""
    if s._clip:
        _blit_sprite[clipped=True](s, src, sw, sh, x0, y0, dw, dh, tint, alpha)
    else:
        _blit_sprite[clipped=False](s, src, sw, sh, x0, y0, dw, dh, tint, alpha)


def _blit_sprite[
    o: Origin[mut=True], so: Origin, //, clipped: Bool
](
    s: Surface[o],
    src: Pointer[UInt8, so],
    sw: Int,
    sh: Int,
    x0: Int,
    y0: Int,
    dw: Int,
    dh: Int,
    tint: Optional[Color],
    alpha: UInt8,
):
    """Blit the `sw` x `sh` RGBA buffer at `src` into the device rect at
    `(x0, y0)` sized `dw` x `dh`, every texel's alpha scaled by `alpha` (the
    sprite's opacity).

    With `tint`, paint the image's silhouette instead: `tint` wherever the
    image is opaque, its alpha scaled by each texel's. That is a sprite's
    shadow; `tint` already carries any opacity, so `alpha` is ignored.

    Takes a bare pixel view rather than an image type, for the same reason
    `Surface` is a plain value: nothing here needs to know where the pixels
    came from.

    Nearest-neighbour: rotation and shear are not resampled, so the caller
    maps the anchor and hands over an axis-aligned destination. A 1:1 blit
    skips the source-index division rather than relying on it cancelling.

    Destination rows and columns are clipped once against the surface up
    front, the way `fill_pixels` already clips, instead of testing `dx`/`dy`
    against the bounds on every pixel. The resampled path (`dw != sw` or
    `dh != sh`) also drops the per-column `col * sw // dw` division: `src_col`
    and `err` are a fixed-point walk of that same division — `err` holds
    `(col * sw) mod dw` and advances by `sw` each column, folding a `dw` back
    out (and bumping `src_col`) whenever it would overflow — so `src_col`
    equals `col * sw // dw` at every step without dividing there. One
    division seeds `src_col`/`err` at `col_lo`, since the clipped loop may not
    start at column 0.
    """
    var W = s.width
    var H = s.height
    var sp = src
    var one_to_one = dw == sw and dh == sh
    var silhouette = Bool(tint)
    var t = tint.value() if tint else Color.WHITE

    var row_lo = max(0, -y0)
    var row_hi = min(dh, H - y0)
    var col_lo = max(0, -x0)
    var col_hi = min(dw, W - x0)
    if row_lo >= row_hi or col_lo >= col_hi:
        return

    for row in range(row_lo, row_hi):
        var dst_row_off = (y0 + row) * W * 4
        if one_to_one:
            var src_row_off = row * sw * 4
            for col in range(col_lo, col_hi):
                var src_off = src_row_off + col * 4
                var sa = sp[unsafe_offset=src_off + 3]
                if sa == 0:
                    continue
                blend[clipped=clipped](
                    s,
                    dst_row_off + (x0 + col) * 4,
                    _silhouette(t, sa) if silhouette else Color(
                        sp[unsafe_offset=src_off],
                        sp[unsafe_offset=src_off + 1],
                        sp[unsafe_offset=src_off + 2],
                        _faded(sa, alpha),
                    ),
                )
        else:
            var src_row_off = (row * sh // dh) * sw * 4
            var src_col = col_lo * sw // dw
            var err = (col_lo * sw) % dw
            for col in range(col_lo, col_hi):
                var src_off = src_row_off + src_col * 4
                var sa = sp[unsafe_offset=src_off + 3]
                if sa != 0:
                    blend[clipped=clipped](
                        s,
                        dst_row_off + (x0 + col) * 4,
                        _silhouette(t, sa) if silhouette else Color(
                            sp[unsafe_offset=src_off],
                            sp[unsafe_offset=src_off + 1],
                            sp[unsafe_offset=src_off + 2],
                            _faded(sa, alpha),
                        ),
                    )
                err += sw
                while err >= dw:
                    err -= dw
                    src_col += 1


def blit_glyph[
    o: Origin[mut=True]
](s: Surface[o], g: _GlyphInfo, x0: Int, y0: Int, c: Color):
    """Composite a glyph's coverage mask at `(x0, y0)` in `c`."""
    blit_alpha(s, g.pixels.unsafe_ptr(), g.width, g.height, x0, y0, c)


def blit_alpha[
    o: Origin[mut=True], so: Origin
](
    s: Surface[o],
    src: Pointer[UInt8, so],
    width: Int,
    height: Int,
    x0: Int,
    y0: Int,
    c: Color,
):
    """Composite the `width` x `height` 8-bit coverage mask at `src` at
    `(x0, y0)` in `c`; see `_blit_alpha`."""
    if s._clip:
        _blit_alpha[clipped=True](s, src, width, height, x0, y0, c)
    else:
        _blit_alpha[clipped=False](s, src, width, height, x0, y0, c)


def _blit_alpha[
    o: Origin[mut=True], so: Origin, //, clipped: Bool
](
    s: Surface[o],
    src: Pointer[UInt8, so],
    width: Int,
    height: Int,
    x0: Int,
    y0: Int,
    c: Color,
):
    """Composite the `width` x `height` 8-bit coverage mask at `src` at
    `(x0, y0)` in `c` — a glyph, or a blurred silhouette.

    Coverage scales the colour's alpha, so antialiasing and a translucent
    colour compose rather than one overriding the other.

    Rows and columns are clipped once against the surface up front, as
    `blit_sprite` does, instead of testing each pixel against the bounds.
    Coverage is still tested per pixel — a mask is genuinely scattered, not a
    run — so it keeps `blend` rather than moving to `fill_span`.
    """
    var W = s.width
    var H = s.height
    var ca = Int(c.a)
    var gp = src

    var row_lo = max(0, -y0)
    var row_hi = min(height, H - y0)
    var col_lo = max(0, -x0)
    var col_hi = min(width, W - x0)
    if row_lo >= row_hi or col_lo >= col_hi:
        return

    for row in range(row_lo, row_hi):
        var dst_row_off = (y0 + row) * W * 4
        var src_row_off = row * width
        for col in range(col_lo, col_hi):
            var cov = Int(gp[unsafe_offset=src_row_off + col])
            if cov == 0:
                continue
            blend[clipped=clipped](
                s,
                dst_row_off + (x0 + col) * 4,
                Color(c.r, c.g, c.b, UInt8(cov * ca // 255)),
            )
