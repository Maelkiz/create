"""Fill and outline geometry for sectors, shared by both replays.

A sector is tiled in *device* space at replay into convex quads — a fan
triangle is a quad with its first corner repeated — and both backends fill
those same quads, the CPU through `fill_quad` and the GPU as vertices,
which is what keeps them in parity. Neighbouring quads share their corners
exactly, so under `fill_quad`'s half-open rule a translucent sector
composites once everywhere, fill and outline together.

The outline is an inset band, as a circle's is: the fill stops where the
outline starts, `outline_thickness` inside every edge. The tiling walks the
sweep in thin wedges around the tip. Within each, the fill runs from the
eroded edge out to `r` less the outline, the outline's arc band from there
out to `r`, and its tip side from the tip in to the eroded edge.
"""

from std.math import asin, cos, max, min, pi, sin, tau

from create.math.geometry import _normalized_sweep
from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D

from ._command import RenderCommand
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
    if the fill is visible, else the outline's.
    """
    var out = SectorQuads()
    var cx = c.geom[0]
    var cy = c.geom[1]
    var r = c.geom[2]
    var sweep = _normalized_sweep(c.geom[3], c.geom[4])
    var start = sweep[0]
    var theta = sweep[1]
    if r <= 0.0 or theta <= 0.0:
        return out^
    var full = theta >= tau
    var sf = pixel_scale(m, scale)
    var t = 0.0
    if c.style._outline_visible():
        t = min(Float64(outline_thickness_px(c.style, m, scale)) / sf, r)
    var fill_r = r - t

    # Sample angles: an even split fine enough for the arc, plus every
    # angle where the eroded edge changes shape, so each wedge sees that
    # edge as one straight piece or one chord of the round reflex tip.
    var angles = List[Float64]()
    var n = _arc_segments(r * sf, theta)
    for i in range(n + 1):
        angles.append(start + theta * Float64(i) / Float64(n))
    if t > 0.0 and not full:
        var beta = pi / 2.0
        if fill_r > t:
            beta = asin(t / fill_r)
        for offset in [beta, pi / 2.0, theta / 2.0]:
            for a in [offset, theta - offset]:
                if a > 0.0 and a < theta:
                    angles.append(start + a)
    sort(angles)

    var tip = Point2D(mat_apply(m, cx, cy))
    var inner = List[Point2D]()
    var middle = List[Point2D]()
    var outer = List[Point2D]()
    var capped = List[Bool]()
    for i in range(len(angles)):
        if i > 0 and angles[i] <= angles[i - 1]:
            continue
        var phi = angles[i]
        var dx = cos(phi)
        var dy = sin(phi)
        var rho = _eroded_distance(phi - start, theta, t, full)
        # The fill narrows to nothing exactly at a sample angle (`beta`);
        # snap the rounding there so no sliver reaches back along the edge.
        if rho >= fill_r * (1.0 - 1e-9):
            rho = fill_r
        inner.append(Point2D(mat_apply(m, cx + dx * rho, cy + dy * rho)))
        middle.append(Point2D(mat_apply(m, cx + dx * fill_r, cy + dy * fill_r)))
        outer.append(Point2D(mat_apply(m, cx + dx * r, cy + dy * r)))
        capped.append(rho >= fill_r)

    for i in range(len(inner) - 1):
        var j = i + 1
        if fill_r > 0.0 and not (capped[i] and capped[j]):
            _append_quad(out.fill, inner[i], middle[i], middle[j], inner[j])
        if t > 0.0:
            if fill_r > 0.0 and not full:
                _append_quad(out.outline, tip, inner[i], inner[j], tip)
            _append_quad(out.outline, middle[i], outer[i], outer[j], middle[j])

    if t > 0.0 and len(out.fill) == 0 and c.style._fill_visible():
        out.fill = out.outline^
        out.outline = List[Point2D]()
    return out^


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


def _append_quad(
    mut corners: List[Point2D], a: Point2D, b: Point2D, c: Point2D, d: Point2D
):
    corners.append(a)
    corners.append(b)
    corners.append(c)
    corners.append(d)
