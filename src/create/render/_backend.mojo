from std.collections import Dict, Optional
from std.memory import unsafe_memcpy
from std.math import max, min, abs, sqrt, ceil, floor, cos, sin, pi

from create.math.matrix import Matrix, identity, inverse, apply as mat_apply

from ._command import (
    CMD_CLEAR,
    CMD_RECT,
    CMD_CIRCLE,
    CMD_LINE,
    CMD_TRIANGLE,
    CMD_SPRITE,
    CMD_TEXT,
    CMD_LETTERBOX,
    DrawCommand,
)
from ._raster import (
    blend,
    blit_sprite,
    fill_all,
    fill_pixels,
    fill_span,
    fill_triangle,
    line_pixels,
)
from ._gl_backend import GLRenderer
from ._image import _Image
from ._style import Style
from ._transform import pixel_scale, outline_thickness_px, uniform
from ._fillet import corner_fillet, rect_corner_radius, triangle_corner_radius
from ._tessellate import _arc_segments
from ._png import write_png
from .surface import MemorySurface, Surface, _force_opaque
from ._text import TextRenderer
from .render_backend import RenderBackend
from .color import Color


def device_bounds(
    m: Matrix[3, 3],
    lx0: Float64,
    ly0: Float64,
    lx1: Float64,
    ly1: Float64,
    width: Int,
    height: Int,
) -> Tuple[Int, Int, Int, Int]:
    """Device-space scan bounds for the local box `[lx0, lx1] x [ly0, ly1]`.

    Returns `(x_min, y_min, x_max, y_max)`, half-open on the maxima and
    clipped to `width` x `height`. The bounds come from the four *corners*,
    not the edge midpoints: under a rotation the midpoints are no longer the
    extremes, and scanning between them clips the shape.
    """
    var p0 = mat_apply(m, lx0, ly0)
    var p1 = mat_apply(m, lx1, ly0)
    var p2 = mat_apply(m, lx1, ly1)
    var p3 = mat_apply(m, lx0, ly1)
    var x_min = max(Int(min(min(p0[0], p1[0]), min(p2[0], p3[0]))), 0)
    var x_max = min(Int(max(max(p0[0], p1[0]), max(p2[0], p3[0]))) + 1, width)
    var y_min = max(Int(min(min(p0[1], p1[1]), min(p2[1], p3[1]))), 0)
    var y_max = min(Int(max(max(p0[1], p1[1]), max(p2[1], p3[1]))) + 1, height)
    return (x_min, y_min, x_max, y_max)


def _circle_row_span(
    pcx: Float64, dy: Float64, rad2: Float64, lo_bound: Int, hi_bound: Int
) -> Tuple[Int, Int]:
    """Integer columns in `[lo_bound, hi_bound)` where `(col - pcx)**2 + dy**2
    <= rad2` — the same per-column test `_circle`'s uniform branch used to
    make one column at a time. `sqrt` only seeds the bounds; each side is
    then walked outward while the exact same expression still passes and
    inward while it fails, which is what keeps this bit-exact with the
    per-pixel loop it replaces despite `sqrt` rounding differently than
    repeated multiplication. Returns an empty range (`lo > hi`) rather than
    raising when no column qualifies.
    """
    if lo_bound >= hi_bound:
        return (lo_bound, lo_bound - 1)
    var rem = rad2 - dy * dy
    if rem < 0.0:
        return (lo_bound, lo_bound - 1)
    var half = sqrt(rem)

    var lo = Int(pcx - half)
    while lo - 1 >= lo_bound:
        var dx = Float64(lo - 1) - pcx
        if dx * dx + dy * dy <= rad2:
            lo -= 1
        else:
            break
    while lo < hi_bound:
        var dx = Float64(lo) - pcx
        if dx * dx + dy * dy <= rad2:
            break
        lo += 1

    var hi = Int(pcx + half)
    while hi + 1 < hi_bound:
        var dx = Float64(hi + 1) - pcx
        if dx * dx + dy * dy <= rad2:
            hi += 1
        else:
            break
    while hi >= lo_bound:
        var dx = Float64(hi) - pcx
        if dx * dx + dy * dy <= rad2:
            break
        hi -= 1

    return (max(lo, lo_bound), min(hi, hi_bound - 1))


