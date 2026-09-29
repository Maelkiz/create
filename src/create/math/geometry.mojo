from std.math import (
    acos,
    atan2,
    ceil,
    cos,
    floor,
    min,
    max,
    sin,
    sqrt,
    tan,
    pi,
    tau,
)
from .bezier import Bezier
from .point2d import Point2D
from .vector2d import Vector2D

comptime _ANGLE_EPSILON = 1e-12
"""How far, in radians, a direction may fall outside a sweep and still count
as on its edge. The edges come from `cos`/`sin` of the angles, which round, so
without it a point exactly on an edge (`Arc.at(1)`, say) could test outside."""

comptime _RADIUS_EPSILON = 1e-9
"""How far, as a fraction of the radius, a point may lie off an arc's circle
and still count as on it. A point on an arc is found through `cos`, `sin` and
`sqrt`, which round, so exact equality would miss most of them: tangents,
crossings, the arc's own `at`."""

comptime _MAX_ARC_BEZIER_ANGLE = pi / 4.0
"""The widest piece `Arc.beziers` approximates with one cubic. At 45° the
cubic strays from the circle by about 4e-6 of the radius: under a quarter
pixel for any radius short of 60,000 pixels."""

comptime _MAX_ARC_FLATTEN_SEGMENTS = 1024
"""Upper bound on `Arc.flatten`'s segment count, as for `Bezier.flatten`."""


def _closest_on_segment(p: Point2D, a: Point2D, b: Point2D) -> Point2D:
    var ab = b - a
    var len_sq = ab.dot(ab)
    if len_sq == 0.0:
        return a
    var t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    return a + ab * t


def _orientation(a: Point2D, b: Point2D, c: Point2D) -> Int:
    var cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    if cross > 0.0:
        return 1
    if cross < 0.0:
        return -1
    return 0


def _point_on_segment(p: Point2D, a: Point2D, b: Point2D) -> Bool:
    if _orientation(a, b, p) != 0:
        return False
    return min(a.x, b.x) <= p.x <= max(a.x, b.x) and min(
        a.y, b.y
    ) <= p.y <= max(a.y, b.y)


def _dist_sq(p: Point2D, q: Point2D) -> Float64:
    var d = p - q
    return d.dot(d)


def _cross(a: Vector2D, b: Vector2D) -> Float64:
    return a.x * b.y - a.y * b.x


def _unit(angle: Float64) -> Vector2D:
    return Vector2D(cos(angle), sin(angle))


def _normalized_sweep(
    start_angle: Float64, sweep_angle: Float64
) -> Tuple[Float64, Float64]:
    """The same sweep as a start angle and a counter-clockwise extent in
    `[0, tau]`: a clockwise sweep is walked from its other end, and anything
    past a full turn is a full turn."""
    if sweep_angle < 0.0:
        return (start_angle + sweep_angle, min(-sweep_angle, tau))
    return (start_angle, min(sweep_angle, tau))


def _in_sweep(v: Vector2D, start_angle: Float64, sweep_angle: Float64) -> Bool:
    """Whether direction `v` lies within the sweep, edges included, for a
    normalized sweep (`_normalized_sweep`). A zero `v` has no direction and
    counts as inside.

    Decided by cross products against the edge directions rather than by
    comparing `atan2` angles, so there is no wrap-around at ±pi to handle.
    Up to a half turn the sweep is convex: `v` must be on the inner side of
    both edges and not pointing away from them. Past a half turn it is
    whatever the open, convex wedge it leaves out is not.
    """
    if sweep_angle >= tau:
        return True
    var mag = v.mag()
    if mag == 0.0:
        return True
    var slack = _ANGLE_EPSILON * mag
    var u0 = _unit(start_angle)
    var u1 = _unit(start_angle + sweep_angle)
    if sweep_angle <= pi:
        return (
            _cross(u0, v) >= -slack
            and _cross(v, u1) >= -slack
            and v.dot(_unit(start_angle + sweep_angle / 2.0)) >= -slack
        )
    return not (_cross(u1, v) > slack and _cross(v, u0) > slack)


def _project_range[
    N: Int
](nx: Float64, ny: Float64, pts: Array[Point2D, N]) -> Tuple[Float64, Float64]:
    var lo = nx * pts[0].x + ny * pts[0].y
    var hi = lo
    for i in range(1, N):
        var proj = nx * pts[i].x + ny * pts[i].y
        lo = min(lo, proj)
        hi = max(hi, proj)
    return (lo, hi)


def _ranges_separate[
    N: Int, M: Int
](
    nx: Float64,
    ny: Float64,
    a: Array[Point2D, N],
    b: Array[Point2D, M],
) -> Bool:
    var ra = _project_range(nx, ny, a)
    var rb = _project_range(nx, ny, b)
    return ra[1] < rb[0] or rb[1] < ra[0]


def _polygons_overlap[
    N: Int, M: Int
](a: Array[Point2D, N], b: Array[Point2D, M]) -> Bool:
    # SAT over both polygons' edge normals -- exact for convex polygons.
    # A zero-length edge contributes no normal, so its axis is skipped; its
    # direction is tested instead (needed to separate collinear degenerate
    # polygons), and the world axes are always tested (needed when both
    # polygons collapse to points and contribute no edge axes at all).
    # Testing extra axes is always sound: separation on any axis proves
    # disjointness, and genuinely overlapping shapes separate on none.
    for i in range(N):
        var p0 = a[i]
        var p1 = a[(i + 1) % N]
        var dx = p1.x - p0.x
        var dy = p1.y - p0.y
        if dx == 0.0 and dy == 0.0:
            continue
        if _ranges_separate(-dy, dx, a, b):
            return False
        if _ranges_separate(dx, dy, a, b):
            return False
    for i in range(M):
        var p0 = b[i]
        var p1 = b[(i + 1) % M]
        var dx = p1.x - p0.x
        var dy = p1.y - p0.y
        if dx == 0.0 and dy == 0.0:
            continue
        if _ranges_separate(-dy, dx, a, b):
            return False
        if _ranges_separate(dx, dy, a, b):
            return False
    if _ranges_separate(1.0, 0.0, a, b):
        return False
    if _ranges_separate(0.0, 1.0, a, b):
        return False
    return True


