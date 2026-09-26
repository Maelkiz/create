from std.math import max, min, abs, ceil, floor
from std.sys import is_big_endian

from .blend_mode import BlendMode
from .color import Color
from .font import _GlyphInfo
from .surface import Surface


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


def blend[o: Origin[mut=True]](s: Surface[o], off: Int, c: Color):
    """Composite one color into the framebuffer at `off`, by the surface's
    blend mode.

    Under `NORMAL`, fully opaque and fully transparent colors skip the
    read-back, so the common case costs no more than a raw store;
    `Color.over` owns the mixing. Any other mode goes through `_blend_lanes`.
    """
    if c.a == 0:
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
    """
    if c.a == 0:
        return
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


def fill_all[o: Origin[mut=True]](s: Surface[o], c: Color):
    """Composite `c` over every pixel — the whole frame, no clipping needed."""
    fill_span(s, 0, s.width * s.height, c)


def fill_pixels[
    o: Origin[mut=True]
](s: Surface[o], x0: Int, y0: Int, x1: Int, y1: Int, c: Color):
    """Fill the half-open device-space rect `[x0, x1) x [y0, y1)`, clipped.

    Clipped once for the whole rect, then one `fill_span` per row.
    """
    if c.a == 0:
        return
    var W = s.width
    var r0 = max(y0, 0)
    var r1 = min(y1, s.height)
    var c0 = max(x0, 0)
    var c1 = min(x1, W)
    if c1 <= c0:
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
    """Bresenham line in device space, `outline_thickness` pixels thick.

    One Bresenham step per column (dx >= dy) or per row (dy > dx), each
    covering the line's perpendicular extent exactly once — not the box
    the naive version stamps at every step, which re-blends most pixels
    along the line once per neighbouring step and so darkens them further
    each time under alpha, on top of the wasted work. A mostly-vertical
    line's extent per row is contiguous in memory and goes through
    `fill_span`; a mostly-horizontal line's extent per column is a strided
    column of pixels, so it composites one pixel at a time with `blend`, but
    each pixel is still touched exactly once.
    """
    if c.a == 0:
        return
    var W = s.width
    var H = s.height
    var sw = outline_thickness
    var half = sw // 2
    var ix0 = Int(x0)
    var iy0 = Int(y0)
    var ix1 = Int(x1)
    var iy1 = Int(y1)
    var dx = abs(ix1 - ix0)
    var dy = abs(iy1 - iy0)
    var sx = 1 if ix0 < ix1 else -1
    var sy = 1 if iy0 < iy1 else -1

    if dx >= dy:
        var y = iy0
        var err = dx // 2
        for step in range(dx + 1):
            var x = ix0 + step * sx
            if 0 <= x < W:
                var r0 = max(y - half, 0)
                var r1 = min(y + sw - half, H)
                for row in range(r0, r1):
                    blend(s, (row * W + x) * 4, c)
            err -= dy
            if err < 0:
                y += sy
                err += dx
    else:
        var x = ix0
        var err = dy // 2
        for step in range(dy + 1):
            var y = iy0 + step * sy
            if 0 <= y < H:
                var c0 = max(x - half, 0)
                var c1 = min(x + sw - half, W)
                if c1 > c0:
                    fill_span(s, (y * W + c0) * 4, c1 - c0, c)
            err -= dx
            if err < 0:
                x += sx
                err += dy


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
    c: Color,
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
):
    """Blit the `sw` x `sh` RGBA buffer at `src` into the device rect at
    `(x0, y0)` sized `dw` x `dh`.

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
                blend(
                    s,
                    dst_row_off + (x0 + col) * 4,
                    Color(
                        sp[unsafe_offset=src_off],
                        sp[unsafe_offset=src_off + 1],
                        sp[unsafe_offset=src_off + 2],
                        sa,
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
                    blend(
                        s,
                        dst_row_off + (x0 + col) * 4,
                        Color(
                            sp[unsafe_offset=src_off],
                            sp[unsafe_offset=src_off + 1],
                            sp[unsafe_offset=src_off + 2],
                            sa,
                        ),
                    )
                err += sw
                while err >= dw:
                    err -= dw
                    src_col += 1


def blit_glyph[
    o: Origin[mut=True]
](s: Surface[o], g: _GlyphInfo, x0: Int, y0: Int, c: Color):
    """Composite a glyph's coverage mask at `(x0, y0)` in `c`.

    Coverage scales the fill's alpha, so antialiasing and a translucent fill
    compose rather than one overriding the other.

    Rows and columns are clipped once against the surface up front, as
    `blit_sprite` now does, instead of testing `px_x` against the bounds on
    every pixel. Coverage is still tested per pixel — a glyph mask is
    genuinely scattered, not a run — so it keeps `blend` rather than moving
    to `fill_span`.
    """
    var W = s.width
    var H = s.height
    var ca = Int(c.a)
    var gp = g.pixels.unsafe_ptr()

    var row_lo = max(0, -y0)
    var row_hi = min(g.height, H - y0)
    var col_lo = max(0, -x0)
    var col_hi = min(g.width, W - x0)
    if row_lo >= row_hi or col_lo >= col_hi:
        return

    for row in range(row_lo, row_hi):
        var dst_row_off = (y0 + row) * W * 4
        var src_row_off = row * g.width
        for col in range(col_lo, col_hi):
            var cov = Int(gp[unsafe_offset=src_row_off + col])
            if cov == 0:
                continue
            blend(
                s,
                dst_row_off + (x0 + col) * 4,
                Color(c.r, c.g, c.b, UInt8(cov * ca // 255)),
            )
