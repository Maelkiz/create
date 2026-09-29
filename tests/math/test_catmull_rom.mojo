from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import pow
from create.math.bezier import CubicBezier
from create.math.catmull_rom import CatmullRomSpline
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _zigzag() -> List[Point2D]:
    # Unevenly spaced, so the alphas give visibly different curves.
    return [(0.0, 0.0), (10.0, 40.0), (15.0, 38.0), (80.0, -20.0), (90.0, 30.0)]


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _blend(a: Point2D, b: Point2D, wa: Float64, wb: Float64) -> Point2D:
    return Point2D(a.x * wa + b.x * wb, a.y * wa + b.y * wb)


def _barry_goldman(
    p0: Point2D,
    p1: Point2D,
    p2: Point2D,
    p3: Point2D,
    alpha: Float64,
    u: Float64,
) -> Point2D:
    """The Catmull-Rom point a fraction `u` of the way from `p1` to `p2`,
    straight from the pyramid of interpolations, as the reference the Bézier
    conversion must reproduce."""
    var t0 = 0.0
    var t1 = t0 + pow((p1 - p0).mag(), alpha)
    var t2 = t1 + pow((p2 - p1).mag(), alpha)
    var t3 = t2 + pow((p3 - p2).mag(), alpha)
    var t = t1 + u * (t2 - t1)
    var a1 = _blend(p0, p1, (t1 - t) / (t1 - t0), (t - t0) / (t1 - t0))
    var a2 = _blend(p1, p2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))
    var a3 = _blend(p2, p3, (t3 - t) / (t3 - t2), (t - t2) / (t3 - t2))
    var b1 = _blend(a1, a2, (t2 - t) / (t2 - t0), (t - t0) / (t2 - t0))
    var b2 = _blend(a2, a3, (t3 - t) / (t3 - t1), (t - t1) / (t3 - t1))
    return _blend(b1, b2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1))


def _uniform(
    p0: Point2D, p1: Point2D, p2: Point2D, p3: Point2D, u: Float64
) -> Point2D:
    """The textbook uniform Catmull-Rom matrix form."""
    var u2 = u * u
    var u3 = u2 * u
    var x = 0.5 * (
        2.0 * p1.x
        + (-p0.x + p2.x) * u
        + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * u2
        + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * u3
    )
    var y = 0.5 * (
        2.0 * p1.y
        + (-p0.y + p2.y) * u
        + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * u2
        + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * u3
    )
    return Point2D(x, y)


def test_open_segments_run_between_neighbouring_points() raises -> None:
    var points = _zigzag()
    var curves = CatmullRomSpline(points.copy()).beziers()
    assert_equal(len(curves), len(points) - 1)
    for i in range(len(curves)):
        assert_equal(curves[i].start, points[i])
        assert_equal(curves[i].end, points[i + 1])


def test_closed_spline_returns_to_the_first_point() raises -> None:
    var points = _zigzag()
    var curves = CatmullRomSpline(points.copy(), closed=True).beziers()
    assert_equal(len(curves), len(points))
    assert_equal(curves[len(curves) - 1].start, points[len(points) - 1])
    assert_equal(curves[len(curves) - 1].end, points[0])


def test_alpha_zero_is_uniform_catmull_rom() raises -> None:
    var p = _zigzag()
    var curves = CatmullRomSpline(p.copy(), alpha=0.0).beziers()
    # The interior stretches, whose four points are all real.
    for i in range(1, len(p) - 2):
        for k in range(11):
            var u = Float64(k) / 10.0
            _assert_point_near(
                curves[i].at(u), _uniform(p[i - 1], p[i], p[i + 1], p[i + 2], u)
            )


def test_matches_barry_goldman_for_each_alpha() raises -> None:
    var p = _zigzag()
    for alpha in [0.0, 0.5, 1.0]:
        var curves = CatmullRomSpline(p.copy(), alpha=alpha).beziers()
        for i in range(1, len(p) - 2):
            for k in range(11):
                var u = Float64(k) / 10.0
                _assert_point_near(
                    curves[i].at(u),
                    _barry_goldman(
                        p[i - 1], p[i], p[i + 1], p[i + 2], alpha, u
                    ),
                )


