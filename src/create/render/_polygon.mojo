"""Fill and outline geometry for polygons, shared by both replays.

A polygon is tiled at replay into convex quads, like a sector, and both
backends fill those same quads — the CPU through `fill_quad`, the GPU as
vertices — which keeps them in parity. Neighbouring quads share their
corners exactly, so under `fill_quad`'s half-open rule a translucent
polygon composites once everywhere, fill and outline together, however it
folds over itself.

The tiling cuts the plane into horizontal slabs at every y where an edge
ends or two edges cross. Inside a slab no edges cross, so they keep one
left-to-right order, and each stretch between two neighbours is one
trapezoid whose winding is counted walking in from the left. The fill rule
is nonzero.

The outline is an inset band: what lies inside and within
`outline_thickness` of an edge. Points within `d` of the edges make a
*band*: a rectangle of half-width `d` along every edge and a disc at every
vertex, each wound once, so a point is in the band where its count is not
zero. The band pieces are cut into the slabs with the edges, which keeps
every trapezoid inside or outside each piece whole.

A shadow's spread offsets the whole polygon first (`geom[0]`, zero for a
render call): outwards it is the polygon or its band, inwards the polygon
without it. The fill is the polygon offset by the outline's width less, so
the outline is an inset band of the offset polygon.
"""

from std.math import cos, max, min, sin, sqrt, tau

from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D

from ._command import RenderCommand
from ._curve import PlacedMask, quads_shadow_mask
from ._tessellate import circle_segments
from ._transform import outline_thickness_px, pixel_scale

comptime _NOTHING = 0
comptime _FILL = 1
comptime _OUTLINE = 2


struct PolygonQuads(Movable):
    """A polygon's device-space tiling: four corners per quad, in order
    around the quad's edge, quad after quad. `fill` is painted in the fill
    colour, `outline` in the outline colour; the two never overlap."""

    var fill: List[Point2D]
    var outline: List[Point2D]

    def __init__(out self):
        self.fill = List[Point2D]()
        self.outline = List[Point2D]()


@fieldwise_init
struct _Edge(Copyable, ImplicitlyCopyable, Movable):
    """One non-level edge of the polygon or a band piece, stored from its
    lower end up. `sign` is +1 if the piece runs up along it, -1 if down;
    `layer` is 0 for the polygon, else the band it belongs to, from 1."""

    var x0: Float64
    var y0: Float64
    var x1: Float64
    var y1: Float64
    var sign: Int
    var layer: Int

    def x_at(self, y: Float64) -> Float64:
        """The edge's x at `y`, from its lower end, so every slab that asks
        at the same `y` gets the same answer."""
        if y <= self.y0:
            return self.x0
        if y >= self.y1:
            return self.x1
        return self.x0 + (self.x1 - self.x0) * (y - self.y0) / (
            self.y1 - self.y0
        )


