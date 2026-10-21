from std.testing import TestSuite, assert_equal, assert_true, assert_false

from create import *
from create.render._text import _pixel_size
from create.render._transform import outline_thickness_px


def test_default_style_matches_a_fresh_frame() raises -> None:
    var s = Style()
    assert_equal(s.fill_color, Color.WHITE)
    assert_false(s.fill_enabled)
    assert_equal(s.outline_color, Color.BLACK)
    assert_equal(s.outline_thickness, 1)
    assert_true(s.outline_enabled)
    assert_equal(s.text_color, Color.BLACK)
    assert_equal(s.font_size, 16)
    assert_equal(s.font_weight, FontWeight.REGULAR)
    assert_false(s.font_italic)
    assert_true(s.text_align == Align.CENTER)
    assert_equal(s.tint, Color.WHITE)
    assert_equal(s.opacity, 1.0)
    assert_true(s.blend_mode == BlendMode.NORMAL)
    assert_equal(s.shadow_color, Color(0, 0, 0, 96))
    assert_equal(s.shadow_offset, Vector2D(4, -4))
    assert_equal(s.shadow_blur, 8.0)
    assert_equal(s.shadow_spread, 0.0)
    assert_false(s.shadow_inset)
    assert_false(s.shadow_follows_transform)
    assert_false(s.shadow_enabled)


def test_each_keyword_lands_in_its_field() raises -> None:
    var s = Style(
        fill=Color.RED,
        fill_enabled=False,
        outline=Color.BLUE,
        outline_thickness=3,
        outline_enabled=False,
        text_color=Color.WHITE,
        font_size=32,
        font_weight=FontWeight.BOLD,
        font_italic=True,
        text_align=Align.TOP_LEFT,
        tint=Color.RED,
        opacity=0.5,
        blend_mode=BlendMode.ADD,
        shadow=Color.RED,
        shadow_offset=Vector2D(1, 2),
        shadow_blur=3.0,
        shadow_spread=-1.0,
        shadow_inset=True,
        shadow_follows_transform=True,
        shadow_enabled=True,
    )
    assert_equal(s.fill_color, Color.RED)
    assert_false(s.fill_enabled)
    assert_equal(s.outline_color, Color.BLUE)
    assert_equal(s.outline_thickness, 3)
    assert_false(s.outline_enabled)
    assert_equal(s.text_color, Color.WHITE)
    assert_equal(s.font_size, 32)
    assert_equal(s.font_weight, FontWeight.BOLD)
    assert_true(s.font_italic)
    assert_true(s.text_align == Align.TOP_LEFT)
    assert_equal(s.tint, Color.RED)
    assert_equal(s.opacity, 0.5)
    assert_true(s.blend_mode == BlendMode.ADD)
    assert_equal(s.shadow_color, Color.RED)
    assert_equal(s.shadow_offset, Vector2D(1, 2))
    assert_equal(s.shadow_blur, 3.0)
    assert_equal(s.shadow_spread, -1.0)
    assert_true(s.shadow_inset)
    assert_true(s.shadow_follows_transform)
    assert_true(s.shadow_enabled)


def test_naming_a_part_switches_its_property_on() raises -> None:
    assert_true(Style(fill=Color.RED).fill_enabled)
    assert_true(Style(shadow=Color.RED).shadow_enabled)
    assert_true(Style(shadow_offset=Vector2D(1, 2)).shadow_enabled)
    assert_true(Style(shadow_blur=12).shadow_enabled)
    assert_true(Style(shadow_spread=0).shadow_enabled)
    assert_true(Style(shadow_inset=False).shadow_enabled)
    assert_false(Style(shadow_follows_transform=True).shadow_enabled)


def test_an_explicit_enabled_beside_a_part_wins() raises -> None:
    var s = Style(shadow=Color.RED, shadow_enabled=False)
    assert_false(s.shadow_enabled)
    assert_equal(s.shadow_color, Color.RED)
    assert_false(
        Style(outline=Color.RED, outline_enabled=False).outline_enabled
    )
    assert_false(Style(fill=Color.RED, fill_enabled=False).fill_enabled)


