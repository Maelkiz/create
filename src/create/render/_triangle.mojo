"""A triangle's fill and outline as pieces shared by both replays.

A triangle's outline is centred on its edges, so it reaches half its width
into the fill. Drawn as a fill with three edge bands over it, as it once
was, a translucent triangle composited twice under each band and three
times where two bands crossed at a corner, and a thick outline left a notch
at every outer corner. Here the outline is the band between an outer and an
inner edge, cut into convex pieces that meet without overlapping, and the
fill is what the inner edge encloses:

- **Sharp** (`corner_radius` 0): the outer edge is the triangle grown by
  half the band `h`, each corner mitred, or bevelled where the miter would
  reach past `MITER_LIMIT` half-widths, as a curve's corners are; the inner
  edge is the triangle shrunk by `h`, which is the triangle scaled about its
  incentre. One quad per edge, one triangle per bevel.
- **Rounded**: the triangle is its corner centres' triangle grown by the
  radius `r`, so the outer edge has arcs of radius `r + h` and the inner
  arcs of `r - h` about the same centres, at the same angles: one quad per
  arc segment and one per edge. Once the band is wider than the corners,
  the inner edge is the shrunk sharp triangle again, and each corner is a
  fan from its inner vertex.

Neighbouring pieces share the very points they meet at, so each pixel is
covered once: the CPU fills the pieces with `fill_quad` and the fill with
`fill_convex`, whose half-open rule composites a shared edge once, and the
GPU pushes them as vertices, as for sectors and polygons. Built in local
space and mapped per point, so a sheared rounded corner is the ellipse arc
it should be; `h` is the outline thickness in device pixels taken back to
local units.
"""

from std.math import atan2, cos, max, min, sin, sqrt, tau

from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D

from ._command import RenderCommand
from ._curve import MITER_LIMIT, stroke_quads
from ._fillet import triangle_corner_radius
from ._tessellate import _arc_segments
from ._transform import outline_thickness_px, pixel_scale


struct TrianglePieces(Movable):
    """A triangle's fill and outline in device space, ready to rasterise."""

    var fill: List[Point2D]
    """The fill as one convex polygon, in order round its edge; empty when
    the outline leaves no room for it."""
    var ring: List[Point2D]
    """The outline as convex quads, four corners each, in order around the
    quad's edge; a corner repeats where a piece is a triangle."""

    def __init__(out self):
        self.fill = List[Point2D]()
        self.ring = List[Point2D]()


