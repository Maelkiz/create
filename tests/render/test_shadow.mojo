from std.math import erf, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)

from create.math.matrix import Matrix, apply, identity, rotate, scale, translate
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from create.math.bezier import Bezier
from create.render.color import Color
from create.render.style import Style
from create.render._command import (
    RenderCommand,
    bezier_chain_command,
    bezier_command,
    circle_command,
    clear_command,
    line_command,
    polygon_command,
    rect_command,
    sector_command,
    sprite_command,
    text_command,
    triangle_command,
)
from create.render._shadow import (
    box_coverage,
    casts_inset_shadow,
    casts_outer_shadow,
    edge_coverage,
    gaussian_cdf,
    rounded_rect_coverage,
    shadow_command,
    shadow_transform,
)


def _shadowed() -> Style:
    var s = Style(fill=Color.WHITE, shadow_enabled=True)
    s.shadow_offset = Vector2D(4, -4)
    return s^


def _device() -> Matrix[3, 3]:
    """A window base like the canvas builds: scale 2, y flipped."""
    return translate(100.0, 100.0) @ scale(2.0, -2.0)


def _moved(m: Matrix[3, 3], s: Matrix[3, 3]) -> Tuple[Float64, Float64]:
    """Where the local origin lands under `s`, relative to under `m`."""
    var a = apply(m, 0.0, 0.0)
    var b = apply(s, 0.0, 0.0)
    return (b[0] - a[0], b[1] - a[1])


def test_screen_fixed_offset_ignores_rotation() raises -> None:
    var m = _device() @ rotate(pi / 2.0)
    var c = rect_command(m, _shadowed(), 0.0, 0.0, 10.0, 10.0)
    # A rotated transform has no single pixel scale, so the length comes from
    # the frame's autoscale factor, as outline thickness does.
    var d = _moved(m, shadow_transform(c, 2.0))
    # Down-right on screen: device rows run downwards.
    assert_almost_equal(d[0], 8.0)
    assert_almost_equal(d[1], 8.0)


def test_follows_transform_offset_turns_with_the_shape() raises -> None:
    var m = _device() @ rotate(pi / 2.0)
    var s = _shadowed()
    s.shadow_follows_transform = True
    var c = rect_command(m, s, 0.0, 0.0, 10.0, 10.0)
    var d = _moved(m, shadow_transform(c, 2.0))
    # (4, -4) turned a quarter anticlockwise is (4, 4): up-right on screen.
    assert_almost_equal(d[0], 8.0)
    assert_almost_equal(d[1], -8.0)


def test_only_render_calls_that_paint_cast_a_shadow() raises -> None:
    var s = _shadowed()
    assert_true(casts_outer_shadow(rect_command(identity[3](), s, 0, 0, 1, 1)))
    assert_false(casts_outer_shadow(clear_command(Color.RED)))
    s.fill_enabled = False
    s.outline_enabled = False
    assert_false(casts_outer_shadow(rect_command(identity[3](), s, 0, 0, 1, 1)))
    var off = _shadowed()
    off.shadow_enabled = False
    assert_false(
        casts_outer_shadow(rect_command(identity[3](), off, 0, 0, 1, 1))
    )
    var inset = _shadowed()
    inset.shadow_inset = True
    assert_false(
        casts_outer_shadow(rect_command(identity[3](), inset, 0, 0, 1, 1))
    )


def test_filled_shape_casts_one_filled_layer() raises -> None:
    var s = _shadowed()
    s.shadow_color = Color(0, 0, 0, 100)
    var c = rect_command(identity[3](), s, 0.0, 0.0, 10.0, 6.0)
    var sh = shadow_command(c, 1.0)
    assert_true(sh.style.fill_enabled)
    assert_equal(sh.style.fill_color, Color(0, 0, 0, 100))
    assert_false(sh.style.outline_enabled)
    assert_false(sh.style.shadow_enabled)
    # A rectangle's outline is inset, so the silhouette is the rectangle.
    assert_equal(sh.geom[2], 10.0)
    assert_equal(sh.geom[3], 6.0)


