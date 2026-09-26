from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)

from create.math.matrix import Matrix, apply, identity, rotate, scale, translate
from create.math.vector2d import Vector2D
from create.render.color import Color
from create.render.style import Style
from create.render._command import (
    RenderCommand,
    circle_command,
    clear_command,
    line_command,
    rect_command,
    sprite_command,
    text_command,
    triangle_command,
)
from create.render._shadow import (
    casts_outer_shadow,
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
