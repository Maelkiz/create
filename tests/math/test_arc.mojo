from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import abs, ceil, pi, tau
from create.math.geometry import Arc, Circle, Line, Rectangle, Triangle
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def test_prints_in_keyword_form() raises -> None:
    assert_equal(
        String(Arc((1.0, 2.0), 10, 0.5, -1.5)),
        (
            "Arc(position=Point2D(1.0, 2.0), r=10.0, start_angle=0.5,"
            " sweep_angle=-1.5)"
        ),
    )


def test_equality_keeps_the_sweep_as_given() raises -> None:
    # Two spellings of the same points are still two different arcs: the
    # fields are what was written, not a normal form.
    assert_true(Arc((0, 0), 5, 0.0, 1.0) == Arc((0, 0), 5, 0.0, 1.0))
    assert_true(Arc((0, 0), 5, 0.0, 1.0) != Arc((0, 0), 5, 1.0, -1.0))


def test_end_angle() raises -> None:
    assert_almost_equal(Arc((0, 0), 5, 1.0, -0.25).end_angle(), 0.75)


def test_at_runs_counter_clockwise_for_a_positive_sweep() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(a.at(0.0), Point2D(10.0, 0.0))
    _assert_point_near(a.at(1.0), Point2D(0.0, 10.0))


def test_at_runs_clockwise_for_a_negative_sweep() raises -> None:
    var a = Arc((0, 0), 10, 0.0, -pi / 2.0)
    _assert_point_near(a.at(1.0), Point2D(0.0, -10.0))
    assert_true(a.at(0.5).y < 0.0)


def test_sweep_past_a_turn_is_a_full_circle() raises -> None:
    var a = Arc((0, 0), 1, 0.0, 3.0 * tau)
    assert_almost_equal(a.length(), tau)
    _assert_point_near(a.at(0.5), Point2D(-1.0, 0.0))


def test_length() raises -> None:
    assert_almost_equal(Arc((5, 5), 4, 1.0, -pi).length(), 4.0 * pi)


def test_tangent_is_constant_speed_along_travel() raises -> None:
    var a = Arc((0, 0), 10, 0.0, -pi)
    for i in range(5):
        var t = Float64(i) / 4.0
        assert_almost_equal(a.tangent(t).mag(), a.length(), atol=1e-9)
    # Clockwise from (10, 0): heading straight down.
    _assert_point_near(
        Point2D(0, 0) + a.tangent(0.0).normalize(), Point2D(0.0, -1.0)
    )


def test_at_distance_is_exact_and_clamped() raises -> None:
    var a = Arc((0, 0), 2, 0.0, pi)
    _assert_point_near(a.at_distance(pi), Point2D(0.0, 2.0))
    _assert_point_near(a.at_distance(-1.0), a.at(0.0))
    _assert_point_near(a.at_distance(100.0), a.at(1.0))


def test_bounds_widen_to_extremes_passed() raises -> None:
    # From 45° to 135°: passes the top of the circle, not the sides.
    var b = Arc((0, 0), 10, pi / 4.0, pi / 2.0).bounds()
    assert_almost_equal(b.top(), 10.0)
    assert_almost_equal(b.left(), -10.0 / 2.0**0.5)
    assert_almost_equal(b.right(), 10.0 / 2.0**0.5)
    assert_almost_equal(b.bottom(), 10.0 / 2.0**0.5)


def test_bounds_of_a_clockwise_sweep_across_the_x_axis() raises -> None:
    var b = Arc((0, 0), 10, pi / 4.0, -pi / 2.0).bounds()
    assert_almost_equal(b.right(), 10.0)
    assert_almost_equal(b.top(), 10.0 / 2.0**0.5)
    assert_almost_equal(b.bottom(), -10.0 / 2.0**0.5)


def test_bounds_of_a_full_circle() raises -> None:
    var b = Arc((1, 2), 3, 0.3, tau).bounds()
    assert_almost_equal(b.w, 6.0)
    assert_almost_equal(b.h, 6.0)
    _assert_point_near(b.center(), Point2D(1.0, 2.0))


def test_flatten_stays_within_tolerance() raises -> None:
    var a = Arc((0, 0), 100, 0.2, 2.5)
    var points = a.flatten(0.25)
    _assert_point_near(points[0], a.at(0.0))
    _assert_point_near(points[len(points) - 1], a.at(1.0))
    for i in range(len(points) - 1):
        var mid = points[i].lerp(points[i + 1], 0.5)
        assert_true(100.0 - mid.dist(Point2D(0, 0)) <= 0.25 + 1e-9)


def test_flatten_of_a_collapsed_arc_gives_two_points() raises -> None:
    assert_equal(len(Arc((0, 0), 5, 1.0, 0.0).flatten(0.25)), 2)


