from std.math import abs, ceil, min, max, sqrt
from .geometry import Rectangle
from .point2d import Point2D
from .vector2d import Vector2D

comptime _MAX_FLATTEN_SEGMENTS = 1024
"""Upper bound on `flatten`'s segment count, so a huge curve at a tiny
tolerance costs bounded work."""

comptime _LENGTH_STEPS = 16
"""Equal steps in `t` that `_length_to` integrates separately, so the
quadrature follows a curve whose speed changes sharply."""

comptime _GAUSS_NODES: Array[Float64, 4] = [
    0.1834346424956498,
    0.5255324099163290,
    0.7966664774136267,
    0.9602898564975363,
]
"""The positive half of the 8-point Gauss–Legendre nodes on [-1, 1]; the
rule is symmetric, so each is used at plus and minus."""

comptime _GAUSS_WEIGHTS: Array[Float64, 4] = [
    0.3626837833783620,
    0.3137066458778873,
    0.2223810344533745,
    0.1012285362903763,
]

comptime _MAX_DISTANCE_ITERATIONS = 50
"""Bound on `at_distance`'s search. Newton converges in a handful; the
bound only matters for bisection on a curve with a stationary stretch."""


def _axis_extremes(
    p0: Float64, p1: Float64, p2: Float64, p3: Float64
) -> Tuple[Float64, Float64]:
    """The minimum and maximum of one coordinate of a cubic Bézier over
    `t` in [0, 1]: the endpoints plus wherever the derivative quadratic
    `a·t² + b·t + c` has a root inside the interval."""
    var lo = min(p0, p3)
    var hi = max(p0, p3)
    var d0 = p1 - p0
    var d1 = p2 - p1
    var d2 = p3 - p2
    var a = d0 - 2.0 * d1 + d2
    var b = 2.0 * (d1 - d0)
    var c = d0
    var roots = List[Float64]()
    if a == 0.0:
        if b != 0.0:
            roots.append(-c / b)
    else:
        var disc = b * b - 4.0 * a * c
        if disc >= 0.0:
            var s = sqrt(disc)
            roots.append((-b + s) / (2.0 * a))
            roots.append((-b - s) / (2.0 * a))
    for t in roots:
        if t > 0.0 and t < 1.0:
            var mt = 1.0 - t
            var v = (
                mt * mt * mt * p0
                + 3.0 * mt * mt * t * p1
                + 3.0 * mt * t * t * p2
                + t * t * t * p3
            )
            lo = min(lo, v)
            hi = max(hi, v)
    return (lo, hi)


