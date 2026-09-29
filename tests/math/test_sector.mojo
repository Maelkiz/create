from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import pi, tau
from create.math.geometry import Arc, Sector
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def test_prints_in_keyword_form() raises -> None:
    assert_equal(
        String(Sector((1.0, 2.0), 10, 0.5, -1.5)),
        (
            "Sector(position=Point2D(1.0, 2.0), r=10.0, start_angle=0.5,"
            " sweep_angle=-1.5)"
        ),
    )


def test_equality() raises -> None:
    assert_true(Sector((0, 0), 5, 0.0, 1.0) == Sector((0, 0), 5, 0.0, 1.0))
    assert_true(Sector((0, 0), 5, 0.0, 1.0) != Sector((0, 0), 5, 1.0, -1.0))


def test_center_is_the_tip() raises -> None:
    var s = Sector((3, 4), 10, 0.0, pi / 2.0)
    assert_equal(s.center(), Point2D(3.0, 4.0))
    assert_almost_equal(s.end_angle(), pi / 2.0)


def test_area() raises -> None:
    assert_almost_equal(Sector((0, 0), 2, 1.0, -pi).area(), 2.0 * pi)
    # Past a full turn, the whole disc.
    assert_almost_equal(Sector((0, 0), 2, 0.0, 10.0).area(), 4.0 * pi)


def test_arc_is_the_curved_edge() raises -> None:
    assert_equal(Sector((1, 2), 3, 0.5, -1.0).arc(), Arc((1, 2), 3, 0.5, -1.0))


def test_bounds_take_in_the_tip() raises -> None:
    var b = Sector((0, 0), 10, pi / 4.0, pi / 2.0).bounds()
    assert_almost_equal(b.top(), 10.0)
    assert_almost_equal(b.bottom(), 0.0)
    assert_almost_equal(b.left(), -10.0 / 2.0**0.5)
    assert_almost_equal(b.right(), 10.0 / 2.0**0.5)


def test_contains_below_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(s.contains(Point2D(3.0, 3.0)))
    assert_true(not s.contains(Point2D(-3.0, 3.0)))
    assert_true(not s.contains(Point2D(3.0, -3.0)))
    assert_true(not s.contains(Point2D(8.0, 8.0)))
    # Directly opposite the slice: not mistaken for inside.
    assert_true(not s.contains(Point2D(-3.0, -3.0)))


def test_contains_a_clockwise_sweep() raises -> None:
    var s = Sector((0, 0), 10, 0.0, -pi / 2.0)
    assert_true(s.contains(Point2D(3.0, -3.0)))
    assert_true(not s.contains(Point2D(3.0, 3.0)))


def test_contains_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi)
    assert_true(s.contains(Point2D(0.0, 5.0)))
    assert_true(s.contains(Point2D(-5.0, 0.0)))
    assert_true(s.contains(Point2D(5.0, 0.0)))
    assert_true(not s.contains(Point2D(0.0, -0.001)))


def test_contains_just_past_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi + 0.1)
    assert_true(s.contains(Point2D(-5.0, -0.1)))
    assert_true(not s.contains(Point2D(-5.0, -1.0)))
    assert_true(not s.contains(Point2D(0.0, -5.0)))


def test_three_quarters_leave_out_one_quadrant() raises -> None:
    # From +x round to -y: all but the lower right quadrant.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(s.contains(Point2D(3.0, 3.0)))
    assert_true(s.contains(Point2D(-3.0, 3.0)))
    assert_true(s.contains(Point2D(-3.0, -3.0)))
    assert_true(not s.contains(Point2D(3.0, -3.0)))
    # Its boundary radii are inside.
    assert_true(s.contains(Point2D(5.0, 0.0)))
    assert_true(s.contains(Point2D(0.0, -5.0)))


def test_contains_the_boundary() raises -> None:
    var s = Sector((1, 2), 10, 0.3, 1.2)
    assert_true(s.contains(Point2D(1.0, 2.0)))
    assert_true(s.contains(s.arc().at(0.0)))
    assert_true(s.contains(s.arc().at(0.5)))
    assert_true(s.contains(s.arc().at(1.0)))
    assert_true(s.contains(Point2D(1, 2).lerp(s.arc().at(1.0), 0.5)))


def test_a_full_turn_is_the_disc() raises -> None:
    var s = Sector((0, 0), 10, 1.0, -tau)
    assert_true(s.contains(Point2D(-7.0, -7.0)))
    assert_true(s.contains(Point2D(0.0, -10.0)))
    assert_true(not s.contains(Point2D(0.0, -10.001)))


def test_closest_point_inside_is_itself() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_equal(s.closest_point((2.0, 3.0)), Point2D(2.0, 3.0))


def test_closest_point_beyond_the_arc() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(s.closest_point((0.0, 20.0)), Point2D(0.0, 10.0))
    _assert_point_near(s.closest_point((30.0, 30.0)), s.arc().at(0.5))


def test_closest_point_beside_a_radius() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(s.closest_point((4.0, -3.0)), Point2D(4.0, 0.0))
    _assert_point_near(s.closest_point((-3.0, 6.0)), Point2D(0.0, 6.0))


def test_closest_point_in_the_missing_wedge() raises -> None:
    # Three quarters, missing the lower right: the nearer of the two radii
    # bounding it, along +x and -y.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    _assert_point_near(s.closest_point((3.0, -1.0)), Point2D(3.0, 0.0))
    _assert_point_near(s.closest_point((1.0, -3.0)), Point2D(0.0, -3.0))


def test_zero_radius_is_the_tip() raises -> None:
    var s = Sector((4, 5), 0, 0.0, pi)
    assert_true(s.contains(Point2D(4.0, 5.0)))
    assert_true(not s.contains(Point2D(4.0, 5.001)))
    assert_equal(s.area(), 0.0)
    _assert_point_near(s.closest_point((10.0, 10.0)), Point2D(4.0, 5.0))


def test_zero_sweep_is_one_radius() raises -> None:
    var s = Sector((0, 0), 10, pi / 2.0, 0.0)
    assert_true(s.contains(Point2D(0.0, 5.0)))
    assert_true(not s.contains(Point2D(0.1, 5.0)))
    assert_true(not s.contains(Point2D(0.0, -5.0)))
    assert_equal(s.area(), 0.0)
    _assert_point_near(s.closest_point((3.0, 5.0)), Point2D(0.0, 5.0))


def test_move_to_and_translate_move_the_tip() raises -> None:
    var s = Sector((0, 0), 5, 0.0, 1.0)
    s.move_to((3.0, 4.0))
    assert_equal(s.position, Point2D(3.0, 4.0))
    s.translate(Vector2D(1.0, -1.0))
    assert_equal(s.position, Point2D(4.0, 3.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