def test_open_ends_mirror_their_neighbour() raises -> None:
    var p = _zigzag()
    var curves = CatmullRomSpline(p.copy()).beziers()
    var first = p[0] + (p[0] - p[1])
    var n = len(p)
    var last = p[n - 1] + (p[n - 1] - p[n - 2])
    for k in range(11):
        var u = Float64(k) / 10.0
        _assert_point_near(
            curves[0].at(u), _barry_goldman(first, p[0], p[1], p[2], 0.5, u)
        )
        _assert_point_near(
            curves[n - 2].at(u),
            _barry_goldman(p[n - 3], p[n - 2], p[n - 1], last, 0.5, u),
        )


def test_tangent_direction_is_continuous_at_joints() raises -> None:
    for closed in [False, True]:
        var curves = CatmullRomSpline(_zigzag(), closed=closed).beziers()
        var joints = len(curves) if closed else len(curves) - 1
        for i in range(joints):
            var arriving = curves[i].tangent(1.0).normalize()
            var leaving = curves[(i + 1) % len(curves)].tangent(0.0).normalize()
            assert_almost_equal(arriving.x, leaving.x, atol=1e-9)
            assert_almost_equal(arriving.y, leaving.y, atol=1e-9)


def test_too_few_points_give_no_curves() raises -> None:
    assert_equal(len(CatmullRomSpline(List[Point2D]()).beziers()), 0)
    assert_equal(len(CatmullRomSpline([(1.0, 2.0)]).beziers()), 0)
    assert_equal(
        len(CatmullRomSpline([(1.0, 2.0), (1.0, 2.0)], closed=True).beziers()),
        0,
    )


def test_two_points_give_a_straight_segment() raises -> None:
    var curves = CatmullRomSpline([(0.0, 0.0), (30.0, 60.0)]).beziers()
    assert_equal(len(curves), 1)
    for k in range(11):
        var p = curves[0].at(Float64(k) / 10.0)
        assert_almost_equal(p.y, 2.0 * p.x, atol=1e-9)


def test_repeated_points_are_skipped() raises -> None:
    var curves = CatmullRomSpline(
        [(0.0, 0.0), (0.0, 0.0), (10.0, 5.0), (10.0, 5.0), (20.0, 0.0)]
    ).beziers()
    assert_equal(len(curves), 2)
    for c in curves:
        for k in range(11):
            var p = c.at(Float64(k) / 10.0)
            assert_true(p.x == p.x and p.y == p.y)  # no NaN


def test_closed_drops_a_last_point_repeating_the_first() raises -> None:
    var p = _zigzag()
    var looped = p.copy()
    looped.append(p[0])
    assert_equal(len(CatmullRomSpline(looped^, closed=True).beziers()), len(p))


def test_at_passes_through_every_point() raises -> None:
    var p = _zigzag()
    var open = CatmullRomSpline(p.copy())
    var n = len(p)
    for k in range(n):
        _assert_point_near(open.at(Float64(k) / Float64(n - 1)), p[k])
    var closed = CatmullRomSpline(p.copy(), closed=True)
    for k in range(n):
        _assert_point_near(closed.at(Float64(k) / Float64(n)), p[k])
    _assert_point_near(closed.at(1.0), p[0])


def test_at_clamps() raises -> None:
    var s = CatmullRomSpline(_zigzag())
    assert_equal(s.at(-1.0), s.at(0.0))
    assert_equal(s.at(2.0), s.at(1.0))


def test_tangent_scales_with_the_share_of_t() raises -> None:
    var s = CatmullRomSpline(_zigzag())
    var curves = s.beziers()
    var t = 0.3
    var scaled = t * Float64(len(curves))
    var i = Int(scaled)
    var expected = curves[i].tangent(scaled - Float64(i)) * Float64(len(curves))
    var got = s.tangent(t)
    assert_almost_equal(got.x, expected.x, atol=1e-9)
    assert_almost_equal(got.y, expected.y, atol=1e-9)


def test_length_sums_the_stretches() raises -> None:
    var s = CatmullRomSpline(_zigzag(), closed=True)
    var total = 0.0
    for c in s.beziers():
        total += c.length()
    assert_almost_equal(s.length(), total, atol=1e-9)


def test_evenly_spaced_collinear_points_measure_the_polyline() raises -> None:
    var s = CatmullRomSpline(
        [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0), (30.0, 0.0)]
    )
    assert_almost_equal(s.length(), 30.0, atol=1e-9)


