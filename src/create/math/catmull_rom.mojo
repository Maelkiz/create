from std.math import max, min, pow
from .bezier import CubicBezier
from .geometry import Rectangle
from .point2d import Point2D
from .vector2d import Vector2D


struct CatmullRomSpline(Copyable, Equatable, Movable, Writable):
    """A smooth curve through every one of `points`, in order: `at`,
    `tangent`, `length`, `at_distance`, `bounds`, `flatten`, `beziers`,
    `translate`.

    Each stretch between two neighbouring points is a cubic whose direction
    at each point is set by that point's neighbours, so the curve turns
    smoothly through every point without the off-curve controls a
    `CubicBezier` needs. The first and last points have one neighbour each;
    the curve leaves and arrives there heading along the missing neighbour's
    mirror image. With `closed`, the curve runs on from the last point back
    to the first and the ends have neighbours like any other point.

    `alpha` sets how the spacing of the points shapes the curve: 0 is
    *uniform*, which can loop or cusp where points bunch up; 0.5,
    *centripetal*, the default, never does within a stretch; 1 is *chordal*,
    which hugs the points more loosely still. Between 0 and 1 is useful.

    `t` runs from 0 at the first point to 1 at the last (back at the first
    when closed), each stretch taking an equal share whatever its length, so
    equal steps in `t` are not equal distances; `at_distance` is.

    Fewer than two distinct points make no curve: then `at` and
    `at_distance` give the one point (the origin if there is none), `length`
    is 0 and `flatten` gives no points.

    Like `CubicBezier`, a spline has no interior and is not a region.
    """

    var points: List[Point2D]
    var alpha: Float64
    var closed: Bool

    def __init__(
        out self,
        var points: List[Point2D],
        alpha: Float64 = 0.5,
        closed: Bool = False,
    ):
        self.points = points^
        self.alpha = alpha
        self.closed = closed

    def __eq__(self, other: CatmullRomSpline) -> Bool:
        if (
            self.alpha != other.alpha
            or self.closed != other.closed
            or len(self.points) != len(other.points)
        ):
            return False
        for i in range(len(self.points)):
            if self.points[i] != other.points[i]:
                return False
        return True

    def __ne__(self, other: CatmullRomSpline) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("CatmullRomSpline(points=[")
        for i in range(len(self.points)):
            if i > 0:
                writer.write(", ")
            writer.write(self.points[i])
        writer.write("], alpha=", self.alpha, ", closed=", self.closed, ")")

    def beziers(self) -> List[CubicBezier]:
        """The spline as cubic Béziers, one per stretch between neighbouring
        points, each ending where the next starts. Exact, not an
        approximation: every stretch is a cubic, and any cubic is a Bézier.

        An open spline of n points gives n - 1 curves; a closed one gives n,
        the last ending at the first point. A point repeating the one before
        it is skipped, as is a closed spline's last point repeating its
        first; fewer than two distinct points give no curves.
        """
        var p = self._distinct_points()
        var n = len(p)
        var curves = List[CubicBezier]()
        if n < 2:
            return curves^
        var segments = n if self.closed else n - 1
        curves.reserve(segments)
        for i in range(segments):
            var p1 = p[i]
            var p2 = p[(i + 1) % n]
            var p0: Point2D
            var p3: Point2D
            if self.closed:
                p0 = p[(i - 1 + n) % n]
                p3 = p[(i + 2) % n]
            else:
                # An open end mirrors its one neighbour, so the curve leaves
                # it heading straight at the next point.
                p0 = p1 + (p1 - p2) if i == 0 else p[i - 1]
                p3 = p2 + (p2 - p1) if i + 2 == n else p[i + 2]
            curves.append(self._segment(p0, p1, p2, p3))
        return curves^

    def at(self, t: Float64) -> Point2D:
        """The point at parameter `t`, clamped to 0..1: a spline has no
        natural continuation past its ends."""
        var curves = self.beziers()
        if len(curves) == 0:
            return self._lone_point()
        var located = _locate(len(curves), t)
        return curves[located[0]].at(located[1])

    def tangent(self, t: Float64) -> Vector2D:
        """The derivative with respect to `t` at `t`, clamped to 0..1: the
        direction of travel, with a magnitude that is the speed `t` moves at.
        A joint belongs to the stretch that starts there. Zero when there is
        no curve."""
        var curves = self.beziers()
        if len(curves) == 0:
            return Vector2D(0.0, 0.0)
        var located = _locate(len(curves), t)
        # Each stretch runs its own 0..1 in 1/n of the spline's `t`.
        return curves[located[0]].tangent(located[1]) * Float64(len(curves))

    def length(self) -> Float64:
        """The distance along the curve from the first point to the last,
        as each stretch's `CubicBezier.length` summed."""
        var total = 0.0
        for c in self.beziers():
            total += c.length()
        return total

    def at_distance(self, distance: Float64) -> Point2D:
        """The point `distance` along the curve from the first point,
        clamped to the curve's ends. Equal steps in `distance` are equal
        steps along the curve. Measures every stretch per call; sample once
        per frame per entity, not in a tight loop."""
        var curves = self.beziers()
        if len(curves) == 0:
            return self._lone_point()
        if distance <= 0.0:
            return curves[0].start
        var remaining = distance
        for c in curves:
            var length = c.length()
            if remaining <= length:
                return c.at_distance(remaining)
            remaining -= length
        return curves[len(curves) - 1].end

    def bounds(self) -> Rectangle:
        """The tightest axis-aligned rectangle around the curve. A spline
        with no curve gives a rectangle of no size at its one point."""
        var curves = self.beziers()
        if len(curves) == 0:
            return Rectangle(self._lone_point(), 0.0, 0.0)
        var box = curves[0].bounds()
        var lo = Point2D(
            box.position.x - box.w / 2.0, box.position.y - box.h / 2.0
        )
        var hi = Point2D(
            box.position.x + box.w / 2.0, box.position.y + box.h / 2.0
        )
        for i in range(1, len(curves)):
            box = curves[i].bounds()
            lo = Point2D(
                min(lo.x, box.position.x - box.w / 2.0),
                min(lo.y, box.position.y - box.h / 2.0),
            )
            hi = Point2D(
                max(hi.x, box.position.x + box.w / 2.0),
                max(hi.y, box.position.y + box.h / 2.0),
            )
        return Rectangle(
            Point2D((lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0),
            hi.x - lo.x,
            hi.y - lo.y,
        )

    def flatten(self, tolerance: Float64) -> List[Point2D]:
        """Points along the curve, from the first point to the last
        inclusive, straying from it by at most `tolerance` between them:
        each stretch's `CubicBezier.flatten`, joined without repeating the
        point where one stretch meets the next."""
        var points = List[Point2D]()
        for c in self.beziers():
            var part = c.flatten(tolerance)
            var first = 0 if len(points) == 0 else 1
            for i in range(first, len(part)):
                points.append(part[i])
        return points^

    def translate(mut self, delta: Vector2D):
        for i in range(len(self.points)):
            self.points[i] = self.points[i] + delta

    def _segment(
        self, p0: Point2D, p1: Point2D, p2: Point2D, p3: Point2D
    ) -> CubicBezier:
        """The stretch from `p1` to `p2` as a Bézier.

        Knots are spaced by distance to the power `alpha` (Barry–Goldman), and
        the tangents at `p1` and `p2` are that recursion's derivatives,
        rescaled from the knot interval onto the Bézier's 0..1; a Bézier's
        controls sit a third of a tangent in from its ends (Yuksel et al.,
        "Parameterization and applications of Catmull-Rom curves").
        """
        var d0 = pow((p1 - p0).mag(), self.alpha)
        var d1 = pow((p2 - p1).mag(), self.alpha)
        var d2 = pow((p3 - p2).mag(), self.alpha)
        var m1 = ((p1 - p0) / d0 - (p2 - p0) / (d0 + d1) + (p2 - p1) / d1) * d1
        var m2 = ((p2 - p1) / d1 - (p3 - p1) / (d1 + d2) + (p3 - p2) / d2) * d1
        return CubicBezier(p1, p1 + m1 / 3.0, p2 - m2 / 3.0, p2)

    def _lone_point(self) -> Point2D:
        """Where a spline with no curve sits: its first point, or the origin
        when it has none."""
        if len(self.points) == 0:
            return Point2D(0.0, 0.0)
        return self.points[0]

    def _distinct_points(self) -> List[Point2D]:
        """`points` without consecutive repeats, and, when closed, without a
        last point repeating the first: each would give a stretch of no
        length, and a zero knot interval to divide by."""
        var p = List[Point2D](capacity=len(self.points))
        for q in self.points:
            if len(p) == 0 or p[len(p) - 1] != q:
                p.append(q)
        if self.closed and len(p) > 1 and p[len(p) - 1] == p[0]:
            _ = p.pop()
        return p^


def _locate(segments: Int, t: Float64) -> Tuple[Int, Float64]:
    """Which of `segments` equal shares of 0..1 the clamped `t` falls in, and
    how far through that share: the stretch and its own `t`."""
    var scaled = max(0.0, min(1.0, t)) * Float64(segments)
    var i = min(Int(scaled), segments - 1)
    return (i, scaled - Float64(i))
