from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_almost_equal,
)
from std.math import abs
from create.math import PI
from create.geometry.bezier import Bezier
from create.geometry.geometry import (
    Arc,
    Circle,
    Line,
    Polygon,
    Rectangle,
    Sector,
    Triangle,
)
from create.geometry.spline import Spline
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _s_curve() -> Bezier:
    return Bezier((0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0))


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _distance_to_segment(p: Point2D, a: Point2D, b: Point2D) -> Float64:
    var ab = b - a
    var len_sq = ab.magnitude_squared()
    if len_sq == 0.0:
        return p.distance(a)
    var t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    return p.distance(a + ab * t)


def test_at_endpoints() raises -> None:
    var b = _s_curve()
    assert_equal(b.at(0.0), b.start)
    assert_equal(b.at(1.0), b.end)


def test_at_straight_curve_is_collinear() raises -> None:
    var b = Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 6.0), (4.0, 8.0))
    for i in range(11):
        var p = b.at(Float64(i) / 10.0)
        assert_almost_equal(p.y, 2.0 * p.x, atol=1e-12)


def test_at_extrapolates() raises -> None:
    # A straight, evenly spaced curve is linear in t, so t = 2 is twice as far.
    var b = Bezier((0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0))
    _assert_point_near(b.at(2.0), Point2D(6.0, 0.0))


def test_tangent_at_ends_points_at_controls() raises -> None:
    var b = _s_curve()
    assert_equal(b.tangent(0.0), (b.control1 - b.start) * 3.0)
    assert_equal(b.tangent(1.0), (b.end - b.control2) * 3.0)


def test_tangent_matches_finite_difference() raises -> None:
    var b = _s_curve()
    var h = 1e-6
    for i in range(1, 10):
        var t = Float64(i) / 10.0
        var numeric = (b.at(t + h) - b.at(t - h)) / (2.0 * h)
        var analytic = b.tangent(t)
        assert_almost_equal(analytic.x, numeric.x, atol=1e-4)
        assert_almost_equal(analytic.y, numeric.y, atol=1e-4)


def test_split_halves_meet_at_the_split_point() raises -> None:
    var b = _s_curve()
    var halves = b.split(0.3)
    assert_equal(halves[0].start, b.start)
    assert_equal(halves[1].end, b.end)
    _assert_point_near(halves[0].end, b.at(0.3))
    assert_equal(halves[0].end, halves[1].start)


def test_split_halves_trace_the_original() raises -> None:
    var b = _s_curve()
    var t = 0.3
    var halves = b.split(t)
    for i in range(11):
        var u = Float64(i) / 10.0
        _assert_point_near(halves[0].at(u), b.at(u * t))
        _assert_point_near(halves[1].at(u), b.at(t + u * (1.0 - t)))


def test_bounds_contains_every_sample() raises -> None:
    var b = _s_curve()
    var r = b.bounds()
    for i in range(101):
        var p = b.at(Float64(i) / 100.0)
        assert_true(p.x >= r.left() - 1e-9 and p.x <= r.right() + 1e-9)
        assert_true(p.y >= r.bottom() - 1e-9 and p.y <= r.top() + 1e-9)


def test_bounds_is_tighter_than_control_points() raises -> None:
    # The controls reach y = 100; the curve itself peaks at y = 75.
    var r = _s_curve().bounds()
    assert_almost_equal(r.bottom(), 0.0, atol=1e-9)
    assert_almost_equal(r.top(), 75.0, atol=1e-9)
    assert_almost_equal(r.left(), 0.0, atol=1e-9)
    assert_almost_equal(r.right(), 100.0, atol=1e-9)


def test_bounds_touches_the_extremes() raises -> None:
    # Tight: some sample reaches each edge to within the sample spacing.
    var b = Bezier((0.0, 0.0), (-40.0, 80.0), (120.0, -30.0), (60.0, 20.0))
    var r = b.bounds()
    var lo_x = 1e9
    var hi_x = -1e9
    var lo_y = 1e9
    var hi_y = -1e9
    for i in range(10001):
        var p = b.at(Float64(i) / 10000.0)
        lo_x = min(lo_x, p.x)
        hi_x = max(hi_x, p.x)
        lo_y = min(lo_y, p.y)
        hi_y = max(hi_y, p.y)
    assert_almost_equal(r.left(), lo_x, atol=1e-3)
    assert_almost_equal(r.right(), hi_x, atol=1e-3)
    assert_almost_equal(r.bottom(), lo_y, atol=1e-3)
    assert_almost_equal(r.top(), hi_y, atol=1e-3)