def test_at_distance_moves_at_constant_speed() raises -> None:
    # Gentle turns, so a short chord is nearly all of its arc.
    var s = CatmullRomSpline(
        [(0.0, 0.0), (100.0, 40.0), (200.0, -30.0), (300.0, 20.0)]
    )
    var total = s.length()
    var steps = 40
    var step = total / Float64(steps)
    var previous = s.at_distance(0.0)
    for k in range(1, steps + 1):
        var p = s.at_distance(Float64(k) * step)
        # A chord is at most the arc it cuts, and nearly all of it when
        # the arc is short.
        var chord = p.dist(previous)
        assert_true(chord <= step + 1e-6)
        assert_true(chord >= step * 0.98)
        previous = p


def test_at_distance_clamps() raises -> None:
    var p = _zigzag()
    var s = CatmullRomSpline(p.copy())
    assert_equal(s.at_distance(-5.0), p[0])
    assert_equal(s.at_distance(0.0), p[0])
    _assert_point_near(s.at_distance(s.length()), p[len(p) - 1], 1e-6)
    assert_equal(s.at_distance(s.length() + 5.0), p[len(p) - 1])


def test_bounds_contain_every_point_on_the_curve() raises -> None:
    for closed in [False, True]:
        var s = CatmullRomSpline(_zigzag(), closed=closed)
        var b = s.bounds()
        var lo = Point2D(b.position.x - b.w / 2.0, b.position.y - b.h / 2.0)
        var hi = Point2D(b.position.x + b.w / 2.0, b.position.y + b.h / 2.0)
        for k in range(201):
            var p = s.at(Float64(k) / 200.0)
            assert_true(p.x >= lo.x - 1e-9 and p.x <= hi.x + 1e-9)
            assert_true(p.y >= lo.y - 1e-9 and p.y <= hi.y + 1e-9)
        for p in s.points:
            assert_true(p.x >= lo.x - 1e-9 and p.x <= hi.x + 1e-9)
            assert_true(p.y >= lo.y - 1e-9 and p.y <= hi.y + 1e-9)


def test_flatten_runs_end_to_end_without_repeats() raises -> None:
    var p = _zigzag()
    var flat = CatmullRomSpline(p.copy()).flatten(0.25)
    assert_equal(flat[0], p[0])
    assert_equal(flat[len(flat) - 1], p[len(p) - 1])
    for i in range(1, len(flat)):
        assert_true(flat[i] != flat[i - 1])
    var closed = CatmullRomSpline(p.copy(), closed=True).flatten(0.25)
    assert_equal(closed[len(closed) - 1], p[0])


def test_no_curve_sits_at_its_one_point() raises -> None:
    var one = CatmullRomSpline([(3.0, 4.0)])
    assert_equal(one.at(0.5), Point2D(3.0, 4.0))
    assert_equal(one.at_distance(1.0), Point2D(3.0, 4.0))
    assert_equal(one.length(), 0.0)
    assert_equal(len(one.flatten(0.25)), 0)
    assert_equal(one.bounds().position, Point2D(3.0, 4.0))
    var none = CatmullRomSpline(List[Point2D]())
    assert_equal(none.at(0.5), Point2D(0.0, 0.0))
    assert_equal(none.tangent(0.5), Vector2D(0.0, 0.0))


def test_translate_moves_every_point() raises -> None:
    var s = CatmullRomSpline([(0.0, 0.0), (1.0, 2.0)], alpha=0.0, closed=True)
    s.translate(Vector2D(3.0, -1.0))
    assert_true(
        s == CatmullRomSpline([(3.0, -1.0), (4.0, 1.0)], alpha=0.0, closed=True)
    )


def test_equality() raises -> None:
    var a = CatmullRomSpline([(0.0, 0.0), (1.0, 1.0)])
    assert_true(a == CatmullRomSpline([(0.0, 0.0), (1.0, 1.0)]))
    assert_true(a != CatmullRomSpline([(0.0, 0.0), (1.0, 2.0)]))
    assert_true(a != CatmullRomSpline([(0.0, 0.0), (1.0, 1.0)], alpha=1.0))
    assert_true(a != CatmullRomSpline([(0.0, 0.0), (1.0, 1.0)], closed=True))
    assert_true(a != CatmullRomSpline([(0.0, 0.0)]))


def test_write_to() raises -> None:
    assert_equal(
        String(CatmullRomSpline([(0.0, 0.0), (1.0, 2.0)])),
        (
            "CatmullRomSpline(points=[Point2D(0.0, 0.0), Point2D(1.0, 2.0)],"
            " alpha=0.5, closed=False)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
