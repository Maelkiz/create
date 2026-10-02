from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from create.render.color import Color
from create.render.gradient import Gradient
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


comptime CENTER = Point2D(0.0, 0.0)
comptime SQUARE = Vector2D(10.0, 10.0)


def test_colours_are_spaced_evenly() raises -> None:
    var g = Gradient.linear(Color.RED, Color.GREEN, Color.BLUE)
    assert_equal(len(g._stops[]), 3)
    assert_equal(g._stops[][0][0], 0.0)
    assert_equal(g._stops[][1][0], 0.5)
    assert_equal(g._stops[][2][0], 1.0)
    assert_equal(g._stops[][1][1], Color.GREEN)


def test_one_colour_is_a_solid() raises -> None:
    var g = Gradient.linear(Color.RED)
    assert_equal(g._at(0.0), Color.RED)
    assert_equal(g._at(0.5), Color.RED)
    assert_equal(g._at(1.0), Color.RED)


def test_positions_are_clamped_and_kept_in_order() raises -> None:
    var g = Gradient.linear(
        [
            (-0.5, Color.RED),
            (0.6, Color.GREEN),
            (0.3, Color.BLUE),
            (2.0, Color.WHITE),
        ]
    )
    assert_equal(g._stops[][0][0], 0.0)
    assert_equal(g._stops[][1][0], 0.6)
    assert_equal(g._stops[][2][0], 0.6)
    assert_equal(g._stops[][3][0], 1.0)


def test_end_colours_carry_on() raises -> None:
    var g = Gradient.linear([(0.25, Color.RED), (0.75, Color.BLUE)])
    assert_equal(g._at(0.0), Color.RED)
    assert_equal(g._at(-3.0), Color.RED)
    assert_equal(g._at(1.0), Color.BLUE)
    assert_equal(g._at(9.0), Color.BLUE)


def test_hard_edge_takes_the_later_stop() raises -> None:
    var g = Gradient.linear(
        [
            (0.0, Color.RED),
            (0.5, Color.RED),
            (0.5, Color.BLUE),
            (1.0, Color.BLUE),
        ]
    )
    assert_equal(g._at(0.49), Color.RED)
    assert_equal(g._at(0.5), Color.BLUE)


def test_blends_between_stops() raises -> None:
    var g = Gradient.linear(Color.BLACK, Color.WHITE)
    assert_equal(g._at(0.5), Color(128, 128, 128))


def test_fade_to_transparent_is_not_grey() raises -> None:
    var g = Gradient.linear(Color.RED, Color.TRANSPARENT)
    var mid = g._at(0.5)
    assert_equal(mid.r, 255)
    assert_equal(mid.g, 0)
    assert_equal(mid.b, 0)
    assert_equal(mid.a, 128)


def test_default_direction_runs_top_to_bottom() raises -> None:
    var g = Gradient.linear(Color.RED, Color.BLUE)
    assert_almost_equal(g._t_at(Point2D(0.0, 10.0), CENTER, SQUARE), 0.0)
    assert_almost_equal(g._t_at(Point2D(0.0, -10.0), CENTER, SQUARE), 1.0)
    assert_almost_equal(g._t_at(Point2D(7.0, 0.0), CENTER, SQUARE), 0.5)


def test_direction_need_not_be_unit() raises -> None:
    var g = Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D(5.0, 0.0))
    assert_almost_equal(g._t_at(Point2D(-10.0, 3.0), CENTER, SQUARE), 0.0)
    assert_almost_equal(g._t_at(Point2D(10.0, 3.0), CENTER, SQUARE), 1.0)


def test_diagonal_reaches_the_far_corners() raises -> None:
    var half = Vector2D(40.0, 10.0)
    var g = Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D(1.0, 1.0))
    assert_almost_equal(g._t_at(Point2D(-40.0, -10.0), CENTER, half), 0.0)
    assert_almost_equal(g._t_at(Point2D(40.0, 10.0), CENTER, half), 1.0)
    # The other two corners fall strictly inside.
    var t = g._t_at(Point2D(40.0, -10.0), CENTER, half)
    assert_true(t > 0.0 and t < 1.0)