def test_flatten_keeps_endpoints_and_lies_on_the_curve() raises -> None:
    var b = _s_curve()
    var points = b.flatten(0.25)
    assert_equal(points[0], b.start)
    assert_equal(points[len(points) - 1], b.end)
    var n = len(points) - 1
    for i in range(len(points)):
        _assert_point_near(points[i], b.at(Float64(i) / Float64(n)))


def test_flatten_refines_as_tolerance_shrinks() raises -> None:
    var b = _s_curve()
    assert_true(len(b.flatten(0.01)) > len(b.flatten(1.0)))


def test_flatten_stays_within_tolerance() raises -> None:
    var b = _s_curve()
    for tol in [1.0, 0.25, 0.05]:
        var points = b.flatten(tol)
        var n = len(points) - 1
        for i in range(n):
            # Probe the curve between each pair of neighbouring points.
            for k in range(1, 8):
                var t = (Float64(i) + Float64(k) / 8.0) / Float64(n)
                var gap = _distance_to_segment(
                    b.at(t), points[i], points[i + 1]
                )
                assert_true(gap <= tol)


def test_flatten_segment_count_is_capped() raises -> None:
    var b = Bezier((0.0, 0.0), (1e9, 1e9), (-1e9, 1e9), (0.0, 0.0))
    assert_equal(len(b.flatten(1e-9)), 1025)


def test_flatten_degenerate_curve() raises -> None:
    var b = Bezier((5.0, 5.0), (5.0, 5.0), (5.0, 5.0), (5.0, 5.0))
    var points = b.flatten(0.25)
    assert_equal(len(points), 2)
    assert_equal(points[0], Point2D(5.0, 5.0))
    assert_equal(points[1], Point2D(5.0, 5.0))


def test_length_of_straight_curve() raises -> None:
    # Unevenly spaced controls: t is not proportional to distance, but the
    # length is still the endpoint distance.
    var b = Bezier((0.0, 0.0), (0.5, 0.0), (1.0, 0.0), (10.0, 0.0))
    assert_almost_equal(b.length(), 10.0, atol=1e-9)


def test_length_of_quarter_circle() raises -> None:
    # The standard four-arc circle approximation, radius 100.
    var k = 0.5522847498 * 100.0
    var b = Bezier((100.0, 0.0), (100.0, k), (k, 100.0), (0.0, 100.0))
    var quarter = PI * 100.0 / 2.0
    assert_true(abs(b.length() - quarter) / quarter < 1e-3)


def test_length_matches_dense_polyline() raises -> None:
    var b = _s_curve()
    var points = b.flatten(1e-6)
    var total = 0.0
    for i in range(len(points) - 1):
        total += points[i].distance(points[i + 1])
    assert_almost_equal(b.length(), total, atol=1e-3)


def test_at_distance_ends() raises -> None:
    var b = _s_curve()
    assert_equal(b.at_distance(0.0), b.start)
    _assert_point_near(b.at_distance(b.length()), b.end, 1e-6)


def test_at_distance_clamps() raises -> None:
    var b = _s_curve()
    assert_equal(b.at_distance(-5.0), b.start)
    assert_equal(b.at_distance(b.length() + 5.0), b.end)


def test_at_distance_steps_evenly() raises -> None:
    # Controls bunched at the start make `at` uneven in t; `at_distance`
    # must not be.
    var b = Bezier((0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (300.0, 200.0))
    var n = 50
    var step = b.length() / Float64(n)
    var previous = b.at_distance(0.0)
    for i in range(1, n + 1):
        var p = b.at_distance(Float64(i) * step)
        # A chord is at most the arc it spans, and only just shorter here.
        var chord = p.distance(previous)
        assert_true(chord <= step + 1e-6)
        assert_true(chord >= step * 0.99)
        previous = p


def test_at_distance_on_degenerate_curve() raises -> None:
    var b = Bezier((5.0, 5.0), (5.0, 5.0), (5.0, 5.0), (5.0, 5.0))
    assert_equal(b.length(), 0.0)
    assert_equal(b.at_distance(1.0), Point2D(5.0, 5.0))


def test_beziers_is_itself() raises -> None:
    var b = Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 2.0), (4.0, 0.0))
    var curves = b.beziers()
    assert_equal(len(curves), 1)
    assert_equal(curves[0], b)


