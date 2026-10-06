from std.testing import TestSuite, assert_equal, assert_true, assert_false

from create import *


def test_default_style_matches_a_fresh_frame() raises -> None:
    var s = Style()
    assert_equal(s.fill_color, Color.WHITE)
    assert_false(s.fill_enabled)
    assert_equal(s.outline_color, Color.BLACK)
    assert_equal(s.outline_thickness, 1)
    assert_true(s.outline_enabled)
    assert_equal(s.corner_radius, 0)
    assert_equal(s.text_color, Color.BLACK)
    assert_equal(s.font_size, 16)
    assert_equal(s.font_weight, FontWeight.REGULAR)
    assert_false(s.font_italic)
    assert_true(s.text_align == Align.CENTER)
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
        corner_radius=5,
        text_color=Color.WHITE,
        font_size=32,
        font_weight=FontWeight.BOLD,
        font_italic=True,
        text_align=Align.TOP_LEFT,
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
    assert_equal(s.corner_radius, 5)
    assert_equal(s.text_color, Color.WHITE)
    assert_equal(s.font_size, 32)
    assert_equal(s.font_weight, FontWeight.BOLD)
    assert_true(s.font_italic)
    assert_true(s.text_align == Align.TOP_LEFT)
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
            " fill_enabled=False,"
            " outline=Color(0, 0, 0, 255), outline_thickness=1,"
            " outline_enabled=True, corner_radius=0, text_color=Color(0, 0, 0,"
            " 255), font=None, font_size=16, font_weight=400,"
            " font_italic=False, text_align=Align.CENTER,"
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