def test_outline_only_shape_casts_its_ring() raises -> None:
    var s = Style(outline=Color.RED, outline_thickness=3, shadow_enabled=True)
    var c = circle_command(identity[3](), s, 0.0, 0.0, 10.0)
    var sh = shadow_command(c, 1.0)
    assert_false(sh.style.fill_enabled)
    assert_true(sh.style.outline_enabled)
    assert_equal(sh.style.outline_color, s.shadow_color)
    assert_equal(sh.style.outline_thickness, 3)
    assert_equal(sh.geom[2], 10.0)


def test_bezier_casts_its_stroke_even_when_filled() raises -> None:
    # A curve has no interior: a fill in its style changes nothing, and its
    # silhouette is the stroke, widened by the spread on both sides.
    var s = _shadowed()
    s.outline_enabled = True
    s.outline_thickness = 3
    s.shadow_spread = 1.0
    var curve = Bezier((0.0, 0.0), (10.0, 20.0), (20.0, -20.0), (30.0, 0.0))
    var c = bezier_command(identity[3](), s, curve)
    assert_true(casts_outer_shadow(c))
    var sh = shadow_command(c, 1.0)
    assert_false(sh.style.fill_enabled)
    assert_true(sh.style.outline_enabled)
    assert_equal(sh.style.outline_color, s.shadow_color)
    assert_equal(sh.style.outline_thickness, 5)
    assert_equal(len(sh.points), len(c.points))
    for i in range(len(c.points)):
        assert_equal(sh.points[i], c.points[i])
    s.outline_enabled = False
    assert_false(casts_outer_shadow(bezier_command(identity[3](), s, curve)))


def test_a_bezier_chain_casts_every_curve() raises -> None:
    var s = _shadowed()
    s.outline_enabled = True
    var chain: List[Point2D] = [
        (0.0, 0.0),
        (10.0, 20.0),
        (20.0, 20.0),
        (30.0, 0.0),
        (40.0, -20.0),
        (50.0, -20.0),
        (0.0, 0.0),
    ]
    var c = bezier_chain_command(identity[3](), s, chain.copy())
    assert_true(casts_outer_shadow(c))
    var sh = shadow_command(c, 1.0)
    assert_equal(len(sh.points), len(chain))
    for i in range(len(chain)):
        assert_equal(sh.points[i], chain[i])


def test_spread_grows_each_kind() raises -> None:
    var s = _shadowed()
    s.outline_enabled = False
    s.shadow_spread = 2.0
    var r = shadow_command(rect_command(identity[3](), s, 0, 0, 10, 6), 1.0)
    assert_equal(r.geom[2], 14.0)
    assert_equal(r.geom[3], 10.0)
    assert_equal(r.style.corner_radius, 2)
    var c = shadow_command(circle_command(identity[3](), s, 0, 0, 5), 1.0)
    assert_equal(c.geom[2], 7.0)
    var l = shadow_command(line_command(identity[3](), s, 0, 0, 5, 0), 1.0)
    assert_equal(l.style.outline_thickness, 5)


def test_negative_spread_never_inverts_a_shape() raises -> None:
    var s = _shadowed()
    s.shadow_spread = -20.0
    var r = shadow_command(rect_command(identity[3](), s, 0, 0, 10, 6), 1.0)
    assert_equal(r.geom[2], 0.0)
    assert_equal(r.geom[3], 0.0)


def test_triangle_grows_every_edge_by_the_spread() raises -> None:
    var s = _shadowed()
    s.outline_enabled = False
    s.shadow_spread = 1.0
    # Right isosceles triangle, legs along the axes.
    var c = triangle_command(identity[3](), s, 0, 0, 10, 0, 0, 10)
    var sh = shadow_command(c, 1.0)
    # The right-angle vertex moves out one unit along both axes.
    assert_almost_equal(sh.geom[0], -1.0)
    assert_almost_equal(sh.geom[1], -1.0)
    assert_equal(sh.style.corner_radius, 1)


def test_triangle_silhouette_reaches_the_outline_outer_edge() raises -> None:
    var s = _shadowed()
    s.outline_thickness = 2
    s.shadow_spread = 0.0
    var c = triangle_command(identity[3](), s, 0, 0, 10, 0, 0, 10)
    var sh = shadow_command(c, 1.0)
    # Centred bands reach half the thickness past each edge.
    assert_almost_equal(sh.geom[0], -1.0)
    assert_almost_equal(sh.geom[1], -1.0)