def test_beziers_hug_the_circle() raises -> None:
    var a = Arc((3, -2), 1000, 0.1, -4.0)
    var curves = a.beziers()
    assert_equal(len(curves), Int(ceil(4.0 / (pi / 4.0))))
    for c in curves:
        for i in range(11):
            var d = c.at(Float64(i) / 10.0).dist(a.position)
            assert_true(abs(d - 1000.0) <= 1e-5 * 1000.0)


def test_beziers_join_end_to_end() raises -> None:
    var a = Arc((0, 0), 10, 0.0, 2.0)
    var curves = a.beziers()
    _assert_point_near(curves[0].start, a.at(0.0))
    _assert_point_near(curves[len(curves) - 1].end, a.at(1.0))
    for i in range(len(curves) - 1):
        assert_equal(curves[i].end, curves[i + 1].start)


def test_beziers_of_a_full_circle_close_exactly() raises -> None:
    var curves = Arc((0, 0), 10, 0.7, -tau).beziers()
    assert_equal(len(curves), 8)
    assert_equal(curves[len(curves) - 1].end, curves[0].start)


def test_beziers_of_a_collapsed_arc_are_none() raises -> None:
    assert_equal(len(Arc((0, 0), 0, 0.0, 1.0).beziers()), 0)
    assert_equal(len(Arc((0, 0), 5, 0.0, 0.0).beziers()), 0)


def test_closest_point_within_the_sweep_is_radial() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    _assert_point_near(a.closest_point((0.0, 3.0)), Point2D(0.0, 10.0))
    _assert_point_near(a.closest_point((0.0, 30.0)), Point2D(0.0, 10.0))


def test_closest_point_outside_the_sweep_is_the_nearer_end() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(a.closest_point((5.0, -20.0)), Point2D(10.0, 0.0))
    _assert_point_near(a.closest_point((-20.0, 5.0)), Point2D(0.0, 10.0))


def test_closest_point_from_the_centre_is_the_start() raises -> None:
    var a = Arc((1, 1), 10, pi, 1.0)
    _assert_point_near(a.closest_point((1.0, 1.0)), a.at(0.0))


def test_closest_point_on_an_edge_direction() raises -> None:
    # Straight out along the end edge: within the sweep despite `cos`/`sin`
    # rounding the edge direction.
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(a.closest_point((0.0, 4.0)), Point2D(0.0, 10.0))


def test_zero_radius_is_the_centre() raises -> None:
    var a = Arc((4, 5), 0, 0.0, pi)
    _assert_point_near(a.at(0.5), Point2D(4.0, 5.0))
    _assert_point_near(a.closest_point((100.0, 0.0)), Point2D(4.0, 5.0))
    assert_equal(a.length(), 0.0)


def test_move_to_and_translate_move_the_centre() raises -> None:
    var a = Arc((0, 0), 5, 0.0, 1.0)
    a.move_to((3.0, 4.0))
    assert_equal(a.position, Point2D(3.0, 4.0))
    a.translate(Vector2D(1.0, -1.0))
    assert_equal(a.position, Point2D(4.0, 3.0))


def _assert_meets(a: Arc, l: Line, expected: Bool) raises:
    assert_equal(a.intersects(l), expected)
    assert_equal(l.intersects(a), expected)


def test_intersects_point_on_the_arc() raises -> None:
    var a = Arc((1, 2), 10, 0.3, 2.0)
    assert_true(a.intersects(a.at(0.0)))
    assert_true(a.intersects(a.at(0.37)))
    assert_true(a.intersects(a.at(1.0)))


def test_intersects_point_off_the_arc() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    assert_true(not a.intersects(Point2D(0.0, 0.0)))
    assert_true(not a.intersects(Point2D(10.001, 0.0)))
    # On the circle, but outside the sweep.
    assert_true(not a.intersects(Point2D(0.0, -10.0)))


def test_intersects_line_crossing_once_and_twice() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    _assert_meets(a, Line((0, 0), (0, 20)), True)
    _assert_meets(a, Line((-20, 5), (20, 5)), True)


def test_intersects_line_only_where_it_crosses_the_sweep() raises -> None:
    # The upper half: a chord below the centre crosses only the missing half.
    var a = Arc((0, 0), 10, 0.0, pi)
    _assert_meets(a, Line((-20, -5), (20, -5)), False)
    # Clockwise from +x down to -x: the lower half, which the chord crosses.
    _assert_meets(Arc((0, 0), 10, 0.0, -pi), Line((-20, -5), (20, -5)), True)


def test_intersects_line_short_of_or_inside_the_circle() raises -> None:
    var a = Arc((0, 0), 10, 0.0, tau)
    _assert_meets(a, Line((-3, 0), (3, 0)), False)
    _assert_meets(a, Line((11, 0), (20, 0)), False)
    _assert_meets(a, Line((-20, 11), (20, 11)), False)