def _affine_row_span(
    v0: Float64,
    step: Float64,
    inv_step: Float64,
    col0: Int,
    lo: Float64,
    hi: Float64,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """Integer columns in `[col_lo, col_hi)` where `lo <= v0 + (col -
    col0)*step <= hi` — one axis of the rotated rect's containment test,
    solved directly instead of walked pixel by pixel. `step` is one of the
    inverse matrix's two affine coefficients (`minv[0,0]` or `minv[1,0]`),
    constant for the whole shape (not just one row), so the caller passes
    its reciprocal `inv_step` precomputed once rather than paying a
    division on every row — `step` itself is still needed for the exact
    `== 0.0` test, since multiplying by an `inv_step` of `inf` would not
    reproduce it. `v0` is the local coordinate at column `col0` — a fixed
    reference column, independent of the `[col_lo, col_hi)` clip range,
    since a caller solving an inner span clips to the outer span's columns
    while `v0` still comes from the row's start. Returns an empty range
    (`lo > hi`) rather than raising when no column qualifies. Not required
    to be bit-exact with a per-pixel walk — see the non-uniform branches
    this feeds, whose exactness policy already accepts a rounded-endpoint
    edge.

    `step` is treated as zero below a small threshold, not just at exactly
    `0.0`: a composed matrix that is mathematically axis-aligned (e.g. a
    rotate/counter-rotate pair meant to cancel) still leaves a residual on
    the order of 1e-16 in `minv[0,0]`/`minv[1,0]` after floating-point matrix
    multiplication, which `uniform()` rejects. Dividing by that residual
    turns it into an inv_step of ~1e15, which amplifies the last bit of
    rounding noise in `step` into a huge, unstable `t0`/`t1` — different
    enough frame to frame under a continuously varying transform to make the
    solved span flicker between "whole row" and "nothing". A real rotation
    or shear is many orders of magnitude above this threshold, so treating
    smaller values as zero costs no legitimate case.
    """
    if col_lo >= col_hi:
        return (col_lo, col_lo - 1)
    if abs(step) < 1e-9:
        if v0 < lo or v0 > hi:
            return (col_lo, col_lo - 1)
        return (col_lo, col_hi - 1)
    var t0 = (lo - v0) * inv_step
    var t1 = (hi - v0) * inv_step
    var c_lo = min(t0, t1)
    var c_hi = max(t0, t1)
    var start = max(Int(ceil(c_lo)) + col0, col_lo)
    var end = min(Int(floor(c_hi)) + col0, col_hi - 1)
    return (start, end)


def _ellipse_row_span(
    a: Float64,
    b: Float64,
    c: Float64,
    inv_2a: Float64,
    col0: Int,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """Integer columns in `[col_lo, col_hi)` where `a*t^2 + b*t + c <= 0`,
    `t = col - col0` — the rotated/sheared circle's per-row containment
    test, solved directly instead of walked pixel by pixel. Substituting the
    row's affine local-space coordinates (taken at reference column `col0`)
    into `dx^2 + dy^2 <= radius^2` turns it into this quadratic in `t`; `a`
    is `step_x^2 + step_y^2`, always positive for a non-degenerate
    transform and constant for the whole shape, so the caller passes
    `inv_2a = 1/(2a)` precomputed once instead of dividing by it on every
    row. The qualifying columns (if any) are the single interval between
    its two roots, offset back to absolute columns by `col0`. `col0` is
    independent of `[col_lo, col_hi)`, since a caller solving an inner span
    clips to the outer span's columns while the quadratic's coefficients
    still come from the row's start. Returns an empty range (`lo > hi`)
    when the row misses the shape entirely.

    `a` is treated as zero below a small threshold, mirroring
    `_affine_row_span`'s `step` guard — a composed matrix that is
    mathematically axis-aligned can still leave `step_x`/`step_y` as ~1e-16
    residuals rather than exact zero, and squaring them into `a` does not
    make them any less capable of sending `inv_2a` (computed by the caller
    as `1/(2a)`) to a huge, sign-unstable value. When `a` degenerates this
    way, `b` (built from the same tiny steps) degenerates with it, so
    solving the linear fallback would hit the identical blow-up — instead,
    since `c` is the implicit function's value already evaluated at the row's
    reference column `col0`, a negligible `a` means the row barely varies
    across its clip range at all, so `c`'s sign alone decides the whole run.
    """
    if col_lo >= col_hi:
        return (col_lo, col_lo - 1)
    if abs(a) < 1e-18:
        if c > 0.0:
            return (col_lo, col_lo - 1)
        return (col_lo, col_hi - 1)
    var disc = b * b - 4.0 * a * c
    if disc < 0.0:
        return (col_lo, col_lo - 1)
    var sq = sqrt(disc)
    var r0 = (-b - sq) * inv_2a
    var r1 = (-b + sq) * inv_2a
    var start = max(Int(ceil(r0)) + col0, col_lo)
    var end = min(Int(floor(r1)) + col0, col_hi - 1)
    return (start, end)


def _circle_arc_row[
    o: Origin[mut=True]
](
    s: Surface[o],
    row_off: Int,
    pcx: Float64,
    dy: Float64,
    pr2: Float64,
    pr_inner2: Float64,
    x0: Int,
    x1: Int,
    full_fill: Bool,
    outline_visible: Bool,
    fill_enabled: Bool,
    fill_col: Color,
    outline_col: Color,
):
    """One row of a circle (or a rounded rect's corner quarter-disc,
    restricted to `[x0, x1)`), factored out of `_circle`'s own uniform
    branch so both call sites share one solve. `full_fill` and `pr_inner2`
    carry the caller's `pr_inner <= 0.0` degenerate case exactly as `_circle`
    already handled it — the whole span paints in *fill* colour, not
    outline, when the outline is too thick for the radius to leave a ring.
    A pure refactor for `_circle`'s own call site: same branches, same
    order, same colours.
    """
    var outer = _circle_row_span(pcx, dy, pr2, x0, x1)
    var ol = outer[0]
    var oh = outer[1]
    if ol > oh:
        return
    if full_fill:
        fill_span(s, (row_off + ol) * 4, oh - ol + 1, fill_col)
    elif outline_visible:
        var inner = _circle_row_span(pcx, dy, pr_inner2, ol, oh + 1)
        var il = inner[0]
        var ih = inner[1]
        if il <= ih:
            if fill_enabled:
                fill_span(s, (row_off + il) * 4, ih - il + 1, fill_col)
            if il > ol:
                fill_span(s, (row_off + ol) * 4, il - ol, outline_col)
            if ih < oh:
                fill_span(s, (row_off + ih + 1) * 4, oh - ih, outline_col)
        else:
            fill_span(s, (row_off + ol) * 4, oh - ol + 1, outline_col)


def _fillet_disc_row_span(
    a: Float64,
    inv_2a: Float64,
    step_x: Float64,
    step_y: Float64,
    A0: Float64,
    B0: Float64,
    cx: Float64,
    cy: Float64,
    r2: Float64,
    col0: Int,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """`_ellipse_row_span` specialised to one fillet corner's circle, centred
    at `(cx, cy)` in local space rather than at the shape's own centre —
    `a`/`inv_2a` stay the caller's precomputed, transform-only constants."""
    var dx0 = A0 - cx
    var dy0 = B0 - cy
    var bcoef = 2.0 * (dx0 * step_x + dy0 * step_y)
    var c0 = dx0 * dx0 + dy0 * dy0 - r2
    return _ellipse_row_span(a, bcoef, c0, inv_2a, col0, col_lo, col_hi)


def _rounded_rect_row_span(
    A0: Float64,
    B0: Float64,
    col0: Int,
    step_x: Float64,
    step_y: Float64,
    inv_step_x: Float64,
    inv_step_y: Float64,
    a: Float64,
    inv_2a: Float64,
    lx0: Float64,
    ly0: Float64,
    lx1: Float64,
    ly1: Float64,
    r: Float64,
    r2: Float64,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """One row's covered columns inside a rounded rect `[lx0,lx1] x
    [ly0,ly1]` with corner radius `r`, under a non-uniform transform.

    A rounded rect is convex, so a row's covered columns are always one
    interval — this finds it as the union of up to three column-contiguous
    sub-solves, ordered by local `y` (monotone in `col` for a fixed row):
    the bottom and top corner bands each solve a straight strip plus two
    fillet discs, the middle band solves the sharp rect's own x-range
    outright, and merging by min/max of endpoints is valid precisely
    because that union stays contiguous. `r <= 0` skips all of it for the
    plain two-axis rect test `_rect`'s sharp path already used.
    """
    if r <= 0.0:
        var xr = _affine_row_span(
            A0, step_x, inv_step_x, col0, lx0, lx1, col_lo, col_hi
        )
        var yr = _affine_row_span(
            B0, step_y, inv_step_y, col0, ly0, ly1, col_lo, col_hi
        )
        return (max(xr[0], yr[0]), min(xr[1], yr[1]))

    var y_bot = _affine_row_span(
        B0, step_y, inv_step_y, col0, ly0, ly0 + r, col_lo, col_hi
    )
    var y_mid = _affine_row_span(
        B0, step_y, inv_step_y, col0, ly0 + r, ly1 - r, col_lo, col_hi
    )
    var y_top = _affine_row_span(
        B0, step_y, inv_step_y, col0, ly1 - r, ly1, col_lo, col_hi
    )

    var lo = col_hi
    var hi = col_lo - 1

    if y_mid[0] <= y_mid[1]:
        var xr = _affine_row_span(
            A0, step_x, inv_step_x, col0, lx0, lx1, y_mid[0], y_mid[1] + 1
        )
        if xr[0] <= xr[1]:
            lo = min(lo, xr[0])
            hi = max(hi, xr[1])

    if y_bot[0] <= y_bot[1]:
        var run_lo = y_bot[0]
        var run_hi = y_bot[1] + 1
        var xr = _affine_row_span(
            A0, step_x, inv_step_x, col0, lx0 + r, lx1 - r, run_lo, run_hi
        )
        if xr[0] <= xr[1]:
            lo = min(lo, xr[0])
            hi = max(hi, xr[1])
        var dl = _fillet_disc_row_span(
            a,
            inv_2a,
            step_x,
            step_y,
            A0,
            B0,
            lx0 + r,
            ly0 + r,
            r2,
            col0,
            run_lo,
            run_hi,
        )
        if dl[0] <= dl[1]:
            lo = min(lo, dl[0])
            hi = max(hi, dl[1])
        var dr = _fillet_disc_row_span(
            a,
            inv_2a,
            step_x,
            step_y,
            A0,
            B0,
            lx1 - r,
            ly0 + r,
            r2,
            col0,
            run_lo,
            run_hi,
        )
        if dr[0] <= dr[1]:
            lo = min(lo, dr[0])
            hi = max(hi, dr[1])

    if y_top[0] <= y_top[1]:
        var run_lo = y_top[0]
        var run_hi = y_top[1] + 1
        var xr = _affine_row_span(
            A0, step_x, inv_step_x, col0, lx0 + r, lx1 - r, run_lo, run_hi
        )
        if xr[0] <= xr[1]:
            lo = min(lo, xr[0])
            hi = max(hi, xr[1])
        var dl = _fillet_disc_row_span(
            a,
            inv_2a,
            step_x,
            step_y,
            A0,
            B0,
            lx0 + r,
            ly1 - r,
            r2,
            col0,
            run_lo,
            run_hi,
        )
        if dl[0] <= dl[1]:
            lo = min(lo, dl[0])
            hi = max(hi, dl[1])
        var dr = _fillet_disc_row_span(
            a,
            inv_2a,
            step_x,
            step_y,
            A0,
            B0,
            lx1 - r,
            ly1 - r,
            r2,
            col0,
            run_lo,
            run_hi,
        )
        if dr[0] <= dr[1]:
            lo = min(lo, dr[0])
            hi = max(hi, dr[1])

    return (lo, hi)


def _halfplane_row_span(
    nx: Float64,
    ny: Float64,
    d: Float64,
    A0: Float64,
    B0: Float64,
    step_x: Float64,
    step_y: Float64,
    col0: Int,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """Integer columns in `[col_lo, col_hi)` where `nx*lx + ny*ly <= d`, with
    `(lx, ly) = (A0, B0) + (col - col0) * (step_x, step_y)` — one edge of a
    convex polygon in whichever coordinate space the caller works in (device
    space directly for `_triangle`'s uniform branch, local space via the
    inverse matrix for its non-uniform branch), generalising
    `_affine_row_span`'s axis-aligned test to an edge at an arbitrary angle.
    Unlike a rect's two-sided range, one half-plane only bounds the row on
    one side, so the caller intersects several of these (one per polygon
    edge) rather than reading a single call's result as the whole span.
    """
    if col_lo >= col_hi:
        return (col_lo, col_lo - 1)
    var coef = nx * step_x + ny * step_y
    var rhs = d - nx * A0 - ny * B0
    if abs(coef) < 1e-12:
        if rhs < 0.0:
            return (col_lo, col_lo - 1)
        return (col_lo, col_hi - 1)
    var t = rhs / coef
    if coef > 0.0:
        return (col_lo, min(Int(floor(t)) + col0, col_hi - 1))
    return (max(Int(ceil(t)) + col0, col_lo), col_hi - 1)


def _edge_halfplane(
    x1: Float64,
    y1: Float64,
    x2: Float64,
    y2: Float64,
    ref_x: Float64,
    ref_y: Float64,
) -> Tuple[Float64, Float64, Float64]:
    """The inward-facing half-plane of the line through `(x1,y1)`-`(x2,y2)`,
    oriented so that `(ref_x, ref_y)` — a point already known to lie inside
    the shape, such as a triangle's centroid — satisfies it. Returns `(nx,
    ny, d)` for `nx*x + ny*y <= d`, normalised to a unit normal so several
    of these (original edges and corner-cutting chords alike) compare on the
    same footing when intersected in `_rounded_triangle_row_span`.
    """
    var ex = x2 - x1
    var ey = y2 - y1
    var elen = sqrt(ex * ex + ey * ey)
    var nx = -ey / elen
    var ny = ex / elen
    var d = nx * x1 + ny * y1
    if nx * ref_x + ny * ref_y > d:
        nx = -nx
        ny = -ny
        d = -d
    return (nx, ny, d)


def _rounded_triangle_row_span(
    A0: Float64,
    B0: Float64,
    col0: Int,
    step_x: Float64,
    step_y: Float64,
    a: Float64,
    inv_2a: Float64,
    planes: List[Tuple[Float64, Float64, Float64]],
    centers: List[Tuple[Float64, Float64]],
    r2: Float64,
    col_lo: Int,
    col_hi: Int,
) -> Tuple[Int, Int]:
    """One row's covered columns for a rounded triangle.

    A rounded triangle's filled interior is the original triangle truncated
    at each corner by the chord between that corner's two tangent points,
    unioned with a full disc at each corner's fillet centre — the chord cut
    alone would miss the straight edge bands away from the corners, and the
    three discs alone would miss the same bands from the other side, so both
    are needed together. `planes` is the truncated body's six half-planes
    (three original edges, three chords) intersected by successive
    `_halfplane_row_span` calls each narrowing the running `[lo, hi]`;
    `centers` is the three fillet centres, sharing one radius-squared `r2`
    since a triangle's corner radius is a single style value, not one per
    corner. Merging the truncated body with the three discs by min/max of
    endpoints, mirroring `_rounded_rect_row_span`'s own band merge, is valid
    because the whole rounded triangle is convex — a row's true covered set
    is always one contiguous interval no matter how many of these sub-solves
    come back empty.
    """
    if col_lo >= col_hi:
        return (col_lo, col_lo - 1)
    var lo = col_lo
    var hi = col_hi - 1
    for ref plane in planes:
        var pr = _halfplane_row_span(
            plane[0],
            plane[1],
            plane[2],
            A0,
            B0,
            step_x,
            step_y,
            col0,
            lo,
            hi + 1,
        )
        lo = pr[0]
        hi = pr[1]
        if lo > hi:
            break

    var out_lo = col_hi
    var out_hi = col_lo - 1
    if lo <= hi:
        out_lo = lo
        out_hi = hi
    for ref center in centers:
        var dr = _fillet_disc_row_span(
            a,
            inv_2a,
            step_x,
            step_y,
            A0,
            B0,
            center[0],
            center[1],
            r2,
            col0,
            col_lo,
            col_hi,
        )
        if dr[0] <= dr[1]:
            out_lo = min(out_lo, dr[0])
            out_hi = max(out_hi, dr[1])
    return (out_lo, out_hi)


def _draw_fillet_arc[
    o: Origin[mut=True]
](
    s: Surface[o],
    f: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    r: Float64,
    c: Color,
    sw: Int,
):
    """Stroke one rounded triangle corner's arc in device space, as a fan of
    `line_pixels` segments between its tangent points.

    `_triangle`'s outline is drawn as a separate pass over the fill, in
    centred device-space bands — the same convention its sharp-corner
    outline already used and deliberately different from the rounded
    rect's inset ring, so this walks the arc rather than reusing any
    rect-style inner/outer span.
    """
    var cx = f[0]
    var cy = f[1]
    var angle_in = f[6]
    var angle_out = f[7]
    var delta = angle_out - angle_in
    if delta > pi:
        delta -= 2.0 * pi
    if delta < -pi:
        delta += 2.0 * pi
    var segs = _arc_segments(r, delta)
    var prev_x = f[2]
    var prev_y = f[3]
    for i in range(1, segs + 1):
        var t = Float64(i) / Float64(segs)
        var ang = angle_in + delta * t
        var cur_x = cx + r * cos(ang)
        var cur_y = cy + r * sin(ang)
        line_pixels(s, prev_x, prev_y, cur_x, cur_y, c, sw)
        prev_x = cur_x
        prev_y = cur_y


def _draw_fillet_arc_mapped[
    o: Origin[mut=True]
](
    s: Surface[o],
    m: Matrix[3, 3],
    scale: Float64,
    f: Tuple[
        Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64
    ],
    r: Float64,
    c: Color,
    sw: Int,
):
    """`_draw_fillet_arc`'s non-uniform counterpart.

    The fillet's circle is only genuinely a circle in local space — under a
    rotation or non-uniform scale it becomes an ellipse, so there is no
    single device-space arc formula to walk. Instead the arc is sampled in
    local space (where `f`'s centre, tangents and angles were computed) and
    each sample point is mapped through `m` individually before stroking.
    """
    var cx = f[0]
    var cy = f[1]
    var angle_in = f[6]
    var angle_out = f[7]
    var delta = angle_out - angle_in
    if delta > pi:
        delta -= 2.0 * pi
    if delta < -pi:
        delta += 2.0 * pi
    var segs = _arc_segments(r * pixel_scale(m, scale), delta)
    var prev = mat_apply(m, cx + r * cos(angle_in), cy + r * sin(angle_in))
    var prev_x = prev[0]
    var prev_y = prev[1]
    for i in range(1, segs + 1):
        var t = Float64(i) / Float64(segs)
        var ang = angle_in + delta * t
        var cur = mat_apply(m, cx + r * cos(ang), cy + r * sin(ang))
        line_pixels(s, prev_x, prev_y, cur[0], cur[1], c, sw)
        prev_x = cur[0]
        prev_y = cur[1]


@fieldwise_init
struct _ImageRequest(Movable):
    """A `frame.save_image` that has not been serviced yet.

    Filed while recording and flushed at present, because present is the only
    place holding both the finished command buffer and a target to replay it
    onto. Deferring also makes the contract honest: the file gets the *whole*
    frame no matter where in `render` the call was made.
    """

    var path: String
    var width: Int
    var height: Int
    var scale: Float64
    """The capture's pixel scale — the fallback for commands whose transform
    is not uniform, exactly as the live frame's autoscale factor is."""
    var rebase: Matrix[3, 3]
    """`capture_base @ window_base_inv` — see `replay`'s `pre`."""
    var transparent: Bool


struct Backend(Movable):
    """Where a frame's recorded commands become pixels.

    One struct with a runtime branch on `kind` rather than a trait: Mojo 1.0
    has no dynamic trait dispatch, so a trait in type position would form an
    inert `AnyTrait[T]` that nothing converts into.

    This is what survives the frame boundary. Fonts and glyph masks already
    had to — reloading a face every frame would be absurd — and GPU resources
    join them for exactly the same reason, so the backend is the natural owner
    of both.
    """

    var kind: Int
    var text: TextRenderer
    var images: Dict[Int, _Image]
    var gl: Optional[GLRenderer]
    """The GPU resources, present exactly when `kind == RenderBackend.GPU`.

    They live on `Backend` rather than beside it so that the fonts, the image
    cache and the command buffer stay in one place whichever path presents
    them — `kind` then means what it says, and a sprite interned for the CPU
    replay is the same entry the GL path will key a texture from.
    """
    var pending_screenshot: Optional[String]
    """A `save_screenshot` filed by this frame, serviced at present.

    Just a path: a screenshot has no geometry to decide, which is the whole
    difference from `_ImageRequest` — it is whatever the framebuffer holds
    once the frame has been drawn.
    """
    var pending_image: Optional[_ImageRequest]
    """A `save_image` filed by this frame, serviced at present.

    One per frame: a second call overwrites the first, which is the only
    sensible reading of two saves of the same frame to two paths being asked
    for by accident.
    """
    var commands: List[DrawCommand]
    """The frame being recorded.

    The buffer lives here rather than travelling out of `Frame` because a
    `Tuple` of move-only values cannot be unpacked in this Mojo version — see
    `present`, which is also where the buffer is reset. Keeping it means the
    allocation is reused frame to frame instead of being rebuilt per frame.
    """

    def __init__(out self, kind: Int = RenderBackend.CPU) raises:
        """A GPU backend builds its GL resources here, so a current context
        is a precondition of `RenderBackend.GPU` — the GL run loop opens its window
        first for exactly that reason."""
        self.kind = kind
        self.text = TextRenderer()
        self.images = Dict[Int, _Image]()
        self.commands = List[DrawCommand]()
        self.pending_image = Optional[_ImageRequest]()
        self.pending_screenshot = Optional[String]()
        self.gl = Optional[GLRenderer]()
        if kind == RenderBackend.GPU:
            self.gl = Optional(GLRenderer())

    def record(mut self, var c: DrawCommand):
        """Append one draw to the frame being recorded."""
        self.commands.append(c^)

    def record_clear(mut self, var c: DrawCommand):
        """Append a clear, replacing an adjacent one it would erase anyway.

        An opaque clear covers the whole framebuffer, so any clear recorded
        immediately before it — with no draw in between to survive — paints
        nothing. Dropping it here rather than at replay keeps both backends
        and both captures agreeing, and costs the common case nothing: a
        program that sets `autoclear` and also opens `update` with
        `background()` records one clear, not two.
        """
        if (
            c.style.fill_color.a == 255
            and len(self.commands) > 0
            and self.commands[len(self.commands) - 1].kind == CMD_CLEAR
        ):
            self.commands[len(self.commands) - 1] = c^
            return
        self.commands.append(c^)

    def request_image(mut self, var request: _ImageRequest):
        """File a design-resolution capture of the frame being recorded."""
        self.pending_image = Optional(request^)

    def request_screenshot(mut self, path: String):
        """File a framebuffer-resolution capture of the frame being recorded."""
        self.pending_screenshot = Optional(path)

    def _discard_recording(mut self):
        """Throw away a recording that will never be presented.

        `commands` is cleared only by `present`/`present_gpu`, and must stay
        that way: the loop presents *after* the frame body has returned, so a
        frame's draws have to survive `Frame._release`. The frame handed to
        `Program.create` is the one frame that is never presented, so without
        this its draws — and any `save_image` or `save_screenshot` it filed —
        would be replayed and written as part of frame one.
        """
        self.commands.clear()
        self.pending_image = Optional[_ImageRequest]()
        self.pending_screenshot = Optional[String]()

    def _flush_screenshot[o: Origin[mut=True]](mut self, s: Surface[o]) raises:
        """Service a pending `save_screenshot` by copying the finished buffer.

        After `replay`, so the bars are in it — a screenshot is what the user
        saw, and at this point `s` already is that. Near-free: a copy of the
        frame, with no second rasterisation.
        """
        if not self.pending_screenshot:
            return
        var path = self.pending_screenshot.take()
        var mem = MemorySurface(s.width, s.height)
        unsafe_memcpy(
            dest=mem.data.unsafe_ptr(),
            src=s.px,
            count=s.width * s.height * 4,
        )
        mem.save(path)

    def _flush_screenshot_gpu(mut self, width: Int, height: Int) raises:
        """The GPU counterpart: read the real framebuffer back off the driver.

        There is no host buffer to copy from here, so this is the one capture
        that costs a pipeline stall — see `GLRenderer.read_frame`. It runs
        after `draw` and before the run loop's buffer swap, which is the only
        window in which the finished frame is still the one being read.
        """
        if not self.pending_screenshot:
            return
        var path = self.pending_screenshot.take()
        var frame = self.gl.value().read_frame(width, height)
        _force_opaque(frame)
        write_png(frame, width, height, path)

    def _flush_image(mut self, cmds: List[DrawCommand]) raises:
        """Service a pending `save_image` by replaying `cmds` a second time.

        Onto an owned buffer of the capture's own size, through the CPU
        rasteriser under both backends — the glyph cache and the image cache
        live here rather than on `GLRenderer`, so a GPU frame needs no readback
        to be captured at a resolution the window never had.

        The bars are dropped by contract: the capture is the design area, and
        a bar is a property of the window it is not being saved at. A
        transparent capture drops the frame's clear as well, so the background
        keeps the buffer's alpha 0.
        """
        if not self.pending_image:
            return
        var request = self.pending_image.take()
        var mem = MemorySurface(request.width, request.height)
        self.replay(
            mem.surface(),
            cmds,
            request.scale,
            pre=request.rebase,
            skip_kinds=(
                (1 << CMD_LETTERBOX)
                | (1 << CMD_CLEAR) if request.transparent else (
                    1 << CMD_LETTERBOX
                )
            ),
        )
        mem.save(request.path, opaque=not request.transparent)

    def present[
        o: Origin[mut=True]
    ](mut self, s: Surface[o], scale: Float64) raises:
        """Draw the recorded frame onto `s` and start a new recording.

        The buffer is moved out and back rather than iterated in place: replay
        needs `self` mutably (the glyph cache and the image cache both fill in
        as it runs), which it cannot have while borrowing a field of `self`.
        Moving it back keeps its capacity for the next frame.
        """
        var cmds = self.commands^
        self.commands = List[DrawCommand]()
        self.replay(s, cmds, scale)
        self._flush_screenshot(s)
        self._flush_image(cmds)
        cmds.clear()
        self.commands = cmds^

    def present_gpu(mut self, width: Int, height: Int, scale: Float64) raises:
        """The GPU counterpart of `present`, onto the current drawable.

        Same contract: the frame is consumed and the recording left empty with
        its capacity intact. There is no `Surface` because there is no host
        pixel buffer — `width` and `height` are the drawable's, which is what
        the letterbox bars and `glViewport` are sized from.
        """
        if not self.gl:
            raise Error(
                "present_gpu called on a backend that has no GL renderer —"
                " construct it with kind=RenderBackend.GPU"
            )
        var cmds = self.commands^
        self.commands = List[DrawCommand]()
        self.gl.value().draw(cmds, self.images, self.text, width, height, scale)
        self._flush_screenshot_gpu(width, height)
        self._flush_image(cmds)
        cmds.clear()
        self.commands = cmds^

    def intern_image[
        so: Origin
    ](
        mut self, key: Int, src: Pointer[UInt8, so], width: Int, height: Int
    ) -> Int:
        """Return a backend id for the `width` x `height` RGBA buffer at `src`.

        Copies on first sight and returns the cached id thereafter, so a sprite
        drawn every frame is copied once. `key` must be stable for the life of
        the image — a `Sprite`'s identity, not its pixel address, which could
        be reused after a free.

        Called while recording rather than at replay, which is what keeps a
        borrow of caller-owned memory out of the command buffer.
        """
        if key in self.images:
            return key
        var buf = List[UInt8](length=width * height * 4, fill=0)
        for i in range(width * height * 4):
            buf[i] = src[unsafe_offset=i]
        self.images[key] = _Image(buf^, width, height)
        return key

    def replay[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        cmds: List[DrawCommand],
        scale: Float64,
        pre: Matrix[3, 3] = identity[3](),
        skip_kinds: Int = 0,
    ) raises:
        """Draw `cmds` onto `s`, in order.

        `scale` is the frame's autoscale factor — the fallback pixel scale for
        commands whose transform is not uniform. It is constant for a frame, so
        it travels here rather than on every command.

        `pre` multiplies every command's transform on the left, and exists
        because a capture replays a frame whose commands were recorded against
        a *different* mapping: `Frame` bakes the window's base matrix into
        each one, so writing that same frame into a design-sized buffer needs
        `capture_base @ window_base_inverse` in front of it. Identity on the
        live path, which is therefore unchanged.

        `skip_kinds` is a bit per command kind — `1 << CMD_LETTERBOX` for a
        capture that is bar-free by contract, plus `1 << CMD_CLEAR` for one
        with a transparent background. A mask rather than a single kind
        because a transparent capture drops both, and `0` drops nothing.
        """
        for ref c in cmds:
            if skip_kinds & (1 << c.kind) == 0:
                self._one(s, c, scale, pre)

    def _one[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        pre: Matrix[3, 3],
    ) raises:
        # The one place the pre-matrix is composed, so no per-kind helper has
        # to remember to do it.
        var m = pre @ c.transform
        if c.kind == CMD_CLEAR:
            fill_all(s, c.style.fill_color)
        elif c.kind == CMD_RECT:
            self._rect(s, c, scale, m)
        elif c.kind == CMD_CIRCLE:
            self._circle(s, c, scale, m)
        elif c.kind == CMD_LINE:
            self._line(s, c, scale, m)
        elif c.kind == CMD_TRIANGLE:
            self._triangle(s, c, scale, m)
        elif c.kind == CMD_SPRITE:
            self._sprite(s, c, scale, m)
        elif c.kind == CMD_TEXT:
            self._text(s, c, scale, m)
        elif c.kind == CMD_LETTERBOX:
            self._letterbox(s, c)

    def _rect[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ):
        var W = s.width
        var x = c.geom[0]
        var y = c.geom[1]
        var lx0 = x - c.geom[2] / 2.0
        var ly0 = y - c.geom[3] / 2.0
        var lx1 = x + c.geom[2] / 2.0
        var ly1 = y + c.geom[3] / 2.0

        var r_local = rect_corner_radius(
            Float64(c.style.corner_radius), c.geom[2], c.geom[3]
        )

        if uniform(m):
            # Axis-aligned: map the two opposite corners and order them, since
            # the y flip in the base mapping sends the smaller world y to the
            # larger pixel row.
            var p0 = mat_apply(m, lx0, ly0)
            var p1 = mat_apply(m, lx1, ly1)
            var x0 = Int(min(p0[0], p1[0]))
            var y0 = Int(min(p0[1], p1[1]))
            var iw = Int(abs(p1[0] - p0[0]))
            var ih = Int(abs(p1[1] - p0[1]))
            if r_local <= 0.0:
                if c.style.fill_visible():
                    fill_pixels(s, x0, y0, x0 + iw, y0 + ih, c.style.fill_color)
                if c.style.outline_visible():
                    var sw = outline_thickness_px(c.style, m, scale)
                    var sc = c.style.outline_color
                    fill_pixels(s, x0, y0, x0 + iw, y0 + sw, sc)
                    fill_pixels(s, x0, y0 + ih - sw, x0 + iw, y0 + ih, sc)
                    fill_pixels(s, x0, y0 + sw, x0 + sw, y0 + ih - sw, sc)
                    fill_pixels(
                        s, x0 + iw - sw, y0 + sw, x0 + iw, y0 + ih - sw, sc
                    )
            else:
                # Cross decomposition, same shape as the sharp path above but
                # shortened by the clamped device-space radius `pr`: a
                # full-height centre band, two full-width middle bands, and
                # four corner quarter-discs through `_circle_arc_row` — the
                # same helper `_circle` uses, so a corner too thick for its
                # outline degenerates exactly like a circle does (a solid
                # disc in *fill* colour, not outline).
                var pr = r_local * pixel_scale(m, scale)
                var pr_i = Int(pr)
                var fill_enabled = c.style.fill_visible()
                var outline_enabled = c.style.outline_visible()
                var fill_col = c.style.fill_color
                var outline_col = c.style.outline_color
                var sw = outline_thickness_px(
                    c.style, m, scale
                ) if outline_enabled else 0
                if fill_enabled:
                    fill_pixels(
                        s, x0 + pr_i, y0, x0 + iw - pr_i, y0 + ih, fill_col
                    )
                    fill_pixels(
                        s, x0, y0 + pr_i, x0 + pr_i, y0 + ih - pr_i, fill_col
                    )
                    fill_pixels(
                        s,
                        x0 + iw - pr_i,
                        y0 + pr_i,
                        x0 + iw,
                        y0 + ih - pr_i,
                        fill_col,
                    )
                if outline_enabled:
                    fill_pixels(
                        s, x0 + pr_i, y0, x0 + iw - pr_i, y0 + sw, outline_col
                    )
                    fill_pixels(
                        s,
                        x0 + pr_i,
                        y0 + ih - sw,
                        x0 + iw - pr_i,
                        y0 + ih,
                        outline_col,
                    )
                    fill_pixels(
                        s, x0, y0 + pr_i, x0 + sw, y0 + ih - pr_i, outline_col
                    )
                    fill_pixels(
                        s,
                        x0 + iw - sw,
                        y0 + pr_i,
                        x0 + iw,
                        y0 + ih - pr_i,
                        outline_col,
                    )
                var pr2 = pr * pr
                var pr_inner = pr - Float64(sw)
                var pr_inner2 = pr_inner * pr_inner
                var full_fill = fill_enabled and (
                    not outline_enabled or pr_inner <= 0.0
                )
                var tl_cx = Float64(x0) + pr
                var tl_cy = Float64(y0) + pr
                var tr_cx = Float64(x0 + iw) - pr
                var bl_cy = Float64(y0 + ih) - pr
                for row in range(y0, y0 + pr_i):
                    var row_off = row * W
                    var dy = Float64(row) - tl_cy
                    _circle_arc_row(
                        s,
                        row_off,
                        tl_cx,
                        dy,
                        pr2,
                        pr_inner2,
                        x0,
                        x0 + pr_i,
                        full_fill,
                        outline_enabled,
                        fill_enabled,
                        fill_col,
                        outline_col,
                    )
                    _circle_arc_row(
                        s,
                        row_off,
                        tr_cx,
                        dy,
                        pr2,
                        pr_inner2,
                        x0 + iw - pr_i,
                        x0 + iw,
                        full_fill,
                        outline_enabled,
                        fill_enabled,
                        fill_col,
                        outline_col,
                    )
                for row in range(y0 + ih - pr_i, y0 + ih):
                    var row_off = row * W
                    var dy = Float64(row) - bl_cy
                    _circle_arc_row(
                        s,
                        row_off,
                        tl_cx,
                        dy,
                        pr2,
                        pr_inner2,
                        x0,
                        x0 + pr_i,
                        full_fill,
                        outline_enabled,
                        fill_enabled,
                        fill_col,
                        outline_col,
                    )
                    _circle_arc_row(
                        s,
                        row_off,
                        tr_cx,
                        dy,
                        pr2,
                        pr_inner2,
                        x0 + iw - pr_i,
                        x0 + iw,
                        full_fill,
                        outline_enabled,
                        fill_enabled,
                        fill_col,
                        outline_col,
                    )
        else:
            # Rotated/sheared: the inverse mapping is still affine (no
            # perspective row), so a device column maps to local space by
            # `local0 + col * (minv[0,0], minv[1,0])` — linear in `col`. The
            # rect's containment test is two independent range checks (`lx`
            # inside `[lx0,lx1]`, `ly` inside `[ly0,ly1]`), and each is linear
            # in `col`, so `_affine_row_span` solves the qualifying column
            # range directly per axis instead of walking pixels; the row's
            # covered run is their intersection. A outline splits that run
            # into an inner fill span (same solve, shrunk by the outline
            # width) and up to two outline spans flanking it, mirroring the
            # uniform circle branch below. Not bit-exact with the old
            # per-pixel test — an edge pixel may land one column off — which
            # this phase's exactness policy accepts and `test_gl_parity.mojo`
            # gates.
            var minv = inverse(m)
            var b = device_bounds(m, lx0, ly0, lx1, ly1, s.width, s.height)
            var sw_f = Float64(c.style.outline_thickness)
            var step_x = minv[0, 0]
            var step_y = minv[1, 0]
            var inv_step_x = 1.0 / step_x if step_x != 0.0 else 0.0
            var inv_step_y = 1.0 / step_y if step_y != 0.0 else 0.0
            if r_local <= 0.0:
                var fill_enabled = c.style.fill_visible()
                var outline_enabled = c.style.outline_visible()
                var fill_col = c.style.fill_color
                var outline_col = c.style.outline_color
                for row in range(b[1], b[3]):
                    var local0 = mat_apply(minv, Float64(b[0]), Float64(row))
                    var A = local0[0]
                    var B = local0[1]
                    var row_off = row * W
                    var xr = _affine_row_span(
                        A, step_x, inv_step_x, b[0], lx0, lx1, b[0], b[2]
                    )
                    var yr = _affine_row_span(
                        B, step_y, inv_step_y, b[0], ly0, ly1, b[0], b[2]
                    )
                    var outer_lo = max(xr[0], yr[0])
                    var outer_hi = min(xr[1], yr[1])
                    if outer_lo > outer_hi:
                        continue
                    if not outline_enabled:
                        if fill_enabled:
                            fill_span(
                                s,
                                (row_off + outer_lo) * 4,
                                outer_hi - outer_lo + 1,
                                fill_col,
                            )
                        continue
                    var xi = _affine_row_span(
                        A,
                        step_x,
                        inv_step_x,
                        b[0],
                        lx0 + sw_f,
                        lx1 - sw_f,
                        outer_lo,
                        outer_hi + 1,
                    )
                    var yi = _affine_row_span(
                        B,
                        step_y,
                        inv_step_y,
                        b[0],
                        ly0 + sw_f,
                        ly1 - sw_f,
                        outer_lo,
                        outer_hi + 1,
                    )
                    var inner_lo = max(xi[0], yi[0])
                    var inner_hi = min(xi[1], yi[1])
                    if inner_lo <= inner_hi:
                        if fill_enabled:
                            fill_span(
                                s,
                                (row_off + inner_lo) * 4,
                                inner_hi - inner_lo + 1,
                                fill_col,
                            )
                        if inner_lo > outer_lo:
                            fill_span(
                                s,
                                (row_off + outer_lo) * 4,
                                inner_lo - outer_lo,
                                outline_col,
                            )
                        if inner_hi < outer_hi:
                            fill_span(
                                s,
                                (row_off + inner_hi + 1) * 4,
                                outer_hi - inner_hi,
                                outline_col,
                            )
                    else:
                        fill_span(
                            s,
                            (row_off + outer_lo) * 4,
                            outer_hi - outer_lo + 1,
                            outline_col,
                        )
            else:
                # Same outer/inner span shape as the sharp path above, but
                # both spans come from `_rounded_rect_row_span` instead of a
                # plain two-axis intersection. The inner (fill) shape is
                # inset by the outline width on both the rect and its
                # radius; when that leaves the radius at or below zero,
                # `_rounded_rect_row_span`'s own `r <= 0` branch falls back
                # to the sharp two-axis test, so a corner too thick for its
                # outline gets a sharp inner silhouette rather than a
                # negative radius.
                var fill_enabled = c.style.fill_visible()
                var outline_enabled = c.style.outline_visible()
                var fill_col = c.style.fill_color
                var outline_col = c.style.outline_color
                var r2 = r_local * r_local
                var a = step_x * step_x + step_y * step_y
                var inv_2a = 1.0 / (2.0 * a) if abs(a) >= 1e-18 else 0.0
                var inner_r = r_local - sw_f
                var inner_r2 = inner_r * inner_r if inner_r > 0.0 else 0.0
                for row in range(b[1], b[3]):
                    var local0 = mat_apply(minv, Float64(b[0]), Float64(row))
                    var A0 = local0[0]
                    var B0 = local0[1]
                    var row_off = row * W
                    var outer = _rounded_rect_row_span(
                        A0,
                        B0,
                        b[0],
                        step_x,
                        step_y,
                        inv_step_x,
                        inv_step_y,
                        a,
                        inv_2a,
                        lx0,
                        ly0,
                        lx1,
                        ly1,
                        r_local,
                        r2,
                        b[0],
                        b[2],
                    )
                    var outer_lo = outer[0]
                    var outer_hi = outer[1]
                    if outer_lo > outer_hi:
                        continue
                    if not outline_enabled:
                        if fill_enabled:
                            fill_span(
                                s,
                                (row_off + outer_lo) * 4,
                                outer_hi - outer_lo + 1,
                                fill_col,
                            )
                        continue
                    var inner = _rounded_rect_row_span(
                        A0,
                        B0,
                        b[0],
                        step_x,
                        step_y,
                        inv_step_x,
                        inv_step_y,
                        a,
                        inv_2a,
                        lx0 + sw_f,
                        ly0 + sw_f,
                        lx1 - sw_f,
                        ly1 - sw_f,
                        inner_r,
                        inner_r2,
                        outer_lo,
                        outer_hi + 1,
                    )
                    var inner_lo = inner[0]
                    var inner_hi = inner[1]
                    if inner_lo <= inner_hi:
                        if fill_enabled:
                            fill_span(
                                s,
                                (row_off + inner_lo) * 4,
                                inner_hi - inner_lo + 1,
                                fill_col,
                            )
                        if inner_lo > outer_lo:
                            fill_span(
                                s,
                                (row_off + outer_lo) * 4,
                                inner_lo - outer_lo,
                                outline_col,
                            )
                        if inner_hi < outer_hi:
                            fill_span(
                                s,
                                (row_off + inner_hi + 1) * 4,
                                outer_hi - inner_hi,
                                outline_col,
                            )
                    else:
                        fill_span(
                            s,
                            (row_off + outer_lo) * 4,
                            outer_hi - outer_lo + 1,
                            outline_col,
                        )

    def _circle[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ):
        var W = s.width
        var H = s.height
        var cx = c.geom[0]
        var cy = c.geom[1]
        var r = c.geom[2]
        var r2 = r * r
        var r_inner = r - Float64(c.style.outline_thickness)
        var r_inner2 = r_inner * r_inner

        if uniform(m):
            # A uniform scale keeps a circle a circle, so it stays a distance
            # test — just in pixels rather than world units.
            var p = mat_apply(m, cx, cy)
            var pcx = p[0]
            var pcy = p[1]
            var pr = r * pixel_scale(m, scale)
            var pr2 = pr * pr
            var pr_inner = pr - Float64(outline_thickness_px(c.style, m, scale))
            var pr_inner2 = pr_inner * pr_inner
            var x0 = max(Int(pcx - pr), 0)
            var y0 = max(Int(pcy - pr), 0)
            var x1 = min(Int(pcx + pr) + 1, W)
            var y1 = min(Int(pcy + pr) + 1, H)
            # Whether a row's *entire* outer span is fill, with no outline ever
            # drawn — matches the per-pixel `if`'s "or pr_inner <= 0.0" arm,
            # which shortcuts to true regardless of `d2` and so never leaves
            # the `elif` reachable.
            var full_fill = c.style.fill_visible() and (
                not c.style.outline_visible() or pr_inner <= 0.0
            )
            var fill_enabled = c.style.fill_visible()
            var outline_enabled = c.style.outline_visible()
            var fill_col = c.style.fill_color
            var outline_col = c.style.outline_color
            for row in range(y0, y1):
                var dy = Float64(row) - pcy
                _circle_arc_row(
                    s,
                    row * W,
                    pcx,
                    dy,
                    pr2,
                    pr_inner2,
                    x0,
                    x1,
                    full_fill,
                    outline_enabled,
                    fill_enabled,
                    fill_col,
                    outline_col,
                )
        else:
            # Same trick as the rotated rect branch above, adapted to a
            # quadratic: a device column maps to local space by `local0 +
            # col * (step_x, step_y)`, so substituting into `dx^2 + dy^2 <=
            # r^2` turns the row's containment test into `a*col^2 + b*col +
            # c <= 0` with `a = step_x^2 + step_y^2` constant across the
            # whole shape. `_ellipse_row_span` solves that directly instead
            # of walking pixels; outline handling mirrors the uniform branch
            # above (outer span, then a shrunk inner span for the fill,
            # flanked by up to two outline spans). Not bit-exact with the old
            # per-pixel walk, which this phase's exactness policy accepts.
            var minv = inverse(m)
            var b = device_bounds(m, cx - r, cy - r, cx + r, cy + r, W, H)
            var step_x = minv[0, 0]
            var step_y = minv[1, 0]
            var fill_enabled = c.style.fill_visible()
            var outline_enabled = c.style.outline_visible()
            var fill_col = c.style.fill_color
            var outline_col = c.style.outline_color
            var full_fill = not outline_enabled or r_inner <= 0.0
            var a = step_x * step_x + step_y * step_y
            var inv_2a = 1.0 / (2.0 * a)
            for row in range(b[1], b[3]):
                var local0 = mat_apply(minv, Float64(b[0]), Float64(row))
                var dx0 = local0[0] - cx
                var dy0 = local0[1] - cy
                var row_off = row * W
                var bcoef = 2.0 * (dx0 * step_x + dy0 * step_y)
                var c_outer = dx0 * dx0 + dy0 * dy0 - r2
                var outer = _ellipse_row_span(
                    a, bcoef, c_outer, inv_2a, b[0], b[0], b[2]
                )
                var ol = outer[0]
                var oh = outer[1]
                if ol > oh:
                    continue
                if full_fill:
                    if fill_enabled:
                        fill_span(s, (row_off + ol) * 4, oh - ol + 1, fill_col)
                    continue
                var c_inner = dx0 * dx0 + dy0 * dy0 - r_inner2
                var inner = _ellipse_row_span(
                    a, bcoef, c_inner, inv_2a, b[0], ol, oh + 1
                )
                var il = inner[0]
                var ih = inner[1]
                if il <= ih:
                    if fill_enabled:
                        fill_span(s, (row_off + il) * 4, ih - il + 1, fill_col)
                    if il > ol:
                        fill_span(s, (row_off + ol) * 4, il - ol, outline_col)
                    if ih < oh:
                        fill_span(
                            s, (row_off + ih + 1) * 4, oh - ih, outline_col
                        )
                else:
                    fill_span(s, (row_off + ol) * 4, oh - ol + 1, outline_col)

    def _line[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ):
        if not c.style.outline_visible():
            return
        var p0 = mat_apply(m, c.geom[0], c.geom[1])
        var p1 = mat_apply(m, c.geom[2], c.geom[3])
        line_pixels(
            s,
            p0[0],
            p0[1],
            p1[0],
            p1[1],
            c.style.outline_color,
            outline_thickness_px(c.style, m, scale),
        )

    def _triangle[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ):
        var lx1 = c.geom[0]
        var ly1 = c.geom[1]
        var lx2 = c.geom[2]
        var ly2 = c.geom[3]
        var lx3 = c.geom[4]
        var ly3 = c.geom[5]
        var p1 = mat_apply(m, lx1, ly1)
        var p2 = mat_apply(m, lx2, ly2)
        var p3 = mat_apply(m, lx3, ly3)

        var r_local = triangle_corner_radius(
            Float64(c.style.corner_radius), lx1, ly1, lx2, ly2, lx3, ly3
        )

        if r_local <= 0.0:
            if c.style.fill_visible():
                fill_triangle(
                    s,
                    p1[0],
                    p1[1],
                    p2[0],
                    p2[1],
                    p3[0],
                    p3[1],
                    c.style.fill_color,
                )
            if c.style.outline_visible():
                var sw = outline_thickness_px(c.style, m, scale)
                var sc = c.style.outline_color
                line_pixels(s, p1[0], p1[1], p2[0], p2[1], sc, sw)
                line_pixels(s, p2[0], p2[1], p3[0], p3[1], sc, sw)
                line_pixels(s, p3[0], p3[1], p1[0], p1[1], sc, sw)
            return

        var fill_enabled = c.style.fill_visible()
        var outline_enabled = c.style.outline_visible()
        var fill_col = c.style.fill_color
        var outline_col = c.style.outline_color
        var W = s.width
        var x_min = max(Int(floor(min(min(p1[0], p2[0]), p3[0]))), 0)
        var x_max = min(Int(ceil(max(max(p1[0], p2[0]), p3[0]))) + 1, s.width)
        var y_min = max(Int(floor(min(min(p1[1], p2[1]), p3[1]))), 0)
        var y_max = min(Int(ceil(max(max(p1[1], p2[1]), p3[1]))) + 1, s.height)

        # Corner `i`'s prev/next follow the winding order `p1 -> p2 -> p3 ->
        # p1`, so `f0`'s incoming tangent sits on edge p3-p1 and its outgoing
        # tangent on edge p1-p2 — the straight outline bands below connect
        # `fI`'s outgoing tangent to `fJ`'s incoming one along each original
        # edge, matching `corner_fillet`'s own docstring.
        if uniform(m):
            var pr = r_local * pixel_scale(m, scale)
            var f0 = corner_fillet(p1[0], p1[1], p3[0], p3[1], p2[0], p2[1], pr)
            var f1 = corner_fillet(p2[0], p2[1], p1[0], p1[1], p3[0], p3[1], pr)
            var f2 = corner_fillet(p3[0], p3[1], p2[0], p2[1], p1[0], p1[1], pr)
            var cx = (p1[0] + p2[0] + p3[0]) / 3.0
            var cy = (p1[1] + p2[1] + p3[1]) / 3.0
            var planes = List[Tuple[Float64, Float64, Float64]]()
            planes.append(_edge_halfplane(p1[0], p1[1], p2[0], p2[1], cx, cy))
            planes.append(_edge_halfplane(p2[0], p2[1], p3[0], p3[1], cx, cy))
            planes.append(_edge_halfplane(p3[0], p3[1], p1[0], p1[1], cx, cy))
            planes.append(_edge_halfplane(f0[2], f0[3], f0[4], f0[5], cx, cy))
            planes.append(_edge_halfplane(f1[2], f1[3], f1[4], f1[5], cx, cy))
            planes.append(_edge_halfplane(f2[2], f2[3], f2[4], f2[5], cx, cy))
            var centers = List[Tuple[Float64, Float64]]()
            centers.append((f0[0], f0[1]))
            centers.append((f1[0], f1[1]))
            centers.append((f2[0], f2[1]))
            var r2 = pr * pr

            if fill_enabled:
                for row in range(y_min, y_max):
                    var span = _rounded_triangle_row_span(
                        Float64(x_min),
                        Float64(row),
                        x_min,
                        1.0,
                        0.0,
                        1.0,
                        0.5,
                        planes,
                        centers,
                        r2,
                        x_min,
                        x_max,
                    )
                    if span[0] <= span[1]:
                        fill_span(
                            s,
                            (row * W + span[0]) * 4,
                            span[1] - span[0] + 1,
                            fill_col,
                        )

            if outline_enabled:
                var sw = outline_thickness_px(c.style, m, scale)
                line_pixels(s, f0[4], f0[5], f1[2], f1[3], outline_col, sw)
                line_pixels(s, f1[4], f1[5], f2[2], f2[3], outline_col, sw)
                line_pixels(s, f2[4], f2[5], f0[2], f0[3], outline_col, sw)
                _draw_fillet_arc(s, f0, pr, outline_col, sw)
                _draw_fillet_arc(s, f1, pr, outline_col, sw)
                _draw_fillet_arc(s, f2, pr, outline_col, sw)
        else:
            var minv = inverse(m)
            var step_x = minv[0, 0]
            var step_y = minv[1, 0]
            var f0 = corner_fillet(lx1, ly1, lx3, ly3, lx2, ly2, r_local)
            var f1 = corner_fillet(lx2, ly2, lx1, ly1, lx3, ly3, r_local)
            var f2 = corner_fillet(lx3, ly3, lx2, ly2, lx1, ly1, r_local)
            var cx = (lx1 + lx2 + lx3) / 3.0
            var cy = (ly1 + ly2 + ly3) / 3.0
            var planes = List[Tuple[Float64, Float64, Float64]]()
            planes.append(_edge_halfplane(lx1, ly1, lx2, ly2, cx, cy))
            planes.append(_edge_halfplane(lx2, ly2, lx3, ly3, cx, cy))
            planes.append(_edge_halfplane(lx3, ly3, lx1, ly1, cx, cy))
            planes.append(_edge_halfplane(f0[2], f0[3], f0[4], f0[5], cx, cy))
            planes.append(_edge_halfplane(f1[2], f1[3], f1[4], f1[5], cx, cy))
            planes.append(_edge_halfplane(f2[2], f2[3], f2[4], f2[5], cx, cy))
            var centers = List[Tuple[Float64, Float64]]()
            centers.append((f0[0], f0[1]))
            centers.append((f1[0], f1[1]))
            centers.append((f2[0], f2[1]))
            var r2 = r_local * r_local
            var a = step_x * step_x + step_y * step_y
            var inv_2a = 1.0 / (2.0 * a) if abs(a) >= 1e-18 else 0.0

            if fill_enabled:
                for row in range(y_min, y_max):
                    var local0 = mat_apply(minv, Float64(x_min), Float64(row))
                    var span = _rounded_triangle_row_span(
                        local0[0],
                        local0[1],
                        x_min,
                        step_x,
                        step_y,
                        a,
                        inv_2a,
                        planes,
                        centers,
                        r2,
                        x_min,
                        x_max,
                    )
                    if span[0] <= span[1]:
                        fill_span(
                            s,
                            (row * W + span[0]) * 4,
                            span[1] - span[0] + 1,
                            fill_col,
                        )

            if outline_enabled:
                var sw = outline_thickness_px(c.style, m, scale)
                var t_f0_out = mat_apply(m, f0[4], f0[5])
                var t_f1_in = mat_apply(m, f1[2], f1[3])
                var t_f1_out = mat_apply(m, f1[4], f1[5])
                var t_f2_in = mat_apply(m, f2[2], f2[3])
                var t_f2_out = mat_apply(m, f2[4], f2[5])
                var t_f0_in = mat_apply(m, f0[2], f0[3])
                line_pixels(
                    s,
                    t_f0_out[0],
                    t_f0_out[1],
                    t_f1_in[0],
                    t_f1_in[1],
                    outline_col,
                    sw,
                )
                line_pixels(
                    s,
                    t_f1_out[0],
                    t_f1_out[1],
                    t_f2_in[0],
                    t_f2_in[1],
                    outline_col,
                    sw,
                )
                line_pixels(
                    s,
                    t_f2_out[0],
                    t_f2_out[1],
                    t_f0_in[0],
                    t_f0_in[1],
                    outline_col,
                    sw,
                )
                _draw_fillet_arc_mapped(
                    s, m, scale, f0, r_local, outline_col, sw
                )
                _draw_fillet_arc_mapped(
                    s, m, scale, f1, r_local, outline_col, sw
                )
                _draw_fillet_arc_mapped(
                    s, m, scale, f2, r_local, outline_col, sw
                )

    def _sprite[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ) raises:
        if c.image not in self.images:
            return
        var p = mat_apply(m, c.geom[0], c.geom[1])
        var sf = pixel_scale(m, scale)
        var dw = max(Int(c.geom[2] * sf + 0.5), 1)
        var dh = max(Int(c.geom[3] * sf + 0.5), 1)
        # Bound by reference so the pixels stay in the cache rather than being
        # copied out of it once per draw.
        ref img = self.images[c.image]
        blit_sprite(
            s,
            img.pixels.unsafe_ptr(),
            img.width,
            img.height,
            Int(p[0]) - dw // 2,
            Int(p[1]) - dh // 2,
            dw,
            dh,
        )

    def _text[
        o: Origin[mut=True]
    ](
        mut self,
        s: Surface[o],
        c: DrawCommand,
        scale: Float64,
        m: Matrix[3, 3],
    ) raises:
        # Only the anchor is mapped — the layout itself happens in pixel space.
        # `frame.text` already skips recording when `text_color` is fully
        # transparent; text has no other visibility gate (fill is unrelated).
        var p = mat_apply(m, c.geom[0], c.geom[1])
        self.text.draw(s, c.text, p[0], p[1], c.style, pixel_scale(m, scale))

    def _letterbox[
        o: Origin[mut=True]
    ](mut self, s: Surface[o], c: DrawCommand):
        var W = s.width
        var H = s.height
        var cx0 = Int(c.geom[0])
        var cy0 = Int(c.geom[1])
        var cx1 = Int(c.geom[2])
        var cy1 = Int(c.geom[3])
        var col = c.style.fill_color
        if cy0 > 0:
            fill_pixels(s, 0, 0, W, cy0, col)
        if cy1 < H:
            fill_pixels(s, 0, cy1, W, H, col)
        if cx0 > 0:
            fill_pixels(s, 0, cy0, cx0, cy1, col)
        if cx1 < W:
            fill_pixels(s, cx1, cy0, W, cy1, col)