def polygon_quads(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64
) -> PolygonQuads:
    """`c` (a `CMD_POLYGON`) mapped by `m` and tiled into fill and outline
    quads.

    The tiling is built in local space and mapped per corner, so a
    non-uniform transform gives the sheared polygon it should. With no
    visible outline everything is fill. With an outline too wide to leave
    any fill, the whole polygon is one colour, as a sector's is: the fill's
    if the fill is visible, else the outline's. `geom[0]` offsets the
    polygon by that many local units first, outwards if positive.
    """
    var out = PolygonQuads()
    var vertices = c.points.copy()
    # Fewer than three encloses nothing; not even a shadow grows from it.
    if len(vertices) < 3:
        return out^
    var grow = c.geom[0]
    var sf = pixel_scale(m, scale)
    var t = 0.0
    if c.style._outline_visible():
        t = Float64(outline_thickness_px(c.style, m, scale)) / sf

    # The polygon's outer edge is offset by `grow`, the fill's by `grow - t`;
    # each needs the band of that radius, unless the offset is zero.
    var outer = grow
    var inner = grow - t
    var edges = List[_Edge]()
    _add_loop(edges, vertices, 0)
    var outer_layer = 0
    var inner_layer = 0
    if outer != 0.0:
        outer_layer = 1
        _add_band(edges, vertices, abs(outer), sf, outer_layer)
    if t > 0.0 and inner != 0.0:
        inner_layer = outer_layer + 1
        _add_band(edges, vertices, abs(inner), sf, inner_layer)

    var ys = _slab_boundaries(edges)
    var active = List[_Edge]()
    var middles = List[Float64]()
    for k in range(len(ys) - 1):
        var y_lo = ys[k]
        var y_hi = ys[k + 1]
        if y_hi <= y_lo:
            continue
        var y_mid = 0.5 * (y_lo + y_hi)
        active.clear()
        middles.clear()
        for e in edges:
            if e.y0 <= y_lo and e.y1 >= y_hi:
                active.append(e)
                middles.append(e.x_at(y_mid))
        _sort_by(active, middles)

        # Walk in from the left, where every count is zero. The stretch
        # after edge `i` runs to edge `i + 1`; runs of one class merge.
        var counts = Array[Int, 3](fill=0)
        var run_class = _NOTHING
        var run_start = 0
        for i in range(len(active)):
            counts[active[i].layer] -= active[i].sign
            var cls = _classify(
                counts, outer, inner, outer_layer, inner_layer, t > 0.0
            )
            if cls == run_class:
                continue
            if run_class != _NOTHING:
                _emit(
                    out, run_class, active[run_start], active[i], y_lo, y_hi, m
                )
            run_class = cls
            run_start = i

    if t > 0.0 and len(out.fill) == 0 and c.style._fill_visible():
        out.fill = out.outline^
        out.outline = List[Point2D]()
    return out^


def polygon_shadow_mask(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64, blur: Int
) -> PlacedMask:
    """The shadow command `c` (a `CMD_POLYGON`, one colour) mapped by `m`,
    rasterised into an alpha mask and blurred by `blur` device pixels."""
    var q = polygon_quads(c, m, scale)
    # Only what the command paints: an outline-only ring leaves its middle.
    var corners = List[Point2D]()
    if c.style._fill_visible():
        for p in q.fill:
            corners.append(p)
    if c.style._outline_visible():
        for p in q.outline:
            corners.append(p)
    return quads_shadow_mask(corners, blur)


def _classify(
    counts: Array[Int, 3],
    outer: Float64,
    inner: Float64,
    outer_layer: Int,
    inner_layer: Int,
    outlined: Bool,
) -> Int:
    """Whether a stretch with these winding counts is fill, outline or
    neither: inside the polygon offset by `outer` and, if outlined, inside
    or outside it offset by `inner`."""
    var inside = counts[0] != 0
    if not _offset_holds(inside, counts[outer_layer] != 0, outer):
        return _NOTHING
    if not outlined:
        return _FILL
    if _offset_holds(inside, counts[inner_layer] != 0, inner):
        return _FILL
    return _OUTLINE


def _offset_holds(inside: Bool, banded: Bool, offset: Float64) -> Bool:
    """Whether a point is inside the polygon offset by `offset`, given
    whether it is inside the polygon and in the band of that radius."""
    if offset > 0.0:
        return inside or banded
    if offset < 0.0:
        return inside and not banded
    return inside


def _emit(
    mut out: PolygonQuads,
    cls: Int,
    left: _Edge,
    right: _Edge,
    y_lo: Float64,
    y_hi: Float64,
    m: Matrix[3, 3],
):
    """The trapezoid between `left` and `right` across the slab, mapped by
    `m`, counter-clockwise from its lower left."""
    var a = Point2D(mat_apply(m, left.x_at(y_lo), y_lo))
    var b = Point2D(mat_apply(m, right.x_at(y_lo), y_lo))
    var c = Point2D(mat_apply(m, right.x_at(y_hi), y_hi))
    var d = Point2D(mat_apply(m, left.x_at(y_hi), y_hi))
    if cls == _FILL:
        _append_quad(out.fill, a, b, c, d)
    else:
        _append_quad(out.outline, a, b, c, d)


