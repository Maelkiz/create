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

The edges are cut where others cross them into the *rim*, pieces with the
outside along one side, and the *seams*, pieces running through the inside
(a pentagram's inner pentagon). The outline is an inset band along the rim
-- what lies inside and within `outline_thickness` of it -- and a band
centred on each seam, as thick in all, so every edge is stroked as thick.
Points within `d` of some pieces make a *band*: a rectangle of half-width
`d` along every piece and a disc at every end, each wound once, so a point
is in the band where its count is not zero. The band pieces are cut into
the slabs with the edges, which keeps every trapezoid inside or outside
each piece whole.

The rim's bands are only ever read on one side of the rim: an inset is the
polygon *without* its band, so only the band's points inside count, and an
outset the polygon *with* it, so only those outside. A point on that side
whose nearest rim point is a corner lies in the corner's normal cone, the
wedge between its two pieces' normals, and that cone opens onto the side
only where the corner is reflex from it. So a rim corner needs no disc
where it is convex from that side, and only that wedge of one, a *pie*,
where it is reflex; and a piece needs only the half of its rectangle on
that side. A pie spans the corner's turn, so a polygon of many shallow
corners -- a rounded one -- adds a few edges per corner rather than a
whole disc. A half rectangle's base lies on the rim's own line, so the
walk across a slab passes over the stretches of no width between them.

A shadow's spread offsets the whole polygon first (`geom[0]`, zero for a
render call): outwards it is the polygon or its rim's band, inwards the
polygon without it. The fill is the polygon offset by the outline's width
less, off the seams' band, so the outline is an inset band of the offset
polygon. A shadow ring's thickness is the outline's plus twice the spread,
so its seams' band grows by the spread as well.
"""

from std.math import atan2, ceil, cos, max, min, nan, pi, sin, sqrt, tau

from create.math.geometry import Line, Polygon
from create.math.matrix import Matrix, apply as mat_apply
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D

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
    var slope: Float64
    """How far x moves per unit of y, worked out once: the sweep asks every
    edge its x many times over."""

    def __init__(
        out self,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
        sign: Int,
        layer: Int,
    ):
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.sign = sign
        self.layer = layer
        self.slope = (x1 - x0) / (y1 - y0)

    def x_at(self, y: Float64) -> Float64:
        """The edge's x at `y`, from its lower end, so every slab that asks
        at the same `y` gets the same answer."""
        if y <= self.y0:
            return self.x0
        if y >= self.y1:
            return self.x1
        return self.x0 + self.slope * (y - self.y0)


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
    # each needs the rim's band of that radius, unless the offset is zero.
    # The seams' band is half the outline's width, either side.
    var outer = grow
    var inner = grow - t
    var edges = List[_Edge]()
    _add_loop(edges, vertices, 0)
    var layers = _Layers()
    var pieces = (List[Line](), List[Line]())
    if outer != 0.0 or t > 0.0:
        pieces = Polygon(vertices^)._pieces()
    ref rim = pieces[0]
    ref seams = pieces[1]
    var shape = Polygon(c.points.copy())
    var rim_corners = _rim_corners(rim, shape)
    # Corners that get a whole disc in a rim band, whichever side it is on.
    var discs = List[Point2D]()
    if outer != 0.0:
        layers.outer = layers.next()
        _add_rim_band(
            edges,
            shape,
            rim,
            rim_corners,
            abs(outer),
            outer > 0.0,
            sf,
            layers.outer,
        )
    if t > 0.0 and inner != 0.0:
        layers.inner = layers.next()
        _add_rim_band(
            edges,
            shape,
            rim,
            rim_corners,
            abs(inner),
            inner > 0.0,
            sf,
            layers.inner,
        )
        for corner in rim_corners:
            if not corner.known:
                discs.append(corner.position)
    if t > 0.0 and len(seams) > 0:
        layers.seams = layers.next()
        var ends = List[Point2D]()
        for p in _ends(seams):
            # Inside a disc of the fill's own band, a seam's adds nothing.
            if not (inner <= -t / 2.0 and p in discs):
                ends.append(p)
        _add_band(edges, seams, ends, t / 2.0, sf, layers.seams)

    def starts_lower(a: _Edge, b: _Edge) -> Bool:
        return a.y0 < b.y0

    sort(edges, starts_lower)
    # A sweep upwards, one slab at a time. The edges spanning the slab are
    # carried from one to the next in their order across it, which changes
    # little, so sorting them stays cheap.
    var active = List[_Edge]()
    var middles = List[Float64]()
    var next = 0
    var y_lo = edges[0].y0 if len(edges) > 0 else 0.0
    while True:
        var kept = 0
        for i in range(len(active)):
            if active[i].y1 > y_lo:
                active[kept] = active[i]
                kept += 1
        while len(active) > kept:
            _ = active.pop()
        while next < len(edges) and edges[next].y0 <= y_lo:
            if edges[next].y1 > y_lo:
                active.append(edges[next])
            next += 1
        if len(active) == 0:
            if next == len(edges):
                break
            y_lo = edges[next].y0
            continue

        # The slab runs up to the next edge's start or end, or the lowest
        # crossing within it. Edges crossing inside the slab leave some
        # neighbours in its middle's order crossing there too, so only
        # neighbours are searched, the slab cut down to the lowest crossing
        # until none do.
        var y_hi = active[0].y1
        for e in active:
            y_hi = min(y_hi, e.y1)
        if next < len(edges):
            y_hi = min(y_hi, edges[next].y0)
        while True:
            var y_mid = 0.5 * (y_lo + y_hi)
            middles.clear()
            for e in active:
                middles.append(e.x_at(y_mid))
            _sort_by(active, middles)
            # Neighbours cross in the slab only if their order flips
            # between its middle and one of its ends.
            var lowest = y_hi
            var below = active[0].x_at(y_lo)
            var above = active[0].x_at(y_hi)
            for i in range(len(active) - 1):
                var next_below = active[i + 1].x_at(y_lo)
                var next_above = active[i + 1].x_at(y_hi)
                if below > next_below or above > next_above:
                    var y = _crossing(active[i], active[i + 1])
                    if y > y_lo and y < lowest:
                        lowest = y
                below = next_below
                above = next_above
            if lowest == y_hi:
                break
            y_hi = lowest

        # Walk in from the left, where every count is zero. The stretch
        # after edge `i` runs to edge `i + 1`; runs of one class merge. A
        # stretch with no width -- a band's edge along the rim's, two pieces
        # meeting at a corner -- paints nothing, so it changes no run.
        var counts = Array[Int, 4](fill=0)
        var run_class = _NOTHING
        var run_start = 0
        for i in range(len(active)):
            counts[active[i].layer] -= active[i].sign
            if i + 1 < len(active) and middles[i + 1] - middles[i] <= 1e-9 * (
                1.0 + abs(middles[i])
            ):
                continue
            var cls = _classify(counts, outer, inner, layers, t > 0.0)
            if cls == run_class:
                continue
            if run_class != _NOTHING:
                _emit(
                    out, run_class, active[run_start], active[i], y_lo, y_hi, m
                )
            run_class = cls
            run_start = i
        y_lo = y_hi

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


@fieldwise_init
struct _Layers(Copyable, ImplicitlyCopyable, Movable):
    """Which count each band is wound into; 0, the polygon's own, for a band
    not needed."""

    var outer: Int
    var inner: Int
    var seams: Int

    def __init__(out self):
        self.outer = 0
        self.inner = 0
        self.seams = 0

    def next(self) -> Int:
        return max(self.outer, self.inner, self.seams) + 1


def _classify(
    counts: Array[Int, 4],
    outer: Float64,
    inner: Float64,
    layers: _Layers,
    outlined: Bool,
) -> Int:
    """Whether a stretch with these winding counts is fill, outline or
    neither: inside the polygon offset by `outer` and, if outlined, inside
    it offset by `inner` and off the seams, or not."""
    var inside = counts[0] != 0
    if not _offset_holds(inside, counts[layers.outer] != 0, outer):
        return _NOTHING
    if not outlined:
        return _FILL
    if layers.seams != 0 and counts[layers.seams] != 0:
        return _OUTLINE
    if _offset_holds(inside, counts[layers.inner] != 0, inner):
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


def _ends(lines: List[Line]) -> List[Point2D]:
    """Every end of `lines`, once."""
    var ends = List[Point2D]()
    for l in lines:
        for p in [l.start, l.end]:
            if p not in ends:
                ends.append(p)
    return ends^


def _add_band(
    mut edges: List[_Edge],
    lines: List[Line],
    ends: List[Point2D],
    d: Float64,
    sf: Float64,
    layer: Int,
):
    """The pieces of the band within `d` of `lines`: a rectangle along
    each and a disc at each of `ends`, each wound counter-clockwise so the
    band's count is how many cover a point."""
    var segments = circle_segments(d * sf)
    var disc = List[Point2D](capacity=segments)
    for a in ends:
        disc.clear()
        for k in range(segments):
            var angle = tau * Float64(k) / Float64(segments)
            disc.append(Point2D(a.x + d * cos(angle), a.y + d * sin(angle)))
        _add_loop(edges, disc, layer)
    for l in lines:
        var a = l.start
        var b = l.end
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


