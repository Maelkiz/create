from std.testing import TestSuite, assert_equal, assert_true, assert_false

from create import *


def test_default_style_matches_a_fresh_frame() raises -> None:
    var s = Style()
    assert_equal(s.fill_color, Color.TRANSPARENT)
    assert_true(s.fill_enabled)
    assert_equal(s.outline_color, Color.BLACK)
    assert_equal(s.outline_thickness, 1)
    assert_true(s.outline_enabled)
    assert_equal(s.corner_radius, 0)
    assert_equal(s.text_color, Color.BLACK)
    assert_equal(s.font_size, 16)
    assert_equal(s.font_weight, FontWeight.REGULAR)
    assert_true(s.text_align == Align.CENTER)
    assert_equal(s.opacity, 1.0)


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
        text_align=Align.TOP_LEFT,
        opacity=0.5,
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
    assert_true(s.text_align == Align.TOP_LEFT)
    assert_equal(s.opacity, 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