def _brute_closest(b: Bezier, p: Point2D) -> Point2D:
    var best = b.start
    for i in range(10001):
        var q = b.at(Float64(i) / 10000.0)
        if q.distance_squared(p) < best.distance_squared(p):
            best = q
    return best


def test_closest_point_on_the_curve_is_itself() raises -> None:
    var b = Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 2.0), (4.0, 0.0))
    var on = b.at(0.3)
    var q = b.closest_point(on)
    assert_almost_equal(q.x, on.x, atol=1e-9)
    assert_almost_equal(q.y, on.y, atol=1e-9)


def test_closest_point_past_an_end_is_that_end() raises -> None:
    var b = Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 2.0), (4.0, 0.0))
    assert_equal(b.closest_point((-5.0, -1.0)), b.start)
    assert_equal(b.closest_point((9.0, -1.0)), b.end)


def test_closest_point_matches_brute_force() raises -> None:
    var curves: List[Bezier] = [
        Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 2.0), (4.0, 0.0)),
        # An S-bend, with two dips in distance from points between.
        Bezier((0.0, 0.0), (6.0, 4.0), (-2.0, 4.0), (4.0, 0.0)),
        # A loop.
        Bezier((0.0, 0.0), (5.0, 5.0), (-1.0, 5.0), (4.0, 0.0)),
    ]
    var points: List[Point2D] = [
        (2.0, 1.0),
        (2.0, 3.0),
        (0.5, 2.5),
        (-1.0, 4.0),
        (3.0, -2.0),
    ]
    for c in curves:
        for p in points:
            var q = c.closest_point(p)
            var expected = _brute_closest(c, p)
            assert_almost_equal(q.distance(p), expected.distance(p), atol=1e-6)


def test_closest_point_on_a_collapsed_curve() raises -> None:
    var b = Bezier((1.0, 1.0), (1.0, 1.0), (1.0, 1.0), (1.0, 1.0))
    assert_equal(b.closest_point((5.0, 5.0)), Point2D(1.0, 1.0))


def _hump() -> Bezier:
    # Rises from (0, 0) to a peak of y = 3 at x = 2, back down at (4, 0).
    return Bezier((0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 0.0))


def test_intersects_a_point_on_it_and_not_off_it() raises -> None:
    var b = _hump()
    assert_true(b.intersects(b.at(0.37)))
    assert_true(b.intersects(b.start))
    assert_false(b.intersects(Point2D(2.0, 2.0)))


def test_intersects_a_line_crossing_its_bulge() raises -> None:
    var b = _hump()
    # Runs across the hump at y = 2, crossing it twice.
    var across = Line((-1.0, 2.0), (5.0, 2.0))
    assert_true(b.intersects(across))
    assert_true(across.intersects(b))


def test_intersects_a_line_under_its_bulge_only_if_it_reaches() raises -> None:
    var b = _hump()
    # Wholly inside the hump, touching nothing.
    var inside = Line((1.0, 1.0), (3.0, 1.0))
    assert_false(b.intersects(inside))
    assert_false(inside.intersects(b))
    # Just over the peak.
    var over = Line((0.0, 3.01), (4.0, 3.01))
    assert_false(b.intersects(over))
    # Just under the peak, past the flattening tolerance (4e-4 here).
    var under_peak = Line((0.0, 2.999), (4.0, 2.999))
    assert_true(b.intersects(under_peak))


def test_intersects_a_line_touching_an_end() raises -> None:
    var b = _hump()
    assert_true(b.intersects(Line((4.0, 0.0), (6.0, -1.0))))


def test_intersects_an_arc() raises -> None:
    var b = _hump()
    # A circle round the peak, radius 1, crossed by the hump.
    var crossing = Arc((2.0, 3.0), 1.0, 0.0, 2.0 * PI)
    assert_true(b.intersects(crossing))
    assert_true(crossing.intersects(b))
    var far = Arc((2.0, 10.0), 1.0, 0.0, 2.0 * PI)
    assert_false(b.intersects(far))
    assert_false(far.intersects(b))