def test_a_sector_casts_its_grown_silhouette() raises -> None:
    # The outline is inset, so the silhouette is the sector; the spread
    # rides along for `sector_quads` to grow it exactly.
    var s = _shadowed()
    s.shadow_spread = 2.0
    var c = sector_command(identity[3](), s, 0.0, 0.0, 10.0, 0.5, -4.0)
    assert_true(casts_outer_shadow(c))
    var sh = shadow_command(c, 1.0)
    assert_true(sh.style.fill_enabled)
    assert_equal(sh.style.fill_color, s.shadow_color)
    assert_false(sh.style.outline_enabled)
    for i in range(5):
        assert_equal(sh.geom[i], c.geom[i])
    assert_equal(sh.geom[5], 2.0)


def test_an_outline_only_sector_casts_its_ring() raises -> None:
    var s = Style(outline=Color.RED, outline_thickness=3, shadow_enabled=True)
    s.shadow_spread = 1.0
    var c = sector_command(identity[3](), s, 0.0, 0.0, 10.0, 0.0, 1.0)
    var sh = shadow_command(c, 1.0)
    assert_false(sh.style.fill_enabled)
    assert_equal(sh.style.outline_color, s.shadow_color)
    assert_equal(sh.style.outline_thickness, 5)
    assert_equal(sh.geom[5], 1.0)
    s.outline_enabled = False
    assert_false(
        casts_outer_shadow(sector_command(identity[3](), s, 0, 0, 10, 0, 1))
    )


def test_a_sector_casts_no_inset_shadow() raises -> None:
    var s = _shadowed()
    s.shadow_inset = True
    var c = sector_command(identity[3](), s, 0.0, 0.0, 10.0, 0.0, 1.0)
    assert_false(casts_inset_shadow(c))
    assert_false(casts_outer_shadow(c))


def _square() -> List[Point2D]:
    return [(-10.0, -10.0), (10.0, -10.0), (10.0, 10.0), (-10.0, 10.0)]


def test_a_polygon_casts_its_grown_silhouette() raises -> None:
    # The outline is inset, so the silhouette is the polygon; the spread
    # rides along for `polygon_quads` to grow it exactly.
    var s = _shadowed()
    s.shadow_spread = 2.0
    var c = polygon_command(identity[3](), s, _square())
    assert_true(casts_outer_shadow(c))
    var sh = shadow_command(c, 1.0)
    assert_true(sh.style.fill_enabled)
    assert_equal(sh.style.fill_color, s.shadow_color)
    assert_false(sh.style.outline_enabled)
    assert_equal(len(sh.points), 4)
    for i in range(4):
        assert_true(sh.points[i] == c.points[i])
    assert_equal(sh.geom[0], 2.0)


def test_an_outline_only_polygon_casts_its_ring() raises -> None:
    var s = Style(outline=Color.RED, outline_thickness=3, shadow_enabled=True)
    s.shadow_spread = 1.0
    var c = polygon_command(identity[3](), s, _square())
    var sh = shadow_command(c, 1.0)
    assert_false(sh.style.fill_enabled)
    assert_equal(sh.style.outline_color, s.shadow_color)
    assert_equal(sh.style.outline_thickness, 5)
    assert_equal(sh.geom[0], 1.0)
    s.outline_enabled = False
    assert_false(
        casts_outer_shadow(polygon_command(identity[3](), s, _square()))
    )


def test_a_polygon_casts_no_inset_shadow() raises -> None:
    var s = _shadowed()
    s.shadow_inset = True
    var c = polygon_command(identity[3](), s, _square())
    assert_false(casts_inset_shadow(c))
    assert_false(casts_outer_shadow(c))


def test_text_shadow_recolours_the_glyphs() raises -> None:
    var s = _shadowed()
    var c = text_command(identity[3](), s, 0.0, 0.0, "hi")
    var sh = shadow_command(c, 1.0)
    assert_equal(sh.style.text_color, s.shadow_color)
    assert_equal(sh.text, "hi")


