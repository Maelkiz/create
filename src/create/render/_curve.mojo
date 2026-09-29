"""Stroke geometry for curves, shared by both replays.

A curve is flattened and stroked in *device* space at replay, not at record
time, so it stays smooth however far a camera zooms in. Both backends fill
the same quads — the CPU through `fill_quad`, the GPU as vertices — which is what keeps them in parity.
"""

from std.math import sqrt

from create.math.bezier import CubicBezier
from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D

from ._command import RenderCommand

comptime FLATTEN_TOLERANCE_PX = 0.25
"""How far, in device pixels, a flattened curve may stray from the true one:
well under the half-pixel that would move a pixel centre in or out."""

comptime MITER_LIMIT = 4.0
"""The furthest a mitred corner may reach, in half-thicknesses. A flattened
curve turns only slightly between segments, so the limit only bites at a
cusp, where the unclamped miter would shoot off towards infinity."""


def bezier_device_points(c: RenderCommand, m: Matrix[3, 3]) -> List[Point2D]:
    """`c`'s curve (`c` a `CMD_BEZIER`) mapped by `m` and flattened to
    device-space points.

    The control points are mapped rather than the flattened points: a
    Bézier's shape survives an affine map, so the curve is flattened at the
    size it will actually be drawn.
    """
    var p0 = mat_apply(m, c.geom[0], c.geom[1])
    var p1 = mat_apply(m, c.geom[2], c.geom[3])
    var p2 = mat_apply(m, c.geom[4], c.geom[5])
    var p3 = mat_apply(m, c.geom[6], c.geom[7])
    return CubicBezier(p0, p1, p2, p3).flatten(FLATTEN_TOLERANCE_PX)


def stroke_quads(points: List[Point2D], width: Float64) -> List[Point2D]:
    """The `width`-thick band along the polyline `points`, as quads: four
    corners each, in order around the quad's edge, quad after quad.

    Neighbouring quads meet on a mitred edge — both use the same two corners
    — so the band has no gap at a joint and no overlap either, and a
    translucent stroke composites once everywhere. The two ends are butt, as
    a line's are. Repeated points are skipped; a polyline of no length gives
    no quads.

    At a cusp the miter is clamped to `MITER_LIMIT`, which lets the two
    quads either side overlap slightly there.
    """
    var path = List[Point2D](capacity=len(points))
    for p in points:
        if len(path) == 0 or path[len(path) - 1] != p:
            path.append(p)
    var corners = List[Point2D]()
    if len(path) < 2 or width <= 0.0:
        return corners^

    var half = width / 2.0
    var segments = len(path) - 1
    var normals = List[Vector2D](capacity=segments)
    for i in range(segments):
        var d = path[i + 1] - path[i]
        normals.append(Vector2D(-d.y, d.x) / d.mag())

    # Each vertex's offset to the band's left edge; the right edge is its
    # negation. An interior vertex's offset lies along the bisector of its
    # two normals, long enough that both neighbouring edges stay `half` away.
    var offsets = List[Vector2D](capacity=len(path))
    offsets.append(normals[0] * half)
    for j in range(1, segments):
        var bisector = normals[j - 1] + normals[j]
        var length = bisector.mag()
        if length == 0.0:
            # The path doubles straight back: no bisector exists.
            offsets.append(normals[j] * half)
            continue
        bisector /= length
        var reach = half / bisector.dot(normals[j])
        offsets.append(bisector * min(reach, MITER_LIMIT * half))
    offsets.append(normals[segments - 1] * half)

    corners.reserve(4 * segments)
    for i in range(segments):
        corners.append(path[i] + offsets[i])
        corners.append(path[i + 1] + offsets[i + 1])
        corners.append(path[i + 1] - offsets[i + 1])
        corners.append(path[i] - offsets[i])
    return corners^