def test_intersects_another_bezier() raises -> None:
    var b = _hump()
    var dip = Bezier((0.0, 4.0), (0.0, 0.0), (4.0, 0.0), (4.0, 4.0))
    assert_true(b.intersects(dip))
    assert_true(dip.intersects(b))
    var above = Bezier((0.0, 5.0), (0.0, 9.0), (4.0, 9.0), (4.0, 5.0))
    assert_false(b.intersects(above))
    assert_false(above.intersects(b))


def test_intersects_a_spline() raises -> None:
    var b = _hump()
    var s = Spline([Point2D(-1.0, 2.0), Point2D(2.0, 1.5), Point2D(5.0, 2.0)])
    assert_true(b.intersects(s))
    assert_true(s.intersects(b))


def test_intersects_a_circle_its_bulge_dips_into() raises -> None:
    var b = _hump()
    # Both ends are well outside; only the peak reaches in.
    var c = Circle((2.0, 3.5), 0.75)
    assert_false(c.contains(b.start) or c.contains(b.end))
    assert_true(b.intersects(c))
    assert_false(b.intersects(Circle((2.0, 4.5), 0.75)))


def test_intersects_a_region_holding_it_whole() raises -> None:
    var b = _hump()
    assert_true(b.intersects(Rectangle((2.0, 1.5), 10.0, 10.0)))
    assert_true(b.intersects(Circle((2.0, 1.5), 10.0)))


def test_intersects_a_region_crossing_its_edge() raises -> None:
    var b = _hump()
    assert_true(b.intersects(Rectangle((2.0, 3.5), 2.0, 2.0)))
    assert_true(b.intersects(Triangle((1.0, 4.0), (3.0, 4.0), (2.0, 2.0))))
    assert_true(b.intersects(Sector((2.0, 5.0), 3.0, -2.0, 1.0)))
    assert_true(b.intersects(Polygon.regular(Point2D(2.0, 4.0), 1.5, sides=5)))


def test_intersects_misses_regions_beside_it() raises -> None:
    var b = _hump()
    assert_false(b.intersects(Rectangle((2.0, 1.0), 1.0, 1.0)))
    assert_false(b.intersects(Triangle((1.0, 1.0), (3.0, 1.0), (2.0, 2.0))))
    assert_false(b.intersects(Sector((2.0, 6.0), 2.0, 0.0, PI)))
    assert_false(b.intersects(Polygon.regular(Point2D(8.0, 0.0), 1.0, sides=6)))


def test_intersects_sees_a_rounded_corner() raises -> None:
    # At t = 1/sqrt(2) the hump runs diagonally down-right, through about
    # (3.17, 2.49). The square's corner sits 0.1 inside the hump from
    # there: the sharp corner reaches over the curve, the rounded one is
    # pulled back about 0.41 along the diagonal and clears it.
    var b = _hump()
    var sharp = Rectangle((4.1, 3.414), 2.0, 2.0)
    var rounded = Rectangle((4.1, 3.414), 2.0, 2.0, corner_radius=1.0)
    assert_true(b.intersects(sharp))
    assert_false(b.intersects(rounded))


def test_translate_moves_every_point() raises -> None:
    var b = _s_curve()
    b = b.translate(Vector2D(10.0, -5.0))
    assert_equal(b.start, Point2D(10.0, -5.0))
    assert_equal(b.control1, Point2D(110.0, 95.0))
    assert_equal(b.control2, Point2D(10.0, 95.0))
    assert_equal(b.end, Point2D(110.0, -5.0))


def test_equality() raises -> None:
    assert_true(_s_curve() == _s_curve())
    var other = _s_curve()
    other.control2 = Point2D(1.0, 1.0)
    assert_true(_s_curve() != other)


def test_writes_keyword_form() raises -> None:
    var b = Bezier((0.0, 0.0), (1.0, 2.0), (3.0, 4.0), (5.0, 6.0))
    assert_equal(
        String(b),
        (
            "Bezier(start=Point2D(0.0, 0.0), control1=Point2D(1.0, 2.0),"
            " control2=Point2D(3.0, 4.0), end=Point2D(5.0, 6.0))"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