def test_box_placement_follows_the_center() raises -> None:
    var g = Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.RIGHT)
    var c = Point2D(100.0, 50.0)
    assert_almost_equal(g._t_at(Point2D(90.0, 50.0), c, SQUARE), 0.0)
    assert_almost_equal(g._t_at(Point2D(110.0, 50.0), c, SQUARE), 1.0)


def test_radial_reaches_the_box_edges() raises -> None:
    var half = Vector2D(20.0, 10.0)
    var g = Gradient.radial(Color.WHITE, Color.BLACK)
    assert_almost_equal(g._t_at(CENTER, CENTER, half), 0.0)
    assert_almost_equal(g._t_at(Point2D(20.0, 0.0), CENTER, half), 1.0)
    assert_almost_equal(g._t_at(Point2D(0.0, -10.0), CENTER, half), 1.0)


def test_radial_center_moves_in_unit_space() raises -> None:
    var g = Gradient.radial(Color.WHITE, Color.BLACK, center=(0.5, -0.5))
    assert_almost_equal(g._t_at(Point2D(5.0, -5.0), CENTER, SQUARE), 0.0)
    # Its size stays put: one half-extent away is the last stop.
    assert_almost_equal(g._t_at(Point2D(15.0, -5.0), CENTER, SQUARE), 1.0)


def test_zero_direction_paints_the_first_stop() raises -> None:
    var g = Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.ZERO)
    var t = g._t_at(Point2D(10.0, -10.0), CENTER, SQUARE)
    assert_equal(g._at(t), Color.RED)


def test_zero_box_paints_the_first_stop() raises -> None:
    var flat = Vector2D(0.0, 10.0)
    var across = Gradient.linear(
        Color.RED, Color.BLUE, direction=Vector2D.RIGHT
    )
    assert_equal(
        across._at(across._t_at(Point2D(0.0, 5.0), CENTER, flat)), Color.RED
    )
    var radial = Gradient.radial(Color.RED, Color.BLUE)
    assert_equal(
        radial._at(radial._t_at(Point2D(0.0, 5.0), CENTER, flat)), Color.RED
    )


def test_opaque_and_visible() raises -> None:
    assert_true(Gradient.linear(Color.RED, Color.BLUE)._opaque())
    assert_false(
        Gradient.linear(Color.RED, Color.BLUE.with_alpha(254))._opaque()
    )
    assert_true(Gradient.linear(Color.TRANSPARENT, Color.RED)._visible())
    assert_false(
        Gradient.linear(Color.TRANSPARENT, Color.TRANSPARENT)._visible()
    )


def test_with_opacity_scales_every_stop() raises -> None:
    var g = Gradient.linear(
        Color.RED, Color.BLUE.with_alpha(100)
    )._with_opacity(0.5)
    assert_equal(g._stops[][0][1], Color(255, 0, 0, 127))
    assert_equal(g._stops[][1][1], Color(0, 0, 255, 50))


def test_equality() raises -> None:
    var a = Gradient.linear(Color.RED, Color.BLUE)
    assert_true(a == Gradient.linear([(0.0, Color.RED), (1.0, Color.BLUE)]))
    assert_true(
        a != Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.UP)
    )
    assert_true(a != Gradient.radial(Color.RED, Color.BLUE))
    # A copy shares its stops and compares equal.
    var b = a
    assert_true(a == b)


def test_prints_as_source() raises -> None:
    assert_equal(
        String(Gradient.linear(Color.RED, Color.BLUE)),
        (
            "Gradient.linear([(0.0, Color(255, 0, 0, 255)), (1.0, Color(0, 0,"
            " 255, 255))], direction=Vector2D(0.0, -1.0))"
        ),
    )
    assert_equal(
        String(Gradient.radial(Color.WHITE, center=(0.5, 0.0))),
        (
            "Gradient.radial([(0.0, Color(255, 255, 255, 255))],"
            " center=Point2D(0.5, 0.0))"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
