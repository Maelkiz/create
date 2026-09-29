"""Fill and outline geometry for sectors, shared by both replays.

A sector is tiled in *device* space at replay into convex quads — a fan
triangle is a quad with its first corner repeated — and both backends fill
those same quads, the CPU through `fill_quad` and the GPU as vertices,
which is what keeps them in parity. Neighbouring quads share their corners
exactly, so under `fill_quad`'s half-open rule a translucent sector
composites once everywhere, fill and outline together.

The outline is an inset band, as a circle's is: the fill stops where the
outline starts, `outline_thickness` inside every edge. The tiling walks the
sweep in thin wedges around the tip, and along each wedge's rays the sector
is one stretch of distances from the tip: the fill is the stretch of the
sector eroded by the outline, the outline what lies either side of it.

A shadow's spread offsets the whole sector first (`geom[5]`, zero for a
render call). Growing it keeps it one stretch per ray — a sector grown by a
disc is still star-shaped about its tip — but reaches into the missing
wedge too, round the tip and the arc's ends, so the walk goes all the way
round.
"""

from std.math import asin, atan, atan2, cos, max, min, pi, sin, sqrt, tau

from create.math.geometry import _normalized_sweep
from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D

from ._command import RenderCommand
from ._curve import PlacedMask, quads_shadow_mask
from ._tessellate import _arc_segments
from ._transform import outline_thickness_px, pixel_scale


struct SectorQuads(Movable):
    """A sector's device-space tiling: four corners per quad, in order
    around the quad's edge, quad after quad. `fill` is painted in the fill
    colour, `outline` in the outline colour; the two never overlap."""

    var fill: List[Point2D]
    var outline: List[Point2D]

    def __init__(out self):
        self.fill = List[Point2D]()
        self.outline = List[Point2D]()


def sector_quads(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64
) -> SectorQuads:
    """`c` (a `CMD_SECTOR`) mapped by `m` and tiled into fill and outline
    quads.

    The tiling is built in local space and mapped per corner, so a
    non-uniform transform gives the elliptical sector it should. With no
    visible outline everything is fill. With an outline too wide to leave
    any fill, the whole sector is one colour, as a circle's is: the fill's
    if the fill is visible, else the outline's. `geom[5]` offsets the sector
    by that many local units first, outwards if positive.
    """
    var out = SectorQuads()
    var cx = c.geom[0]
    var cy = c.geom[1]
    var r = c.geom[2]
    var grow = c.geom[5]
    var sweep = _normalized_sweep(c.geom[3], c.geom[4])
    var start = sweep[0]
    var theta = sweep[1]
    if r <= 0.0 or theta <= 0.0 or r + grow <= 0.0:
        return out^
    var full = theta >= tau
    var sf = pixel_scale(m, scale)
    var t = 0.0
    if c.style._outline_visible():
        t = min(Float64(outline_thickness_px(c.style, m, scale)) / sf, r + grow)

    # Sample angles into the sweep: an even split fine enough for the arc,
    # plus every angle where either boundary changes shape, so each wedge
    # sees a boundary as one straight piece or one chord of a round one. A
    # grown sector reaches round into the missing wedge, so the walk does.
    var span = tau if grow > 0.0 else theta
    var n = _arc_segments((r + max(grow, 0.0)) * sf, span)
    var alphas = List[Float64]()
    for i in range(n + 1):
        alphas.append(span * Float64(i) / Float64(n))
    if not full:
        # The far edge, which an even split of a whole turn can straddle.
        alphas.append(theta)
        _breakpoints(alphas, theta, r, grow, sf)
        if t > 0.0:
            _breakpoints(alphas, theta, r, grow - t, sf)
    sort(alphas)

    # Along each ray, from the tip: outline to `inner`, fill to `middle`,
    # outline to `outer`. Any stretch may be empty.
    var tip = List[Point2D]()
    var inner = List[Point2D]()
    var middle = List[Point2D]()
    var outer = List[Point2D]()
    var lengths = List[Tuple[Float64, Float64, Float64]]()
    for i in range(len(alphas)):
        var alpha = alphas[i]
        if i > 0 and alpha <= alphas[i - 1]:
            continue
        var shape = _offset_extent(alpha, theta, full, r, grow)
        var a = shape[0]
        var b = max(shape[1], a)
        var cc = a
        var d = b
        if t > 0.0:
            var hole = _offset_extent(alpha, theta, full, r, grow - t)
            d = min(max(hole[1], a), b)
            cc = min(max(hole[0], a), d)
        var dx = cos(start + alpha)
        var dy = sin(start + alpha)
        tip.append(Point2D(mat_apply(m, cx + dx * a, cy + dy * a)))
        inner.append(Point2D(mat_apply(m, cx + dx * cc, cy + dy * cc)))
        middle.append(Point2D(mat_apply(m, cx + dx * d, cy + dy * d)))
        outer.append(Point2D(mat_apply(m, cx + dx * b, cy + dy * b)))
        lengths.append((cc - a, d - cc, b - d))

    for i in range(len(inner) - 1):
        var j = i + 1
        if lengths[i][1] > 0.0 or lengths[j][1] > 0.0:
            _append_quad(out.fill, inner[i], middle[i], middle[j], inner[j])
        if lengths[i][0] > 0.0 or lengths[j][0] > 0.0:
            _append_quad(out.outline, tip[i], inner[i], inner[j], tip[j])
        if lengths[i][2] > 0.0 or lengths[j][2] > 0.0:
            _append_quad(out.outline, middle[i], outer[i], outer[j], middle[j])

    if t > 0.0 and len(out.fill) == 0 and c.style._fill_visible():
        out.fill = out.outline^
        out.outline = List[Point2D]()
    return out^