def test_intersects_tangent_line() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    _assert_meets(a, Line((-5, 10), (5, 10)), True)
    _assert_meets(a, Line((-5, -10), (5, -10)), False)


def test_intersects_line_ending_on_the_arc() raises -> None:
    var a = Arc((3, -2), 7, 0.4, 1.9)
    _assert_meets(a, Line(a.at(0.6), a.at(0.6) + Vector2D(50, 50)), True)
    _assert_meets(a, Line(a.at(1.0), a.position), True)


def test_intersects_line_along_a_radius() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    _assert_meets(a, Line((0, 0), (0, 10)), True)
    _assert_meets(a, Line((0, 0), (0, -10)), False)


def test_intersects_degenerate_line() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    _assert_meets(a, Line((0, 10), (0, 10)), True)
    _assert_meets(a, Line((0, 5), (0, 5)), False)


def test_intersects_crossing_arcs() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    assert_true(a.intersects(Arc((10, 0), 10, pi / 2.0, pi)))
    # The same circles cross at (5, ±8.66); a lower arc misses the upper one.
    assert_true(not a.intersects(Arc((10, 0), 10, pi, pi / 2.0)))
    assert_true(Arc((10, 0), 10, pi / 2.0, pi).intersects(a))


def test_intersects_tangent_arcs() raises -> None:
    var a = Arc((0, 0), 10, -1.0, 2.0)
    assert_true(a.intersects(Arc((20, 0), 10, pi - 1.0, 2.0)))
    # Internally tangent at (10, 0).
    assert_true(a.intersects(Arc((5, 0), 5, -1.0, 2.0)))


def test_intersects_disjoint_and_nested_circles() raises -> None:
    var a = Arc((0, 0), 10, 0.0, tau)
    assert_true(not a.intersects(Arc((30, 0), 5, 0.0, tau)))
    assert_true(not a.intersects(Arc((1, 0), 5, 0.0, tau)))


def test_intersects_concentric_arcs() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi / 2.0)
    assert_true(a.intersects(Arc((0, 0), 10, 1.0, 2.0)))
    assert_true(a.intersects(Arc((0, 0), 10, pi / 2.0, pi / 2.0)))
    assert_true(not a.intersects(Arc((0, 0), 10, pi, pi / 2.0)))
    assert_true(not a.intersects(Arc((0, 0), 5, 0.0, pi / 2.0)))


def test_intersects_arc_holding_the_other_within_its_sweep() raises -> None:
    # One concentric arc wholly within the other's sweep.
    var a = Arc((0, 0), 10, 0.0, pi)
    assert_true(a.intersects(Arc((0, 0), 10, 1.0, 0.5)))
    assert_true(Arc((0, 0), 10, 1.0, 0.5).intersects(a))


def test_intersects_circle() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    assert_true(a.intersects(Circle((0, 12), 2)))
    assert_true(a.intersects(Circle((0, 10), 1)))
    assert_true(a.intersects(Circle((0, 0), 20)))
    assert_true(not a.intersects(Circle((0, 0), 5)))
    assert_true(not a.intersects(Circle((0, -10), 1)))


def test_intersects_rectangle() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    assert_true(a.intersects(Rectangle((0, 10), 4, 4)))
    assert_true(a.intersects(Rectangle((0, 0), 100, 100)))
    assert_true(a.intersects(Rectangle((0, 15), 40, 10)))
    assert_true(not a.intersects(Rectangle((0, 0), 4, 4)))
    assert_true(not a.intersects(Rectangle((0, -10), 4, 4)))


def test_intersects_triangle() raises -> None:
    var a = Arc((0, 0), 10, 0.0, pi)
    assert_true(a.intersects(Triangle((-2, 8), (2, 8), (0, 12))))
    assert_true(a.intersects(Triangle((-50, -1), (50, -1), (0, 50))))
    assert_true(not a.intersects(Triangle((-2, 0), (2, 0), (0, 2))))
    assert_true(not a.intersects(Triangle((-2, -8), (2, -8), (0, -12))))


def test_intersects_collapsed_arcs() raises -> None:
    var point = Arc((0, 10), 0, 0.0, 1.0)
    _assert_meets(point, Line((-5, 10), (5, 10)), True)
    _assert_meets(point, Line((-5, 11), (5, 11)), False)
    assert_true(Arc((0, 0), 10, 0.0, pi).intersects(point))
    assert_true(point.intersects(Arc((0, 0), 10, 0.0, pi)))
    var no_sweep = Arc((0, 0), 10, pi / 2.0, 0.0)
    _assert_meets(no_sweep, Line((-5, 10), (5, 10)), True)
    _assert_meets(no_sweep, Line((1, 0), (1, 20)), False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