struct CubicBezier(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A cubic Bézier curve from `start` to `end`, shaped by `control1` and
    `control2`: `at`, `tangent`, `split`, `bounds`, `flatten`, `translate`.

    The curve passes through `start` and `end` only; the controls pull it
    towards themselves and set the direction it leaves `start`
    (`control1 - start`) and arrives at `end` (`end - control2`). It is the
    curve SVG paths, fonts and vector editors use.

    Like `Line`, a curve has no interior and is not a region: there is no
    `area`, `contains` or `overlaps` for it.

    `t` runs from 0 at `start` to 1 at `end`, but it is not proportional to
    distance along the curve — equal steps in `t` bunch up where the
    controls do.
    """

    var start: Point2D
    var control1: Point2D
    var control2: Point2D
    var end: Point2D

    def __init__(
        out self,
        start: Point2D,
        control1: Point2D,
        control2: Point2D,
        end: Point2D,
    ):
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end

    def __eq__(self, other: CubicBezier) -> Bool:
        return (
            self.start == other.start
            and self.control1 == other.control1
            and self.control2 == other.control2
            and self.end == other.end
        )

    def __ne__(self, other: CubicBezier) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "CubicBezier(start=",
            self.start,
            ", control1=",
            self.control1,
            ", control2=",
            self.control2,
            ", end=",
            self.end,
            ")",
        )

    def at(self, t: Float64) -> Point2D:
        """The point at parameter `t`. Not clamped: outside 0..1 the cubic
        continues past its endpoints, as `lerp` extrapolates."""
        var mt = 1.0 - t
        var w0 = mt * mt * mt
        var w1 = 3.0 * mt * mt * t
        var w2 = 3.0 * mt * t * t
        var w3 = t * t * t
        return Point2D(
            w0 * self.start.x
            + w1 * self.control1.x
            + w2 * self.control2.x
            + w3 * self.end.x,
            w0 * self.start.y
            + w1 * self.control1.y
            + w2 * self.control2.y
            + w3 * self.end.y,
        )

    def tangent(self, t: Float64) -> Vector2D:
        """The derivative at `t`: the direction of travel, with a magnitude
        that is the curve's speed per unit of `t`. Not normalised — it is
        zero where the curve stops, e.g. at a cusp or where a control sits
        on its endpoint."""
        var mt = 1.0 - t
        var a = self.control1 - self.start
        var b = self.control2 - self.control1
        var c = self.end - self.control2
        return (a * (mt * mt) + b * (2.0 * mt * t) + c * (t * t)) * 3.0

    def split(self, t: Float64) -> Tuple[CubicBezier, CubicBezier]:
        """The curve cut at `t` into two, together tracing exactly the
        original: the first runs `start` to `at(t)`, the second `at(t)` to
        `end` (de Casteljau)."""
        var p01 = self.start.lerp(self.control1, t)
        var p12 = self.control1.lerp(self.control2, t)
        var p23 = self.control2.lerp(self.end, t)
        var p012 = p01.lerp(p12, t)
        var p123 = p12.lerp(p23, t)
        var mid = p012.lerp(p123, t)
        return (
            CubicBezier(self.start, p01, p012, mid),
            CubicBezier(mid, p123, p23, self.end),
        )

    def bounds(self) -> Rectangle:
        """The tightest axis-aligned rectangle around the curve — around
        the curve itself, not its control points, which usually reach
        further."""
        var xs = _axis_extremes(
            self.start.x, self.control1.x, self.control2.x, self.end.x
        )
        var ys = _axis_extremes(
            self.start.y, self.control1.y, self.control2.y, self.end.y
        )
        return Rectangle(
            Point2D((xs[0] + xs[1]) / 2.0, (ys[0] + ys[1]) / 2.0),
            xs[1] - xs[0],
            ys[1] - ys[0],
        )

    def flatten(self, tolerance: Float64) -> List[Point2D]:
        """Points along the curve, from `start` to `end` inclusive, such that
        the straight segments between them stray from the curve by at most
        `tolerance`.

        The points are evenly spaced in `t`, with the count from Wang's
        formula, and capped at 1024 segments. A curve collapsed to one point
        still gives two points.
        """
        var d1 = (self.start - self.control1) + (self.control2 - self.control1)
        var d2 = (self.control1 - self.control2) + (self.end - self.control2)
        var m = max(d1.mag(), d2.mag())
        var n = 1
        if tolerance > 0.0 and m > 0.0:
            n = Int(ceil(sqrt(0.75 * m / tolerance)))
            n = max(1, min(n, _MAX_FLATTEN_SEGMENTS))
        var points = List[Point2D](capacity=n + 1)
        points.append(self.start)
        for i in range(1, n):
            points.append(self.at(Float64(i) / Float64(n)))
        points.append(self.end)
        return points^

    def length(self) -> Float64:
        """The distance along the curve from `start` to `end`.

        Gauss–Legendre quadrature (8 points on each of 16 equal steps in
        `t`) of the curve's speed — accurate to far below a pixel for any
        curve that fits on a screen, but an approximation, not exact.
        """
        return self._length_to(1.0)

    def at_distance(self, distance: Float64) -> Point2D:
        """The point `distance` along the curve from `start`, clamped to
        the curve's ends.

        Unlike `at`, equal steps in `distance` are equal steps along the
        curve, so this is what moves something along it at a steady speed.
        Each call inverts `length` numerically; sample once per frame per
        entity, not in a tight loop.
        """
        var total = self.length()
        if distance <= 0.0 or total == 0.0:
            return self.start
        if distance >= total:
            return self.end
        # Newton's method on `_length_to(t) - distance`, kept inside a
        # bracket that bisection falls back to where the speed is too low
        # for a Newton step to be trusted.
        var lo = 0.0
        var hi = 1.0
        var t = distance / total
        for _ in range(_MAX_DISTANCE_ITERATIONS):
            var error = self._length_to(t) - distance
            if abs(error) <= total * 1e-12:
                break
            if error > 0.0:
                hi = t
            else:
                lo = t
            var next = (lo + hi) / 2.0
            var speed = self.tangent(t).mag()
            if speed > 0.0:
                var newton = t - error / speed
                if newton > lo and newton < hi:
                    next = newton
            t = next
        return self.at(t)

    def _length_to(self, t: Float64) -> Float64:
        """Arc length from `start` to the point at `t`, for `t` in 0..1."""
        var step = t / Float64(_LENGTH_STEPS)
        var half = step / 2.0
        var nodes = materialize[_GAUSS_NODES]()
        var weights = materialize[_GAUSS_WEIGHTS]()
        var total = 0.0
        for i in range(_LENGTH_STEPS):
            var centre = (Float64(i) + 0.5) * step
            for k in range(4):
                var node = nodes[k] * half
                total += weights[k] * (
                    self.tangent(centre - node).mag()
                    + self.tangent(centre + node).mag()
                )
        return total * half

    def translate(mut self, delta: Vector2D):
        self.start = self.start + delta
        self.control1 = self.control1 + delta
        self.control2 = self.control2 + delta
        self.end = self.end + delta