def sector_shadow_mask(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64, blur: Int
) -> PlacedMask:
    """The shadow command `c` (a `CMD_SECTOR`, one colour) mapped by `m`,
    rasterised into an alpha mask and blurred by `blur` device pixels."""
    var q = sector_quads(c, m, scale)
    # Only what the command paints: an outline-only ring leaves its middle.
    var corners = List[Point2D]()
    if c.style._fill_visible():
        for p in q.fill:
            corners.append(p)
    if c.style._outline_visible():
        for p in q.outline:
            corners.append(p)
    return quads_shadow_mask(corners, blur)


def _offset_extent(
    alpha: Float64, theta: Float64, full: Bool, r: Float64, offset: Float64
) -> Tuple[Float64, Float64]:
    """The stretch of the ray at `alpha` into a sweep of `theta` that the
    sector offset by `offset` covers, as distances from the tip. Empty
    stretches come back with both ends equal, where the stretch would close
    up, so the caller's quads shrink to nothing without jumping."""
    if offset >= 0.0:
        if full or alpha <= theta:
            return (0.0, r + offset)
        return (
            0.0,
            max(
                _capsule_distance(alpha - theta, r, offset),
                _capsule_distance(tau - alpha, r, offset),
            ),
        )
    var e = -offset
    var hi = r - e
    if not full and alpha > theta:
        return (hi, hi)
    var lo = _eroded_distance(alpha, theta, e, full)
    # The eroded sector narrows to nothing exactly at a sample angle; snap
    # the rounding there so no sliver reaches back along the edge.
    if lo >= hi * (1.0 - 1e-9):
        lo = hi
    return (lo, hi)


def _breakpoints(
    mut alphas: List[Float64],
    theta: Float64,
    r: Float64,
    offset: Float64,
    sf: Float64,
):
    """Append the angles where the sector offset by `offset` changes shape
    along its boundary, measured from both straight edges."""
    if offset < 0.0:
        var e = -offset
        if r - e <= 0.0:
            return
        var beta = pi / 2.0
        if r - e > e:
            beta = asin(e / (r - e))
        for off in [beta, pi / 2.0, theta / 2.0]:
            for a in [off, theta - off]:
                if a > 0.0 and a < theta:
                    alphas.append(a)
    elif offset > 0.0:
        # Into the missing wedge: where the round end of an edge's band meets
        # its straight side, where the side meets the round tip, and the
        # wedge's middle, where the two edges' bands swap which reaches
        # further. The round end is centred off the tip, so it is walked by
        # its own angle.
        var gap = tau - theta
        var ends = _arc_segments(offset * sf, pi / 2.0)
        var offs = List[Float64]()
        offs.append(atan(offset / r))
        offs.append(pi / 2.0)
        offs.append(gap / 2.0)
        for k in range(1, ends):
            var psi = -pi / 2.0 * Float64(k) / Float64(ends)
            offs.append(atan2(-offset * sin(psi), r + offset * cos(psi)))
        for off in offs:
            if off > 0.0 and off < gap:
                alphas.append(theta + off)
                alphas.append(tau - off)


def _eroded_distance(
    alpha: Float64, theta: Float64, t: Float64, full: Bool
) -> Float64:
    """How far from the tip, along the direction `alpha` into a sweep of
    `theta`, a point first lies `t` or more from both straight edges.

    Within a quarter turn of an edge the nearest point of that edge is
    across from it, so the distance is `t / sin`; past that it is the tip,
    so `t`. A full turn has no straight edges.
    """
    if full or t <= 0.0:
        return 0.0
    return max(_edge_distance(alpha, t), _edge_distance(theta - alpha, t))


def _edge_distance(alpha: Float64, t: Float64) -> Float64:
    if alpha >= pi / 2.0:
        return t
    var s = sin(alpha)
    if s <= 0.0:
        return Float64.MAX
    return t / s


def _capsule_distance(beta: Float64, r: Float64, g: Float64) -> Float64:
    """How far from the tip the ray `beta` outside a straight edge of
    length `r` leaves that edge grown by `g`: a band of half-width `g`,
    round at both ends."""
    if beta >= pi / 2.0:
        return g
    var s = sin(beta)
    var co = cos(beta)
    if r * s <= g * co:
        # Past the far end of the side: the round end at the arc's end.
        return r * co + sqrt(max(g * g - r * r * s * s, 0.0))
    return g / s


def _append_quad(
    mut corners: List[Point2D], a: Point2D, b: Point2D, c: Point2D, d: Point2D
):
    corners.append(a)
    corners.append(b)
    corners.append(c)
    corners.append(d)