def test_style_writes_constructor_keywords() raises -> None:
    assert_equal(
        String(Style()),
        (
            "Style(fill=Color(255, 255, 255, 255), fill_gradient=None,"
            " fill_enabled=False, outline=Color(0, 0, 0, 255),"
            " outline_thickness=1.0, outline_enabled=True, text_color=Color(0,"
            " 0, 0, 255), font=None, font_size=16.0,"
            " font_weight=FontWeight.REGULAR, font_italic=False,"
            " text_align=Align.CENTER, tint=Color(255, 255, 255, 255),"
            " opacity=1.0, blend_mode=BlendMode.NORMAL, shadow=Color(0, 0, 0,"
            " 96), shadow_offset=Vector2D(4.0, -4.0), shadow_blur=8.0,"
            " shadow_spread=0.0, shadow_inset=False,"
            " shadow_follows_transform=False, shadow_enabled=False)"
        ),
    )


def test_shadow_is_visible_only_when_enabled_and_opaque_enough() raises -> None:
    assert_false(Style()._shadow_visible())
    assert_true(Style(shadow_enabled=True)._shadow_visible())
    assert_false(
        Style(shadow=Color.TRANSPARENT, shadow_enabled=True)._shadow_visible()
    )


def test_fill_gradient_keyword_switches_the_fill_on() raises -> None:
    var sky = Gradient.linear(Color.RED, Color.BLUE)
    var s = Style(fill_gradient=sky)
    assert_true(s.fill_enabled)
    assert_true(s.fill_gradient.value() == sky)
    assert_equal(s.fill_color, Color.WHITE)
    assert_false(Style(fill_gradient=sky, fill_enabled=False).fill_enabled)


def test_fill_gradient_beside_fill_keeps_both() raises -> None:
    var sky = Gradient.linear(Color.RED, Color.BLUE)
    var s = Style(fill=Color.GREEN, fill_gradient=sky)
    assert_true(s.fill_gradient.value() == sky)
    assert_equal(s.fill_color, Color.GREEN)


def test_fill_visibility_follows_the_gradient() raises -> None:
    assert_true(
        Style(
            fill_gradient=Gradient.linear(Color.TRANSPARENT, Color.RED)
        )._fill_visible()
    )
    var clear = Gradient.linear(Color.TRANSPARENT, Color.TRANSPARENT)
    assert_false(Style(fill=Color.RED, fill_gradient=clear)._fill_visible())


def test_fractional_sizes_are_kept_as_given() raises -> None:
    var s = Style(outline_thickness=1.5, font_size=13.5)
    assert_equal(s.outline_thickness, 1.5)
    assert_equal(s.font_size, 13.5)


def test_integer_literals_still_reach_the_float_keywords() raises -> None:
    var s = Style(outline_thickness=2, font_size=24)
    assert_equal(s.outline_thickness, 2.0)
    assert_equal(s.font_size, 24.0)
    assert_true(
        Style(outline_thickness=3, outline_enabled=False).outline_thickness
        == 3.0
    )


def test_fractional_sizes_round_once_scaled() raises -> None:
    """World-unit sizes become whole pixels only at the device: 1.5 units
    at 2 pixels a unit is exactly 3 pixels."""
    var s = Style(outline_thickness=1.5, font_size=13.5)
    assert_equal(outline_thickness_px(s, scale(2.0), 2.0), 3)
    assert_equal(outline_thickness_px(s, scale(1.0), 1.0), 2)
    assert_equal(_pixel_size(s, 2.0), 27)


def test_unset_number_keywords_take_none_or_any_number() raises -> None:
    # An integer literal, a float, `None` and a forwarded `Optional` all
    # reach a number keyword, like every other optional keyword.
    var s = Style(shadow_blur=12, shadow_spread=1.5)
    assert_equal(s.shadow_blur, 12.0)
    assert_equal(s.shadow_spread, 1.5)
    assert_true(s.shadow_enabled)

    var unset = Style(shadow_blur=None, outline_thickness=None)
    assert_equal(unset.shadow_blur, 8.0)
    assert_equal(unset.outline_thickness, 1.0)
    assert_false(unset.shadow_enabled)

    var forwarded: Optional[Float64] = 3.0
    assert_equal(Style(outline_thickness=forwarded).outline_thickness, 3.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
