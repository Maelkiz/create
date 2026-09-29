from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import abs, pi
from create.math.bezier import Bezier
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _s_curve() -> Bezier:
    return Bezier((0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0))


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _distance_to_segment(p: Point2D, a: Point2D, b: Point2D) -> Float64:
    var ab = b - a
    var len_sq = ab.mag_sq()
    if len_sq == 0.0:
        return p.dist(a)
    var t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    return p.dist(a + ab * t)


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
    var quarter = pi * 100.0 / 2.0
    assert_true(abs(b.length() - quarter) / quarter < 1e-3)


def test_length_matches_dense_polyline() raises -> None:
    var b = _s_curve()
    var points = b.flatten(1e-6)
    var total = 0.0
    for i in range(len(points) - 1):
        total += points[i].dist(points[i + 1])
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
        var chord = p.dist(previous)
        assert_true(chord <= step + 1e-6)
        assert_true(chord >= step * 0.99)
        previous = p


def test_at_distance_on_degenerate_curve() raises -> None:
    var b = Bezier((5.0, 5.0), (5.0, 5.0), (5.0, 5.0), (5.0, 5.0))
    assert_equal(b.length(), 0.0)
    assert_equal(b.at_distance(1.0), Point2D(5.0, 5.0))


def test_translate_moves_every_point() raises -> None:
    var b = _s_curve()
    b.translate(Vector2D(10.0, -5.0))
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
