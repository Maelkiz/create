"""Stroke geometry for curves, shared by both replays.

A curve is flattened and stroked in *device* space at replay, not at record
time, so it stays smooth however far a camera zooms in. Both backends fill
the same quads — the CPU through `fill_quad`, the GPU as vertices — which is what keeps them in parity.

A blurred curve shadow is a mask rasterised from those same quads and blurred
(`bezier_shadow_mask`), which both backends composite; `quads_shadow_mask`
builds one from any device quads, which is how sectors and polygons cast theirs too.
Unlike a sprite's, it is not cached: a curve has no stable id to key it by,
so every blurred curve shadow costs one blur per frame.
"""

from std.math import ceil, floor, sqrt

from create.math.bezier import Bezier
from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D

from ._blur import BlurredMask, blur_alpha
from ._command import RenderCommand
from ._raster import fill_quad
from ._transform import outline_thickness_px
from .color import Color
from .surface import MemorySurface

comptime FLATTEN_TOLERANCE_PX = 0.25
"""How far, in device pixels, a flattened curve may stray from the true one:
well under the half-pixel that would move a pixel centre in or out."""

comptime MITER_LIMIT = 4.0
"""The furthest a mitred corner may reach, in half-thicknesses. A flattened
curve turns only slightly between segments, so the limit only bites at a
cusp, where the unclamped miter would shoot off towards infinity."""


def bezier_device_points(c: RenderCommand, m: Matrix[3, 3]) -> List[Point2D]:
    """`c`'s chain of curves (`c` a `CMD_BEZIER`) mapped by `m` and flattened
    to one polyline of device-space points, the point where one curve meets
    the next appearing once.

    The control points are mapped rather than the flattened points: a
    Bézier's shape survives an affine map, so each curve is flattened at the
    size it will actually be drawn.
    """
    var mapped = List[Point2D](capacity=len(c.points))
    for p in c.points:
        mapped.append(mat_apply(m, p.x, p.y))
    var points = List[Point2D]()
    for i in range(0, len(mapped) - 3, 3):
        var part = Bezier(
            mapped[i], mapped[i + 1], mapped[i + 2], mapped[i + 3]
        ).flatten(FLATTEN_TOLERANCE_PX)
        var first = 0 if len(points) == 0 else 1
        for j in range(first, len(part)):
            points.append(part[j])
    return points^