struct Rectangle(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """An axis-aligned rectangle: `center`, `area`, `left`/`right`/`bottom`/
    `top`, `closest_point`, `contains`, `move_to`, `translate`.

    Locations are `Point2D` and displacements `Vector2D`, throughout this
    module; extents are plain scalars, like `Circle`'s radius. Width and
    height are two independent lengths rather than a coordinate pair, so
    they are not grouped: read them as `w`/`h` and pair them however the
    caller needs.

    `position` is the centre, not a corner -- consistent with every shape in
    this module and with `canvas.rectangle`. `w`/`h` are full width and
    height, so `left()`/`right()`/`bottom()`/`top()` are `+-w/2`/`+-h/2`
    from the centre. Coordinates follow world space: y grows upward, so
    `top()` is `position.y + h/2` and `bottom()` is `position.y - h/2`.

    `contains` and `closest_point` treat the boundary as inside -- a point
    exactly on an edge is contained, and `closest_point` returns it
    unchanged. A zero `w`/`h` collapses the rectangle to a segment or a
    point; `contains`/`overlaps` remain exact for it rather than reporting
    a false containment or overlap. `w`/`h` are assumed non-negative.
    """

    var position: Point2D
    var w: Float64
    var h: Float64

    def __init__(out self, position: Point2D, w: Float64, h: Float64):
        self.position = position
        self.w = w
        self.h = h

    def __init__(out self, position: Point2D, w: Int, h: Int):
        self = Rectangle(position, Float64(w), Float64(h))

    def __eq__(self, other: Rectangle) -> Bool:
        return (
            self.position == other.position
            and self.w == other.w
            and self.h == other.h
        )

    def __ne__(self, other: Rectangle) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Rectangle(position=",
            self.position,
            ", w=",
            self.w,
            ", h=",
            self.h,
            ")",
        )

    def center(self) -> Point2D:
        return self.position

    def area(self) -> Float64:
        return self.w * self.h

    def closest_point(self, p: Point2D) -> Point2D:
        return Point2D(
            max(self.left(), min(p.x, self.right())),
            max(self.bottom(), min(p.y, self.top())),
        )

    def left(self) -> Float64:
        return self.position.x - self.w / 2.0

    def right(self) -> Float64:
        return self.position.x + self.w / 2.0

    def bottom(self) -> Float64:
        return self.position.y - self.h / 2.0

    def top(self) -> Float64:
        return self.position.y + self.h / 2.0

    def contains(self, p: Point2D) -> Bool:
        return (
            self.left() <= p.x <= self.right()
            and self.bottom() <= p.y <= self.top()
        )

    def contains(self, other: Rectangle) -> Bool:
        return (
            self.left() <= other.left()
            and other.right() <= self.right()
            and self.bottom() <= other.bottom()
            and other.top() <= self.top()
        )

    def contains(self, c: Circle) -> Bool:
        return (
            self.left() <= c.position.x - c.r
            and c.position.x + c.r <= self.right()
            and self.bottom() <= c.position.y - c.r
            and c.position.y + c.r <= self.top()
        )

    def contains(self, t: Triangle) -> Bool:
        for p in t._points():
            if not self.contains(p):
                return False
        return True

    def contains(self, l: Line) -> Bool:
        return self.contains(l.start) and self.contains(l.end)

    def contains(self, s: Sector) -> Bool:
        return self.contains(s.bounds())

    def move_to(mut self, position: Point2D):
        self.position = position

    def translate(mut self, delta: Vector2D):
        self.position = self.position + delta

    def _points(self) -> Array[Point2D, 4]:
        return [
            Point2D(self.left(), self.bottom()),
            Point2D(self.right(), self.bottom()),
            Point2D(self.right(), self.top()),
            Point2D(self.left(), self.top()),
        ]


struct Circle(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A circle: `center`, `area`, `diameter`, `closest_point`, `contains`,
    `move_to`, `translate`.

    `position` is the centre and `r` the radius -- there is no orientation, so
    unlike `Rectangle`/`Triangle` there is nothing y-up affects beyond the
    centre's own coordinates.

    `contains` treats the boundary as inside (`dist <= r`), and
    `closest_point` returns the query point itself when it is already
    inside or exactly at the centre, rather than an arbitrary point on the
    circumference. A zero `r` collapses the circle to a point; `contains`
    then holds only for that exact point, and `overlaps`/`intersects`
    remain exact rather than always-false. `r` is assumed non-negative.
    """

    var position: Point2D
    var r: Float64

    def __init__(out self, position: Point2D, r: Float64):
        self.position = position
        self.r = r

    def __init__(out self, position: Point2D, r: Int):
        self = Circle(position, Float64(r))

    def __eq__(self, other: Circle) -> Bool:
        return self.position == other.position and self.r == other.r

    def __ne__(self, other: Circle) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Circle(position=", self.position, ", r=", self.r, ")")

    def center(self) -> Point2D:
        return self.position

    def area(self) -> Float64:
        return pi * self.r * self.r

    def diameter(self) -> Float64:
        return self.r * 2.0

    def closest_point(self, p: Point2D) -> Point2D:
        var d = p - self.position
        var dist_sq = d.dot(d)
        if dist_sq == 0.0 or dist_sq <= self.r * self.r:
            return p
        return self.position + d * (self.r / sqrt(dist_sq))

    def contains(self, p: Point2D) -> Bool:
        return _dist_sq(p, self.position) <= self.r * self.r

    def contains(self, other: Circle) -> Bool:
        var dist = sqrt(_dist_sq(other.position, self.position))
        return dist + other.r <= self.r

    def contains(self, r: Rectangle) -> Bool:
        for p in r._points():
            if not self.contains(p):
                return False
        return True

    def contains(self, t: Triangle) -> Bool:
        for p in t._points():
            if not self.contains(p):
                return False
        return True

    def contains(self, l: Line) -> Bool:
        return self.contains(l.start) and self.contains(l.end)

    def contains(self, s: Sector) -> Bool:
        # A sector is its tip fanned out to its arc, and a disc is convex,
        # so it holds the sector when it holds the tip and the arc's point
        # furthest from its centre. That point comes through `cos` and
        # `sin`, so it gets an arc's slack, as in `Sector.contains`.
        if not self.contains(s.position):
            return False
        var far = s.arc()._furthest_along(s.position - self.position)
        var reach = self.r * (1.0 + _RADIUS_EPSILON)
        return _dist_sq(far, self.position) <= reach * reach

    def move_to(mut self, position: Point2D):
        self.position = position

    def translate(mut self, delta: Vector2D):
        self.position = self.position + delta


struct Line(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A line segment from `start` to `end`: `length`, `length_sq`,
    `midpoint`, `closest_point`, `intersects`, `move_to`, `translate`.

    Unlike `Rectangle`/`Circle`/`Triangle`, `Line` has no interior and is
    not a shape: it has no `center()`, `contains(region)` beyond the two
    endpoint-based overloads below, `area()`, or `overlaps` overload. It is
    the one type in this module that can be the *subject* of an asymmetric
    relation, `l.intersects(x)` -- see the comment above `intersects`
    for why that method exists only here.

    `intersects` and `_point_on_segment`-based checks treat the endpoints
    and any touching/collinear-overlapping point as inclusive. A
    zero-length line (`start == end`) is a degenerate point segment:
    `intersects` and `closest_point` remain exact for it (a point can
    still "intersect" the collapsed line if it coincides with it).
    """

    var start: Point2D
    var end: Point2D

    def __init__(out self, start: Point2D, end: Point2D):
        self.start = start
        self.end = end

    def __eq__(self, other: Line) -> Bool:
        return self.start == other.start and self.end == other.end

    def __ne__(self, other: Line) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Line(start=", self.start, ", end=", self.end, ")")

    def length_sq(self) -> Float64:
        return _dist_sq(self.end, self.start)

    def length(self) -> Float64:
        return sqrt(self.length_sq())

    def intersects(self, other: Line) -> Bool:
        var o1 = _orientation(self.start, self.end, other.start)
        var o2 = _orientation(self.start, self.end, other.end)
        var o3 = _orientation(other.start, other.end, self.start)
        var o4 = _orientation(other.start, other.end, self.end)

        if (
            o1 != 0
            and o2 != 0
            and o1 != o2
            and o3 != 0
            and o4 != 0
            and o3 != o4
        ):
            return True
        # Collinear arms -- inclusive: touching or overlapping counts.
        if o1 == 0 and _point_on_segment(other.start, self.start, self.end):
            return True
        if o2 == 0 and _point_on_segment(other.end, self.start, self.end):
            return True
        if o3 == 0 and _point_on_segment(self.start, other.start, other.end):
            return True
        if o4 == 0 and _point_on_segment(self.end, other.start, other.end):
            return True
        return False

    # `x.intersects(y)` is the curve-as-subject relation, for `Line` and
    # `Arc` -- asymmetric, unlike `overlaps`, because a curve has no interior
    # and cannot be an operand of a symmetric region test. Two curves meet
    # where they cross or touch: exactly for two `Line`s, within
    # `_RADIUS_EPSILON` once an `Arc` is involved, since its points are
    # rounded. A region is tested by the cheapest exact method for that
    # shape -- `Circle` via `closest_point`-then-`contains` (exact only
    # because a circle's containment is radial from its centre), `Rectangle`
    # and `Triangle` via endpoint containment (covers a curve wholly inside,
    # which no edge test would catch) plus their edges as `Line`s, and
    # `Sector` the same way, its edges being two radii and an `Arc`.
    def intersects(self, p: Point2D) -> Bool:
        return _point_on_segment(p, self.start, self.end)

    def intersects(self, a: Arc) -> Bool:
        return a.intersects(self)

    def intersects(self, s: Sector) -> Bool:
        if s.contains(self.start) or s.contains(self.end):
            return True
        return s._boundary_meets(self)

    def intersects(self, c: Circle) -> Bool:
        return c.contains(self.closest_point(c.position))

    def intersects(self, r: Rectangle) -> Bool:
        if r.contains(self.start) or r.contains(self.end):
            return True
        var pts = r._points()
        for i in range(4):
            var edge = Line(pts[i], pts[(i + 1) % 4])
            if self.intersects(edge):
                return True
        return False

    def intersects(self, t: Triangle) -> Bool:
        if t.contains(self.start) or t.contains(self.end):
            return True
        var pts = t._points()
        for i in range(3):
            var edge = Line(pts[i], pts[(i + 1) % 3])
            if self.intersects(edge):
                return True
        return False

    def closest_point(self, p: Point2D) -> Point2D:
        return _closest_on_segment(p, self.start, self.end)

    def midpoint(self) -> Point2D:
        return self.start.lerp(self.end, 0.5)

    def move_to(mut self, position: Point2D):
        self.translate(position - self.midpoint())

    def translate(mut self, delta: Vector2D):
        self.start = self.start + delta
        self.end = self.end + delta


struct Arc(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A circular arc: part of the circle around `position` with radius `r`,
    from `start_angle` round by `sweep_angle`. `end_angle`, `at`, `tangent`,
    `length`, `at_distance`, `bounds`, `flatten`, `beziers`,
    `closest_point`, `intersects`, `move_to`, `translate`.

    Angles are radians, counted counter-clockwise from the +x axis: y is up,
    so this is the direction `rotate` turns. The sweep is signed -- positive
    runs counter-clockwise, negative clockwise -- so every arc has one
    spelling and reversing one is negating its sweep. A sweep of a full turn
    (`tau`) or more is the whole circle. The fields keep what was given; the
    methods read the sweep clamped to a turn.

    Like `Line` and `Bezier`, an arc is a curve with no interior: there is
    no `area`, `contains` or `overlaps` for it. `position` is the circle's
    centre, which the arc passes through only when `r` is zero, and
    `move_to` moves that centre. A zero `r` or sweep collapses the arc to a
    point.
    """

    var position: Point2D
    var r: Float64
    var start_angle: Float64
    var sweep_angle: Float64

    def __init__(
        out self,
        position: Point2D,
        r: Float64,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self.position = position
        self.r = r
        self.start_angle = start_angle
        self.sweep_angle = sweep_angle

    def __init__(
        out self,
        position: Point2D,
        r: Int,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self = Arc(position, Float64(r), start_angle, sweep_angle)

    def __eq__(self, other: Arc) -> Bool:
        return (
            self.position == other.position
            and self.r == other.r
            and self.start_angle == other.start_angle
            and self.sweep_angle == other.sweep_angle
        )

    def __ne__(self, other: Arc) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Arc(position=",
            self.position,
            ", r=",
            self.r,
            ", start_angle=",
            self.start_angle,
            ", sweep_angle=",
            self.sweep_angle,
            ")",
        )

    def end_angle(self) -> Float64:
        """`start_angle + sweep_angle`: where the arc ends, as an angle."""
        return self.start_angle + self.sweep_angle

    def _sweep(self) -> Float64:
        """The signed sweep, clamped to a full turn either way."""
        return max(-tau, min(self.sweep_angle, tau))

    def _point_at_angle(self, angle: Float64) -> Point2D:
        return self.position + _unit(angle) * self.r

    def at(self, t: Float64) -> Point2D:
        """The point at parameter `t`: 0 at the start, 1 at the end, and
        proportional to distance along the arc in between. Not clamped:
        outside 0..1 it carries on round the circle."""
        return self._point_at_angle(self.start_angle + self._sweep() * t)

    def tangent(self, t: Float64) -> Vector2D:
        """The derivative at `t`: the direction of travel, with a magnitude
        that is the arc's length (the speed per unit of `t`, the same
        everywhere). Zero for a collapsed arc."""
        var sweep = self._sweep()
        var angle = self.start_angle + sweep * t
        return Vector2D(-sin(angle), cos(angle)) * (self.r * sweep)

    def length(self) -> Float64:
        """The distance along the arc from start to end. Exact."""
        return self.r * abs(self._sweep())

    def at_distance(self, distance: Float64) -> Point2D:
        """The point `distance` along the arc from its start, clamped to the
        arc's ends. An arc has constant speed, so this is `at` with `t`
        scaled: exact, and as cheap as `at`."""
        var total = self.length()
        if distance <= 0.0 or total == 0.0:
            return self.at(0.0)
        if distance >= total:
            return self.at(1.0)
        return self.at(distance / total)

    def bounds(self) -> Rectangle:
        """The tightest axis-aligned rectangle around the arc: its two ends,
        widened to each of the circle's four extremes the arc passes."""
        var s = _normalized_sweep(self.start_angle, self.sweep_angle)
        var a = self.at(0.0)
        var b = self.at(1.0)
        var lo = Point2D(min(a.x, b.x), min(a.y, b.y))
        var hi = Point2D(max(a.x, b.x), max(a.y, b.y))
        if _in_sweep(Vector2D(1.0, 0.0), s[0], s[1]):
            hi.x = self.position.x + self.r
        if _in_sweep(Vector2D(0.0, 1.0), s[0], s[1]):
            hi.y = self.position.y + self.r
        if _in_sweep(Vector2D(-1.0, 0.0), s[0], s[1]):
            lo.x = self.position.x - self.r
        if _in_sweep(Vector2D(0.0, -1.0), s[0], s[1]):
            lo.y = self.position.y - self.r
        return Rectangle(lo.lerp(hi, 0.5), hi.x - lo.x, hi.y - lo.y)

    def flatten(self, tolerance: Float64) -> List[Point2D]:
        """Points along the arc, from start to end inclusive, such that the
        straight segments between them stray from the arc by at most
        `tolerance`.

        The points are evenly spaced, as few as the tolerance allows, and
        capped at 1024 segments. A collapsed arc still gives two points.
        """
        var sweep = abs(self._sweep())
        var n = 1
        if tolerance > 0.0 and tolerance < self.r and sweep > 0.0:
            # A chord spanning angle `a` strays r * (1 - cos(a / 2)) from
            # the circle at its middle.
            var widest = 2.0 * acos(1.0 - tolerance / self.r)
            n = Int(ceil(sweep / widest))
            n = max(1, min(n, _MAX_ARC_FLATTEN_SEGMENTS))
        var points = List[Point2D](capacity=n + 1)
        for i in range(n + 1):
            points.append(self.at(Float64(i) / Float64(n)))
        return points^

    def beziers(self) -> List[Bezier]:
        """The arc as cubic Béziers, each ending where the next starts, in
        pieces of at most 45°. An approximation -- no cubic is exactly a
        circle -- but within about 4e-6 of the radius. A full circle ends
        exactly where it starts. A collapsed arc gives no curves.
        """
        var curves = List[Bezier]()
        var sweep = self._sweep()
        if self.r == 0.0 or sweep == 0.0:
            return curves^
        var n = Int(ceil(abs(sweep) / _MAX_ARC_BEZIER_ANGLE))
        var step = sweep / Float64(n)
        # Each control sits on the tangent at its end, this far out along
        # it: the length that makes the cubic's midpoint land on the circle.
        var reach = self.r * 4.0 / 3.0 * tan(step / 4.0)
        var first = self.at(0.0)
        var start = first
        for i in range(n):
            var a0 = self.start_angle + step * Float64(i)
            var a1 = a0 + step
            var end = self._point_at_angle(a1)
            if i == n - 1 and abs(sweep) == tau:
                end = first
            curves.append(
                Bezier(
                    start,
                    start + Vector2D(-sin(a0), cos(a0)) * reach,
                    end - Vector2D(-sin(a1), cos(a1)) * reach,
                    end,
                )
            )
            start = end
        return curves^

    def closest_point(self, p: Point2D) -> Point2D:
        """The point on the arc nearest `p`: straight out from the centre
        when `p` lies within the sweep, otherwise the nearer end. From the
        centre itself every point is as near, and the start is returned."""
        var v = p - self.position
        if v.mag_sq() == 0.0:
            return self.at(0.0)
        var s = _normalized_sweep(self.start_angle, self.sweep_angle)
        if _in_sweep(v, s[0], s[1]):
            return self.position + v * (self.r / v.mag())
        var a = self.at(0.0)
        var b = self.at(1.0)
        return a if _dist_sq(p, a) <= _dist_sq(p, b) else b

    def _furthest_along(self, direction: Vector2D) -> Point2D:
        """The point on the arc furthest in `direction`: straight out that
        way from the centre when the sweep reaches it, otherwise the end
        further that way. A zero `direction` gives the start."""
        if direction.mag_sq() > 0.0 and self._spans(self.position + direction):
            return self.position + direction * (self.r / direction.mag())
        var a = self.at(0.0)
        var b = self.at(1.0)
        return a if (a - b).dot(direction) >= 0.0 else b

    def _spans(self, p: Point2D) -> Bool:
        """Whether the direction from the centre to `p` lies within the
        sweep, however far `p` is from the circle."""
        var s = _normalized_sweep(self.start_angle, self.sweep_angle)
        return _in_sweep(p - self.position, s[0], s[1])

    # The `intersects` family is documented above `Line.intersects`.
    def intersects(self, p: Point2D) -> Bool:
        var off = abs((p - self.position).mag() - self.r)
        return off <= _RADIUS_EPSILON * self.r and self._spans(p)

    def intersects(self, l: Line) -> Bool:
        var d = l.end - l.start
        var len_sq = d.mag_sq()
        if len_sq == 0.0:
            return self.intersects(l.start)
        var f = l.start - self.position
        # The line through the segment comes nearest the centre at `t_near`
        # along it, `h` away, and crosses the circle `half` either side of
        # there. Each crossing, pulled back onto the segment, is a meeting
        # exactly when it is on the arc; a tangent just short of the circle
        # after rounding still gets its one touching point.
        var length = sqrt(len_sq)
        var h = abs(_cross(d, f)) / length
        if h > self.r * (1.0 + _RADIUS_EPSILON):
            return False
        var t_near = -f.dot(d) / len_sq
        var half = sqrt(max(0.0, self.r * self.r - h * h)) / length
        var t0 = max(0.0, min(t_near - half, 1.0))
        var t1 = max(0.0, min(t_near + half, 1.0))
        return self.intersects(l.start + d * t0) or self.intersects(
            l.start + d * t1
        )

    def intersects(self, other: Arc) -> Bool:
        if self.r == 0.0:
            return other.intersects(self.position)
        if other.r == 0.0:
            return self.intersects(other.position)
        var between = other.position - self.position
        var d = between.mag()
        var slack = _RADIUS_EPSILON * (self.r + other.r)
        if d <= slack:
            # One circle: the arcs meet where their sweeps overlap, which
            # is exactly when one holds an end of the other.
            if abs(self.r - other.r) > slack:
                return False
            return (
                self._spans(other.at(0.0))
                or self._spans(other.at(1.0))
                or other._spans(self.at(0.0))
                or other._spans(self.at(1.0))
            )
        if d > self.r + other.r + slack or d < abs(self.r - other.r) - slack:
            return False
        # The circles cross on the chord `along` from this centre towards
        # the other, `h` either side of the line between them.
        var along = (d * d + self.r * self.r - other.r * other.r) / (2.0 * d)
        var h = sqrt(max(0.0, self.r * self.r - along * along))
        var u = between * (1.0 / d)
        var mid = self.position + u * along
        var side = Vector2D(-u.y, u.x) * h
        var p = mid + side
        var q = mid - side
        return (self._spans(p) and other._spans(p)) or (
            self._spans(q) and other._spans(q)
        )

    def intersects(self, c: Circle) -> Bool:
        return c.contains(self.closest_point(c.position))

    def intersects(self, r: Rectangle) -> Bool:
        if r.contains(self.at(0.0)) or r.contains(self.at(1.0)):
            return True
        var pts = r._points()
        for i in range(4):
            if self.intersects(Line(pts[i], pts[(i + 1) % 4])):
                return True
        return False

    def intersects(self, t: Triangle) -> Bool:
        if t.contains(self.at(0.0)) or t.contains(self.at(1.0)):
            return True
        var pts = t._points()
        for i in range(3):
            if self.intersects(Line(pts[i], pts[(i + 1) % 3])):
                return True
        return False

    def intersects(self, s: Sector) -> Bool:
        if s.contains(self.at(0.0)) or s.contains(self.at(1.0)):
            return True
        return s._boundary_meets(self)

    def move_to(mut self, position: Point2D):
        self.position = position

    def translate(mut self, delta: Vector2D):
        self.position = self.position + delta


struct Sector(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A sector -- a slice of pie: the region between two radii of the
    circle around `position` with radius `r`, from `start_angle` round by
    `sweep_angle`. `end_angle`, `center`, `area`, `arc`, `bounds`,
    `closest_point`, `contains`, `move_to`, `translate`.

    The angles are an `Arc`'s: radians, counter-clockwise from the +x axis,
    and a signed sweep, so a negative one runs clockwise and a full turn or
    more is the whole circle. The fields keep what was given.

    `center()` is `position`, the tip of the slice, as for `Circle`: not the
    centroid. `contains` treats the boundary as inside, within the slack
    `Arc.intersects` allows, so points found on the sector's own arc count;
    `closest_point` returns the query point itself when it is inside. A sweep wider than a
    half turn is not convex. A zero `r` collapses the sector to its tip, and
    a zero sweep to the one radius at `start_angle`. `r` is assumed
    non-negative.
    """

    var position: Point2D
    var r: Float64
    var start_angle: Float64
    var sweep_angle: Float64

    def __init__(
        out self,
        position: Point2D,
        r: Float64,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self.position = position
        self.r = r
        self.start_angle = start_angle
        self.sweep_angle = sweep_angle

    def __init__(
        out self,
        position: Point2D,
        r: Int,
        start_angle: Float64,
        sweep_angle: Float64,
    ):
        self = Sector(position, Float64(r), start_angle, sweep_angle)

    def __eq__(self, other: Sector) -> Bool:
        return (
            self.position == other.position
            and self.r == other.r
            and self.start_angle == other.start_angle
            and self.sweep_angle == other.sweep_angle
        )

    def __ne__(self, other: Sector) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Sector(position=",
            self.position,
            ", r=",
            self.r,
            ", start_angle=",
            self.start_angle,
            ", sweep_angle=",
            self.sweep_angle,
            ")",
        )

    def end_angle(self) -> Float64:
        """`start_angle + sweep_angle`: where the sector ends, as an angle."""
        return self.start_angle + self.sweep_angle

    def center(self) -> Point2D:
        return self.position

    def area(self) -> Float64:
        return 0.5 * self.r * self.r * abs(self.arc()._sweep())

    def arc(self) -> Arc:
        """The curved edge of the sector, running the same way round."""
        return Arc(self.position, self.r, self.start_angle, self.sweep_angle)

    def bounds(self) -> Rectangle:
        """The tightest axis-aligned rectangle around the sector: its arc's,
        widened to take in the tip."""
        var b = self.arc().bounds()
        var lo = Point2D(
            min(b.left(), self.position.x), min(b.bottom(), self.position.y)
        )
        var hi = Point2D(
            max(b.right(), self.position.x), max(b.top(), self.position.y)
        )
        return Rectangle(lo.lerp(hi, 0.5), hi.x - lo.x, hi.y - lo.y)

    def closest_point(self, p: Point2D) -> Point2D:
        if self.contains(p):
            return p
        # Outside, the nearest point is on the boundary: one of the two
        # radii or the arc.
        var a = self.arc()
        var best = a.closest_point(p)
        var ends: Array[Point2D, 2] = [a.at(0.0), a.at(1.0)]
        for end in ends:
            var q = _closest_on_segment(p, self.position, end)
            if _dist_sq(p, q) < _dist_sq(p, best):
                best = q
        return best

    def contains(self, p: Point2D) -> Bool:
        # The arc is found through `cos` and `sin`, as is its sweep, so both
        # boundaries get an arc's slack: the sector holds its own edge.
        var reach = self.r * (1.0 + _RADIUS_EPSILON)
        if _dist_sq(p, self.position) > reach * reach:
            return False
        return self.arc()._spans(p)

    # A sector has no holes, so it holds a shape exactly when it holds the
    # shape's outline: a `Rectangle` or `Triangle` edge by edge, a `Circle`
    # as a whole-turn `Arc`, another `Sector` as its two radii and its arc.
    def contains(self, r: Rectangle) -> Bool:
        return self._contains_polygon(r._points())

    def contains(self, t: Triangle) -> Bool:
        return self._contains_polygon(t._points())

    def contains(self, c: Circle) -> Bool:
        return self._contains_arc(Arc(c.position, c.r, 0.0, tau))

    def contains(self, other: Sector) -> Bool:
        for radius in other._radii():
            if not self.contains(radius):
                return False
        return self._contains_arc(other.arc())

    # A segment or arc with both ends inside can still leave the sector:
    # across the missing wedge of one wider than a half turn, or bulging
    # out through a radius or the arc. Where it crosses the boundary -- the
    # line of either radius, or the circle -- cuts it into pieces that are
    # each wholly inside or wholly outside, so the sector holds it exactly
    # when it holds the middle of every piece. A piece that only touches
    # the boundary is inside, within the slack of `contains(Point2D)`.
    def contains(self, l: Line) -> Bool:
        if not (self.contains(l.start) and self.contains(l.end)):
            return False
        var d = l.end - l.start
        var f = l.start - self.position
        var cuts: List[Float64] = [0.0, 1.0]
        for u in self._edge_directions():
            var across = _cross(d, u)
            if across != 0.0:
                cuts.append(-_cross(f, u) / across)
        var len_sq = d.mag_sq()
        var b = f.dot(d)
        var discriminant = b * b - len_sq * (f.mag_sq() - self.r * self.r)
        if len_sq > 0.0 and discriminant >= 0.0:
            var root = sqrt(discriminant)
            cuts.append((-b - root) / len_sq)
            cuts.append((-b + root) / len_sq)
        sort(cuts)
        for i in range(len(cuts) - 1):
            var t0 = max(0.0, min(cuts[i], 1.0))
            var t1 = max(0.0, min(cuts[i + 1], 1.0))
            if not self.contains(l.start + d * ((t0 + t1) / 2.0)):
                return False
        return True

    def _contains_arc(self, a: Arc) -> Bool:
        if not (self.contains(a.at(0.0)) and self.contains(a.at(1.0))):
            return False
        var crossings = List[Point2D]()
        for u in self._edge_directions():
            var foot = self.position + u * (a.position - self.position).dot(u)
            var h_sq = _dist_sq(a.position, foot)
            if h_sq <= a.r * a.r:
                var half = sqrt(a.r * a.r - h_sq)
                crossings.append(foot + u * half)
                crossings.append(foot - u * half)
        var between = self.position - a.position
        var d = between.mag()
        if d > 0.0 and d <= a.r + self.r and d >= abs(a.r - self.r):
            var along = (d * d + a.r * a.r - self.r * self.r) / (2.0 * d)
            var h = sqrt(max(0.0, a.r * a.r - along * along))
            var u = between * (1.0 / d)
            var mid = a.position + u * along
            var side = Vector2D(-u.y, u.x) * h
            crossings.append(mid + side)
            crossings.append(mid - side)
        # Cut as angles past the start of the arc's counter-clockwise sweep.
        var s = _normalized_sweep(a.start_angle, a.sweep_angle)
        var cuts: List[Float64] = [0.0, s[1]]
        for p in crossings:
            var v = p - a.position
            var angle = atan2(v.y, v.x) - s[0]
            angle -= tau * floor(angle / tau)
            if angle < s[1]:
                cuts.append(angle)
        sort(cuts)
        for i in range(len(cuts) - 1):
            var middle = s[0] + (cuts[i] + cuts[i + 1]) / 2.0
            if not self.contains(a.position + _unit(middle) * a.r):
                return False
        return True

    def _contains_polygon[N: Int](self, pts: Array[Point2D, N]) -> Bool:
        for i in range(N):
            if not self.contains(Line(pts[i], pts[(i + 1) % N])):
                return False
        return True

    def _edge_directions(self) -> Array[Vector2D, 2]:
        """Unit directions of the two radii, from the tip outward."""
        return [
            _unit(self.start_angle),
            _unit(self.start_angle + self.arc()._sweep()),
        ]

    def _radii(self) -> Array[Line, 2]:
        """The two straight edges, from the tip out to where the arc starts
        and ends."""
        var a = self.arc()
        return [Line(self.position, a.at(0.0)), Line(self.position, a.at(1.0))]

    def _boundary_meets(self, l: Line) -> Bool:
        for radius in self._radii():
            if l.intersects(radius):
                return True
        return self.arc().intersects(l)

    def _boundary_meets(self, a: Arc) -> Bool:
        for radius in self._radii():
            if a.intersects(radius):
                return True
        return a.intersects(self.arc())

    def move_to(mut self, position: Point2D):
        self.position = position

    def translate(mut self, delta: Vector2D):
        self.position = self.position + delta


struct Triangle(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A triangle defined by its three vertices `a`, `b`, `c`: `center`,
    `area`, `closest_point`, `contains`, `move_to`, `translate`.

    Unlike `Rectangle`/`Circle`, a `Triangle` is not centre-positioned in
    its fields -- `center()` (the centroid) is derived, and `move_to`
    translates all three vertices so the centroid lands on the given
    point. Vertex winding (clockwise or counter-clockwise) does not matter
    to any method here; `contains` and `area` both work from unsigned or
    sign-normalized quantities.

    `contains` treats every edge as inside (boundary-inclusive), matching
    `Rectangle`/`Circle`. When the three vertices are collinear (including
    all three coincident), the hull has zero area and collapses to the
    longest edge as a segment; `contains`/`overlaps`/`area` all remain
    exact for this degenerate case rather than reporting a false
    containment, overlap, or a divide-by-zero.
    """

    var a: Point2D
    var b: Point2D
    var c: Point2D

    def __init__(out self, a: Point2D, b: Point2D, c: Point2D):
        self.a = a
        self.b = b
        self.c = c

    def __eq__(self, other: Triangle) -> Bool:
        return self.a == other.a and self.b == other.b and self.c == other.c

    def __ne__(self, other: Triangle) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Triangle(a=", self.a, ", b=", self.b, ", c=", self.c, ")")

    def center(self) -> Point2D:
        return Point2D(
            (self.a.x + self.b.x + self.c.x) / 3.0,
            (self.a.y + self.b.y + self.c.y) / 3.0,
        )

    def _signed_area2(self) -> Float64:
        var ab = self.b - self.a
        var ac = self.c - self.a
        return ab.x * ac.y - ab.y * ac.x

    def area(self) -> Float64:
        return abs(self._signed_area2()) / 2.0

    def closest_point(self, p: Point2D) -> Point2D:
        if self.contains(p):
            return p
        var p1 = _closest_on_segment(p, self.a, self.b)
        var p2 = _closest_on_segment(p, self.b, self.c)
        var p3 = _closest_on_segment(p, self.c, self.a)
        var d1 = _dist_sq(p1, p)
        var d2 = _dist_sq(p2, p)
        var d3 = _dist_sq(p3, p)
        if d1 <= d2 and d1 <= d3:
            return p1
        if d2 <= d3:
            return p2
        return p3

    def contains(self, p: Point2D) -> Bool:
        if self._signed_area2() == 0.0:
            # Degenerate hull: a segment (or a point). Contained iff on the
            # longest edge -- the other two edges are contained within it.
            var len_ab = _dist_sq(self.b, self.a)
            var len_bc = _dist_sq(self.c, self.b)
            var len_ca = _dist_sq(self.a, self.c)
            if len_ab >= len_bc and len_ab >= len_ca:
                return _point_on_segment(p, self.a, self.b)
            if len_bc >= len_ca:
                return _point_on_segment(p, self.b, self.c)
            return _point_on_segment(p, self.c, self.a)
        var d1 = _orientation(self.a, self.b, p)
        var d2 = _orientation(self.b, self.c, p)
        var d3 = _orientation(self.c, self.a, p)
        var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
        var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
        return not (has_neg and has_pos)

    def contains(self, other: Triangle) -> Bool:
        for p in other._points():
            if not self.contains(p):
                return False
        return True

    def contains(self, r: Rectangle) -> Bool:
        for p in r._points():
            if not self.contains(p):
                return False
        return True

    def contains(self, c: Circle) -> Bool:
        if not self.contains(c.position):
            return False
        var r_sq = c.r * c.r
        return (
            _dist_sq(
                _closest_on_segment(c.position, self.a, self.b), c.position
            )
            >= r_sq
            and _dist_sq(
                _closest_on_segment(c.position, self.b, self.c), c.position
            )
            >= r_sq
            and _dist_sq(
                _closest_on_segment(c.position, self.c, self.a), c.position
            )
            >= r_sq
        )

    def contains(self, l: Line) -> Bool:
        return self.contains(l.start) and self.contains(l.end)

    def contains(self, s: Sector) -> Bool:
        # A sector is its tip fanned out to its arc, and a triangle is
        # convex, so it holds the sector when it holds the tip and, for
        # each edge, the arc's point furthest across it. Both ways across
        # are tried, so a degenerate triangle needs no winding.
        if not self.contains(s.position):
            return False
        var a = s.arc()
        var pts = self._points()
        for i in range(3):
            var e = pts[(i + 1) % 3] - pts[i]
            var normal = Vector2D(-e.y, e.x)
            if not (
                self.contains(a._furthest_along(normal))
                and self.contains(a._furthest_along(-normal))
            ):
                return False
        return True

    def move_to(mut self, position: Point2D):
        self.translate(position - self.center())

    def translate(mut self, delta: Vector2D):
        self.a = self.a + delta
        self.b = self.b + delta
        self.c = self.c + delta

    def _points(self) -> Array[Point2D, 3]:
        return [self.a, self.b, self.c]


# `overlaps(a, b)` is the whole overlap-testing surface for regions: one
# specialized, exact overload per unordered shape pair (`Rectangle`,
# `Circle`, `Triangle`, `Sector` -- `Line` and `Arc` have no interior and are
# deliberately excluded, see the taxonomy comment above `Line.intersects`),
# so a symmetric relation reads as a symmetric call -- `overlaps(a, b)` and
# `overlaps(b, a)` always agree, and the reverse-order overload is a
# one-line delegation to the other. Each pair picks the cheapest exact
# test for that combination rather than routing through a single generic
# algorithm -- `Circle` vs. anything else is a `closest_point`-then-
# `contains` check (exact only because a circle's containment is radial
# from its centre), and any pair of straight-edged shapes is SAT over
# `_polygons_overlap`. A `Sector` is curved, and past a half turn not even
# convex, so against a polygon or another sector it is not SAT but the
# test any two regions share: one holds a point of the other (the tip, a
# vertex), or their boundaries cross (`_polygon_overlaps_sector`). The
# arc's boundary is found through `cos` and `sin`, so a sector touches
# within the slack `Arc.intersects` allows rather than exactly.
#
# Every overload is boundary-inclusive: shapes that only touch (shared
# edge, shared corner, tangent circles) count as overlapping. Degenerate
# inputs -- a zero-size rectangle, a zero-radius circle, a collinear or
# fully degenerate triangle -- remain exact rather than reporting a false
# overlap; `_polygons_overlap`'s own comment covers how SAT stays sound
# when a polygon collapses to a segment or a point.
def overlaps(a: Rectangle, b: Rectangle) -> Bool:
    return (
        a.left() <= b.right()
        and a.right() >= b.left()
        and a.bottom() <= b.top()
        and a.top() >= b.bottom()
    )


def overlaps(a: Circle, b: Circle) -> Bool:
    var rsum = a.r + b.r
    return _dist_sq(a.position, b.position) <= rsum * rsum


def overlaps(a: Circle, b: Rectangle) -> Bool:
    return a.contains(b.closest_point(a.position))


def overlaps(a: Rectangle, b: Circle) -> Bool:
    return overlaps(b, a)


def overlaps(a: Circle, b: Triangle) -> Bool:
    return a.contains(b.closest_point(a.position))


def overlaps(a: Triangle, b: Circle) -> Bool:
    return overlaps(b, a)


def overlaps(a: Rectangle, b: Triangle) -> Bool:
    return _polygons_overlap(a._points(), b._points())


def overlaps(a: Triangle, b: Rectangle) -> Bool:
    return overlaps(b, a)


def overlaps(a: Triangle, b: Triangle) -> Bool:
    return _polygons_overlap(a._points(), b._points())


def _polygon_overlaps_sector[N: Int](pts: Array[Point2D, N], s: Sector) -> Bool:
    """Whether the sector holds a vertex of the polygon, or an edge of the
    polygon crosses the sector's boundary. With the polygon holding the
    sector's tip, which the caller tests, that is every way to overlap."""
    for p in pts:
        if s.contains(p):
            return True
    for i in range(N):
        if s._boundary_meets(Line(pts[i], pts[(i + 1) % N])):
            return True
    return False


def overlaps(a: Sector, b: Circle) -> Bool:
    return b.contains(a.closest_point(b.position))


def overlaps(a: Circle, b: Sector) -> Bool:
    return overlaps(b, a)


def overlaps(a: Sector, b: Rectangle) -> Bool:
    return b.contains(a.position) or _polygon_overlaps_sector(b._points(), a)


def overlaps(a: Rectangle, b: Sector) -> Bool:
    return overlaps(b, a)


def overlaps(a: Sector, b: Triangle) -> Bool:
    return b.contains(a.position) or _polygon_overlaps_sector(b._points(), a)


def overlaps(a: Triangle, b: Sector) -> Bool:
    return overlaps(b, a)


def overlaps(a: Sector, b: Sector) -> Bool:
    if a.contains(b.position) or b.contains(a.position):
        return True
    for radius in a._radii():
        if b._boundary_meets(radius):
            return True
    return b._boundary_meets(a.arc())