@fieldwise_init
struct _RimCorner(Copyable, ImplicitlyCopyable, Movable):
    """Where two rim pieces meet, seen from the corner: `a` and `b` are the
    unit directions along them, `inside_between` whether the polygon fills
    the narrower wedge between them. `known` is false where the corner is
    not two pieces meeting at an angle, and it takes a whole disc."""

    var position: Point2D
    var a: Vector2D
    var b: Vector2D
    var inside_between: Bool
    var known: Bool


def _rim_corners(rim: List[Line], shape: Polygon) -> List[_RimCorner]:
    """Every end of `rim`, with how the polygon lies about it."""
    var corners = List[_RimCorner]()
    for p in _ends(rim):
        var directions = List[Vector2D]()
        var shortest = Float64.MAX
        for l in rim:
            if l.start == p:
                directions.append(l.end - p)
            elif l.end == p:
                directions.append(l.start - p)
            else:
                continue
            shortest = min(shortest, directions[len(directions) - 1].mag())
        var none = Vector2D(0.0, 0.0)
        if len(directions) != 2 or shortest <= 0.0:
            corners.append(_RimCorner(p, none, none, False, False))
            continue
        var a = directions[0].normalize()
        var b = directions[1].normalize()
        var between = a + b
        if between.mag() < 1e-9:
            # Straight on: the rectangles meet flush on both sides.
            corners.append(_RimCorner(p, a, b, False, True))
            continue
        var probe = p + between.normalize() * (shortest * 1e-4)
        corners.append(_RimCorner(p, a, b, shape.contains(probe), True))
    return corners^