def triangle_pieces(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64
) -> TrianglePieces:
    """`c`'s fill and outline (`c` a `CMD_TRIANGLE`) as device pieces,
    whichever of the two its style shows; the caller draws what is visible.
    Without an outline the fill is the whole (rounded) triangle."""
    var out = TrianglePieces()
    # Fixed-size and on the stack: this runs once per triangle drawn.
    var xs = Array[Float64, 3](fill=0.0)
    var ys = Array[Float64, 3](fill=0.0)
    for i in range(3):
        xs[i] = c.geom[2 * i]
        ys[i] = c.geom[2 * i + 1]
    var cross = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (ys[1] - ys[0]) * (
        xs[2] - xs[0]
    )
    if cross < 0.0:
        # Counter-clockwise from here on, so every outward normal turns the
        # same way; the triangle is the same set of points either way.
        var x1 = xs[1]
        var y1 = ys[1]
        xs[1] = xs[2]
        ys[1] = ys[2]
        xs[2] = x1
        ys[2] = y1
        cross = -cross
    var sf = pixel_scale(m, scale)
    var h = 0.0
    if c.style._outline_visible():
        h = Float64(outline_thickness_px(c.style, m, scale)) / (2.0 * sf)

    var lengths = Array[Float64, 3](fill=0.0)
    for i in range(3):
        var j = (i + 1) % 3
        lengths[i] = sqrt((xs[j] - xs[i]) ** 2 + (ys[j] - ys[i]) ** 2)
    var perimeter = lengths[0] + lengths[1] + lengths[2]
    if cross <= 1e-12 or perimeter <= 0.0:
        # No interior: nothing to fill, and the outline is the band along
        # the edges there are.
        if h > 0.0:
            var path = List[Point2D](capacity=4)
            for i in range(4):
                path.append(mat_apply(m, xs[i % 3], ys[i % 3]))
            out.ring = stroke_quads(path, 2.0 * h * sf)
        return out^

    # Edge `i` runs from corner `i` to `i + 1`, so corner `i` faces edge
    # `i + 1`, whose length weights it in the incentre.
    var inradius = cross / perimeter
    var ix = (
        lengths[1] * xs[0] + lengths[2] * xs[1] + lengths[0] * xs[2]
    ) / perimeter
    var iy = (
        lengths[1] * ys[0] + lengths[2] * ys[1] + lengths[0] * ys[2]
    ) / perimeter
    var r = min(
        triangle_corner_radius(
            Float64(c.style.corner_radius),
            xs[0],
            ys[0],
            xs[1],
            ys[1],
            xs[2],
            ys[2],
        ),
        inradius,
    )
    # Edge `i`'s outward normal.
    var nx = Array[Float64, 3](fill=0.0)
    var ny = Array[Float64, 3](fill=0.0)
    for i in range(3):
        var j = (i + 1) % 3
        nx[i] = (ys[j] - ys[i]) / lengths[i]
        ny[i] = -(xs[j] - xs[i]) / lengths[i]

    # The inner edge once it is sharp: the triangle shrunk by `h`, or the
    # incentre alone once the band fills it.
    var k = max((inradius - h) / inradius, 0.0)
    var sharp_inner = Array[Point2D, 3](fill=Point2D(0.0, 0.0))
    for i in range(3):
        sharp_inner[i] = mat_apply(
            m, ix + (xs[i] - ix) * k, iy + (ys[i] - iy) * k
        )

    if r > 0.0:
        # Corner `i`'s arc runs about its centre from the incoming edge's
        # normal round to the outgoing one's; `outer[i]` and `inner[i]` are
        # its points at the same angles, `inner` only while `h < r`.
        var ck = (inradius - r) / inradius
        var outer = List[List[Point2D]](capacity=3)
        var inner = List[List[Point2D]](capacity=3)
        for i in range(3):
            var kx = ix + (xs[i] - ix) * ck
            var ky = iy + (ys[i] - iy) * ck
            var prev = (i + 2) % 3
            var a0 = atan2(ny[prev], nx[prev])
            var a1 = atan2(ny[i], nx[i])
            if a1 < a0:
                a1 += tau
            var n = _arc_segments((r + h) * sf, a1 - a0)
            var o = List[Point2D](capacity=n + 1)
            var q = List[Point2D](capacity=n + 1)
            for step in range(n + 1):
                var a = a0 + (a1 - a0) * Float64(step) / Float64(n)
                o.append(
                    mat_apply(m, kx + (r + h) * cos(a), ky + (r + h) * sin(a))
                )
                if h > 0.0 and h < r:
                    q.append(
                        mat_apply(
                            m, kx + (r - h) * cos(a), ky + (r - h) * sin(a)
                        )
                    )
            outer.append(o^)
            inner.append(q^)
        if h == 0.0:
            for i in range(3):
                for p in outer[i]:
                    out.fill.append(p)
            return out^
        for i in range(3):
            var j = (i + 1) % 3
            var last = len(outer[i]) - 1
            if h < r:
                for step in range(last):
                    _quad(
                        out.ring,
                        outer[i][step],
                        outer[i][step + 1],
                        inner[i][step + 1],
                        inner[i][step],
                    )
                _quad(
                    out.ring,
                    outer[i][last],
                    outer[j][0],
                    inner[j][0],
                    inner[i][last],
                )
            else:
                for step in range(last):
                    _quad(
                        out.ring,
                        outer[i][step],
                        outer[i][step + 1],
                        sharp_inner[i],
                        sharp_inner[i],
                    )
                _quad(
                    out.ring,
                    outer[i][last],
                    outer[j][0],
                    sharp_inner[j],
                    sharp_inner[i],
                )
        if h < r:
            for i in range(3):
                for p in inner[i]:
                    out.fill.append(p)
        elif k > 0.0:
            for p in sharp_inner:
                out.fill.append(p)
        return out^

    if h == 0.0:
        for i in range(3):
            out.fill.append(mat_apply(m, xs[i], ys[i]))
        return out^
    # Sharp: where each corner's band leaves along its outgoing edge and
    # arrives along its incoming one — one miter point, or a bevel's two.
    var leaves = Array[Point2D, 3](fill=Point2D(0.0, 0.0))
    var arrives = Array[Point2D, 3](fill=Point2D(0.0, 0.0))
    var bevelled = Array[Bool, 3](fill=False)
    for i in range(3):
        var reach = sqrt((xs[i] - ix) ** 2 + (ys[i] - iy) ** 2) / inradius
        if reach <= MITER_LIMIT:
            var g = (inradius + h) / inradius
            var miter = mat_apply(
                m, ix + (xs[i] - ix) * g, iy + (ys[i] - iy) * g
            )
            leaves[i] = miter
            arrives[i] = miter
        else:
            var prev = (i + 2) % 3
            leaves[i] = mat_apply(m, xs[i] + nx[i] * h, ys[i] + ny[i] * h)
            arrives[i] = mat_apply(
                m, xs[i] + nx[prev] * h, ys[i] + ny[prev] * h
            )
            bevelled[i] = True
    for i in range(3):
        var j = (i + 1) % 3
        _quad(out.ring, leaves[i], arrives[j], sharp_inner[j], sharp_inner[i])
        if bevelled[i]:
            _quad(
                out.ring, arrives[i], leaves[i], sharp_inner[i], sharp_inner[i]
            )
    out.ring.reserve(24)
    if k > 0.0:
        for p in sharp_inner:
            out.fill.append(p)
    return out^


def _quad(
    mut corners: List[Point2D], a: Point2D, b: Point2D, c: Point2D, d: Point2D
):
    corners.append(a)
    corners.append(b)
    corners.append(c)
    corners.append(d)
