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
from create.math.matrix import apply, inverse, rotate, scale, translate


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


def _check_mapping(g: Gradient) raises:
    # A device mapping is `_t_at` seen through the inverse transform, for any
    # transform: compare the two at a few device pixels.
    var m = translate(50.0, 40.0) @ rotate(0.7) @ scale(3.0, 2.0)
    var minv = inverse(m)
    var center = Point2D(5.0, -2.0)
    var half = Vector2D(12.0, 7.0)
    var mapping = g._device_mapping(minv, center, half)
    for p in [(0.5, 0.5), (60.5, 10.5), (13.5, 77.5)]:
        var local = apply(minv, p[0], p[1])
        assert_almost_equal(
            mapping.t(p[0], p[1]),
            g._t_at(Point2D(local[0], local[1]), center, half),
            atol=1e-9,
        )


def test_device_mapping_matches_t_at_linear() raises -> None:
    _check_mapping(
        Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D(1.0, -2.0))
    )


def test_device_mapping_matches_t_at_radial() raises -> None:
    _check_mapping(Gradient.radial(Color.RED, Color.BLUE, center=(0.3, -0.6)))


def test_device_mapping_of_a_zero_direction_is_the_first_stop() raises -> None:
    var g = Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.ZERO)
    var mapping = g._device_mapping(inverse(rotate(0.3)), CENTER, SQUARE)
    assert_equal(g._sample(mapping.t(7.5, 3.5), 7, 3), Color.RED)


def test_sample_leaves_exact_colours_alone() raises -> None:
    # Dithering only ever rounds a fraction: a colour the ramp holds exactly
    # comes out as itself at every pixel of the 4x4 pattern.
    var g = Gradient.linear(Color(10, 20, 30, 40), Color(10, 20, 30, 40))
    for y in range(4):
        for x in range(4):
            assert_equal(g._sample(0.5, x, y), Color(10, 20, 30, 40))
    var ends = Gradient.linear(Color.RED, Color.BLUE)
    assert_equal(ends._sample(-1.0, 0, 0), Color.RED)
    assert_equal(ends._sample(2.0, 3, 3), Color.BLUE)


def test_sample_dithers_between_levels() raises -> None:
    # Half way between two neighbouring levels, the 4x4 pattern paints half
    # its pixels one level and half the other.
    var g = Gradient.linear(Color(0, 0, 0), Color(255, 255, 255))
    var t = 100.5 / 255.0
    var high = 0
    for y in range(4):
        for x in range(4):
            var c = g._sample(t, x, y)
            assert_true(c.r == 100 or c.r == 101)
            if c.r == 101:
                high += 1
    assert_equal(high, 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