def _add_rim_band(
    mut edges: List[_Edge],
    shape: Polygon,
    rim: List[Line],
    corners: List[_RimCorner],
    d: Float64,
    outside: Bool,
    sf: Float64,
    layer: Int,
):
    """The band within `d` of the rim, exact on one side of it -- outside
    the polygon if `outside`, else inside -- and nowhere else that matters:
    along each piece the half of its rectangle on that side, and at each
    corner nothing, a pie, or (where unknown) a whole disc."""
    var ends = List[Point2D]()
    for corner in corners:
        if not corner.known:
            ends.append(corner.position)
    # Whole discs where a corner is unknown.
    _add_band(edges, List[Line](), ends, d, sf, layer)
    # Along each piece, the half of its rectangle on the side.
    for l in rim:
        var along = l.end - l.start
        var length = along.mag()
        if length == 0.0:
            continue
        var n = Vector2D(along.y, -along.x) * (d / length)
        var middle = l.start + along * 0.5
        var probe = middle + n * (1e-4 * min(length, d) / d)
        if shape.contains(probe) == outside:
            n = -n
        var half: List[Point2D] = [l.start, l.end, l.end + n, l.start + n]
        if _signed_area2(half) < 0.0:
            half.reverse()
        _add_loop(edges, half, layer)
    var segments = circle_segments(d * sf)
    var pie = List[Point2D]()
    for corner in corners:
        if not corner.known:
            continue
        var straight = (corner.a + corner.b).mag() < 1e-9
        # The side fills the narrower wedge: covered by the rectangles.
        if straight or corner.inside_between != outside:
            continue
        # Normals turned away from the other piece, into the wider wedge.
        var na = Vector2D(-corner.a.y, corner.a.x)
        if na.dot(corner.b) > 0.0:
            na = -na
        var nb = Vector2D(-corner.b.y, corner.b.x)
        if nb.dot(corner.a) > 0.0:
            nb = -nb
        var start = atan2(na.y, na.x)
        var sweep = atan2(nb.y, nb.x) - start
        if sweep > pi:
            sweep -= tau
        elif sweep < -pi:
            sweep += tau
        var steps = max(Int(ceil(Float64(segments) * abs(sweep) / tau)), 1)
        pie.clear()
        pie.append(corner.position)
        for k in range(steps + 1):
            var angle = start + sweep * Float64(k) / Float64(steps)
            pie.append(
                Point2D(
                    corner.position.x + d * cos(angle),
                    corner.position.y + d * sin(angle),
                )
            )
        # Wound counter-clockwise, like every band piece.
        if sweep < 0.0:
            pie.reverse()
        _add_loop(edges, pie, layer)


def _signed_area2(points: List[Point2D]) -> Float64:
    var n = len(points)
    var sum = 0.0
    for i in range(n):
        var a = points[i]
        var b = points[(i + 1) % n]
        sum += a.x * b.y - b.x * a.y
    return sum


def _crossing(p: _Edge, q: _Edge) -> Float64:
    """The y where `p` and `q` cross, or NaN if they don't: where their x
    difference changes sign across the span they share, the same whichever
    way round they are passed."""
    var y_lo = max(p.y0, q.y0)
    var y_hi = min(p.y1, q.y1)
    if y_hi <= y_lo:
        return nan[DType.float64]()
    var lo = p.x_at(y_lo) - q.x_at(y_lo)
    var hi = p.x_at(y_hi) - q.x_at(y_hi)
    if (lo < 0.0 and hi > 0.0) or (lo > 0.0 and hi < 0.0):
        return y_lo + (y_hi - y_lo) * lo / (lo - hi)
    return nan[DType.float64]()


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