def test_sprite_shadow_is_a_silhouette() raises -> None:
    var s = _shadowed()
    var c = sprite_command(identity[3](), s, 0, 0, 4, 4, 7, 4, 4)
    assert_false(c.silhouette)
    var sh = shadow_command(c, 1.0)
    assert_true(sh.silhouette)
    assert_equal(sh.style.fill_color, s.shadow_color)
    assert_equal(sh.image, 7)


def test_gaussian_cdf_matches_erf() raises -> None:
    var x = -3.875
    while x < 4.0:
        var want = 0.5 * (1.0 + erf(x / sqrt(2.0)))
        assert_almost_equal(gaussian_cdf(x), want, atol=2e-7)
        x += 0.125
    # Past four sigma it saturates, below what an 8-bit channel resolves.
    assert_equal(gaussian_cdf(4.0), 1.0)
    assert_equal(gaussian_cdf(-4.0), 0.0)


def test_coverage_is_half_on_an_edge_and_saturates_by_three_sigma() raises -> (
    None
):
    # A half-plane: the far edges out of reach.
    assert_almost_equal(edge_coverage(0.0, 1e9, 1e9), 0.5, atol=1e-7)
    assert_true(edge_coverage(3.0, 1e9, 1e9) > 0.998)
    assert_true(edge_coverage(-3.0, 1e9, 1e9) < 0.002)
    assert_almost_equal(box_coverage(0.0, 1e9, 1e9, 1e9), 0.5, atol=1e-7)
    assert_true(box_coverage(3.0, 1e9, 1e9, 1e9) > 0.998)
    assert_true(box_coverage(-3.0, 1e9, 1e9, 1e9) < 0.002)
    # A long straight edge of a rounded rectangle.
    assert_almost_equal(
        rounded_rect_coverage(10.0, 0.0, 10.0, 100.0, 2.0), 0.5, atol=1e-7
    )
    assert_true(rounded_rect_coverage(7.0, 0.0, 10.0, 100.0, 2.0) > 0.998)
    assert_true(rounded_rect_coverage(13.0, 0.0, 10.0, 100.0, 2.0) < 0.002)


def test_box_coverage_is_the_separable_erf_form() raises -> None:
    # Centre of a rectangle 2 sigma wide and 1 sigma tall: each axis keeps
    # the share of the Gaussian within its half-extent.
    var want = erf(1.0 / sqrt(2.0)) * erf(0.5 / sqrt(2.0))
    assert_almost_equal(box_coverage(1.0, 1.0, 0.5, 0.5), want, atol=1e-6)
    # Off-centre: x = 0.3 in a slab [-1, 1].
    var slab = 0.5 * (erf(1.3 / sqrt(2.0)) + erf(0.7 / sqrt(2.0)))
    assert_almost_equal(box_coverage(1.3, 0.7, 1e9, 1e9), slab, atol=1e-6)


def test_edge_product_matches_the_box_once_the_shape_is_wide() raises -> None:
    # Far from the opposite edges the two forms agree; narrow, the product
    # overestimates, since cdf(a) * cdf(b) >= cdf(a) + cdf(b) - 1.
    assert_almost_equal(
        edge_coverage(0.5, 10.0, 0.5, 10.0),
        box_coverage(0.5, 10.0, 0.5, 10.0),
        atol=1e-6,
    )
    assert_true(
        edge_coverage(0.5, 0.5, 0.5, 0.5) > box_coverage(0.5, 0.5, 0.5, 0.5)
    )


def test_rounded_rect_coverage_is_symmetric_and_rounds_corners() raises -> None:
    var a = rounded_rect_coverage(9.0, 4.0, 10.0, 5.0, 3.0)
    assert_almost_equal(a, rounded_rect_coverage(-9.0, -4.0, 10.0, 5.0, 3.0))
    # The sharp corner point is outside a rounded corner by (sqrt 2 - 1) r.
    var corner = rounded_rect_coverage(10.0, 5.0, 10.0, 5.0, 3.0)
    assert_almost_equal(
        corner, gaussian_cdf(-(sqrt(2.0) - 1.0) * 3.0), atol=1e-9
    )
    # A circle: half at its radius in any direction.
    var d = 4.0 / sqrt(2.0)
    assert_almost_equal(
        rounded_rect_coverage(d, d, 4.0, 4.0, 4.0), 0.5, atol=1e-7
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