def stroke_quads(points: List[Point2D], width: Float64) -> List[Point2D]:
    """The `width`-thick band along the polyline `points`, as quads: four
    corners each, in order around the quad's edge, quad after quad.

    Neighbouring quads meet on a mitred edge — both use the same two corners
    — so the band has no gap at a joint and no overlap either, and a
    translucent stroke composites once everywhere. The two ends are butt, as
    a line's are. A polyline that ends where it starts, around at least
    three distinct points, is a ring instead: it has no ends, and its last
    quad meets its first on a mitred edge like any other joint. Repeated
    points are skipped; a polyline of no length gives no quads.

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
    var closed = len(path) >= 4 and path[0] == path[len(path) - 1]
    if closed:
        # The repeat of the first point; the ring wraps round to it instead.
        _ = path.pop()

    var half = width / 2.0
    var n = len(path)
    var segments = n if closed else n - 1
    var normals = List[Vector2D](capacity=segments)
    for i in range(segments):
        var d = path[(i + 1) % n] - path[i]
        normals.append(Vector2D(-d.y, d.x) / d.mag())

    # Each vertex's offset to the band's left edge; the right edge is its
    # negation. A joint's offset lies along the bisector of its two
    # normals, long enough that both neighbouring edges stay `half` away;
    # an open end's is its one segment's normal.
    var offsets = List[Vector2D](capacity=n)
    for j in range(n):
        if not closed and j == 0:
            offsets.append(normals[0] * half)
        elif not closed and j == n - 1:
            offsets.append(normals[segments - 1] * half)
        else:
            offsets.append(_miter(normals[(j - 1 + n) % n], normals[j], half))

    corners.reserve(4 * segments)
    for i in range(segments):
        var k = (i + 1) % n
        corners.append(path[i] + offsets[i])
        corners.append(path[k] + offsets[k])
        corners.append(path[k] - offsets[k])
        corners.append(path[i] - offsets[i])
    return corners^


def _miter(before: Vector2D, after: Vector2D, half: Float64) -> Vector2D:
    """The offset to the left edge at a joint between segments with unit
    normals `before` and `after`, clamped to `MITER_LIMIT` half-widths."""
    var bisector = before + after
    var length = bisector.mag()
    if length == 0.0:
        # The path doubles straight back: no bisector exists.
        return after * half
    bisector /= length
    var reach = half / bisector.dot(after)
    return bisector * min(reach, MITER_LIMIT * half)


struct PlacedMask(Movable):
    """A blurred mask and where its top-left pixel lands on the device."""

    var mask: BlurredMask
    var x: Int
    var y: Int

    def __init__(out self, var mask: BlurredMask, x: Int, y: Int):
        self.mask = mask^
        self.x = x
        self.y = y


def bezier_shadow_mask(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64, blur: Int
) -> PlacedMask:
    """The stroke of `c` (a `CMD_BEZIER` shadow command) mapped by `m`,
    rasterised into an alpha mask and blurred by `blur` device pixels.

    The quads are the ones the stroke itself fills. A curve with no visible
    stroke gives an empty mask.
    """
    var corners = List[Point2D]()
    if c.style._outline_visible():
        corners = stroke_quads(
            bezier_device_points(c, m),
            Float64(outline_thickness_px(c.style, m, scale)),
        )
    return quads_shadow_mask(corners, blur)


def quads_shadow_mask(corners: List[Point2D], blur: Int) -> PlacedMask:
    """Device quads (four corners each, as `fill_quad` takes them)
    rasterised into an alpha mask and blurred by `blur` device pixels.

    The quads are shifted by a whole number of pixels onto the mask, so
    every pixel centre falls where it would on the device and the mask holds
    the same pixels the quads paint there. No quads give an empty mask.
    """
    if len(corners) == 0:
        return PlacedMask(BlurredMask(List[UInt8](), 0, 0, 0), 0, 0)
    var lo = corners[0]
    var hi = corners[0]
    for p in corners:
        lo = Point2D(min(lo.x, p.x), min(lo.y, p.y))
        hi = Point2D(max(hi.x, p.x), max(hi.y, p.y))
    var x0 = Int(floor(lo.x))
    var y0 = Int(floor(lo.y))
    var width = Int(ceil(hi.x)) - x0 + 1
    var height = Int(ceil(hi.y)) - y0 + 1

    # Filled white on a scratch surface, so the mask is the same pixels the
    # hard quads paint; only its alpha is kept.
    var scratch = MemorySurface(width, height)
    var s = scratch.surface()
    for q in range(0, len(corners), 4):
        var qx: Array[Float64, 4] = [
            corners[q].x - Float64(x0),
            corners[q + 1].x - Float64(x0),
            corners[q + 2].x - Float64(x0),
            corners[q + 3].x - Float64(x0),
        ]
        var qy: Array[Float64, 4] = [
            corners[q].y - Float64(y0),
            corners[q + 1].y - Float64(y0),
            corners[q + 2].y - Float64(y0),
            corners[q + 3].y - Float64(y0),
        ]
        fill_quad(s, qx, qy, Color.WHITE)
    var alpha = List[UInt8](length=width * height, fill=0)
    for i in range(width * height):
        alpha[i] = scratch.data[i * 4 + 3]
    var mask = blur_alpha(alpha, width, height, Float64(blur) / 2.0)
    var pad = mask.pad
    return PlacedMask(mask^, x0 - pad, y0 - pad)