def _add_loop(mut edges: List[_Edge], points: List[Point2D], layer: Int):
    """Every edge of the closed loop through `points`, level ones left out:
    they never cross a slab, so they never change a count."""
    var n = len(points)
    for i in range(n):
        var a = points[i]
        var b = points[(i + 1) % n]
        if a.y < b.y:
            edges.append(_Edge(a.x, a.y, b.x, b.y, 1, layer))
        elif a.y > b.y:
            edges.append(_Edge(b.x, b.y, a.x, a.y, -1, layer))


def _add_band(
    mut edges: List[_Edge],
    vertices: List[Point2D],
    d: Float64,
    sf: Float64,
    layer: Int,
):
    """The pieces of the band within `d` of the polygon's edges, each wound
    counter-clockwise so the band's count is how many cover a point."""
    var n = len(vertices)
    var segments = circle_segments(d * sf)
    var disc = List[Point2D](capacity=segments)
    for i in range(n):
        var a = vertices[i]
        var b = vertices[(i + 1) % n]
        disc.clear()
        for k in range(segments):
            var angle = tau * Float64(k) / Float64(segments)
            disc.append(Point2D(a.x + d * cos(angle), a.y + d * sin(angle)))
        _add_loop(edges, disc, layer)
        var dx = b.x - a.x
        var dy = b.y - a.y
        var length = sqrt(dx * dx + dy * dy)
        if length == 0.0:
            continue
        # The normal to the right of a → b, so the rectangle below runs
        # counter-clockwise.
        var nx = dy / length * d
        var ny = -dx / length * d
        var rectangle: List[Point2D] = [
            Point2D(a.x + nx, a.y + ny),
            Point2D(b.x + nx, b.y + ny),
            Point2D(b.x - nx, b.y - ny),
            Point2D(a.x - nx, a.y - ny),
        ]
        _add_loop(edges, rectangle, layer)


def _slab_boundaries(edges: List[_Edge]) -> List[Float64]:
    """Every y where an edge ends or two edges cross, in order: between two
    neighbours, no edges cross."""
    var ys = List[Float64]()
    for e in edges:
        ys.append(e.y0)
        ys.append(e.y1)
    for i in range(len(edges)):
        var p = edges[i]
        for j in range(i + 1, len(edges)):
            var q = edges[j]
            var y_lo = max(p.y0, q.y0)
            var y_hi = min(p.y1, q.y1)
            if y_hi <= y_lo:
                continue
            # Where their x difference changes sign across the shared span.
            var lo = p.x_at(y_lo) - q.x_at(y_lo)
            var hi = p.x_at(y_hi) - q.x_at(y_hi)
            if (lo < 0.0 and hi > 0.0) or (lo > 0.0 and hi < 0.0):
                ys.append(y_lo + (y_hi - y_lo) * lo / (lo - hi))
    sort(ys)
    var unique = List[Float64](capacity=len(ys))
    for y in ys:
        if len(unique) == 0 or y > unique[len(unique) - 1]:
            unique.append(y)
    return unique^


def _sort_by(mut edges: List[_Edge], mut keys: List[Float64]):
    """Sort `edges` by `keys`, in step. Insertion: a slab holds few edges,
    and neighbouring slabs mostly agree."""
    for i in range(1, len(keys)):
        var key = keys[i]
        var edge = edges[i]
        var j = i
        while j > 0 and keys[j - 1] > key:
            keys[j] = keys[j - 1]
            edges[j] = edges[j - 1]
            j -= 1
        keys[j] = key
        edges[j] = edge


def _append_quad(
    mut corners: List[Point2D], a: Point2D, b: Point2D, c: Point2D, d: Point2D
):
    corners.append(a)
    corners.append(b)
    corners.append(c)
    corners.append(d)
