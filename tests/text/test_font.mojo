"""`Font` and the packaged faces, outside any renderer."""

from std.testing import TestSuite, assert_equal, assert_true

from create.text.font import (
    Font,
    FontWeight,
    default_font_path,
    fallback_font_path,
)


def test_the_packaged_faces_load_from_the_text_package() raises -> None:
    # They are located from font.mojo's own path, so moving the file must
    # take them with it.
    assert_true(default_font_path().endswith("text/fonts/NotoSans.ttf"))
    var f = Font(default_font_path(), 24)
    assert_true(f.has_glyph(ord("A")))
    # Loading raises if the file is not where the path says.
    _ = Font(fallback_font_path(), 24)


def test_a_glyph_renders() raises -> None:
    var f = Font(default_font_path(), 24)
    var g = f.render(ord("A"), 24)
    assert_true(g.width > 0 and g.height > 0)
    assert_true(g.advance_x > 0)


def test_font_weights_are_design_space_values() raises -> None:
    assert_equal(FontWeight.REGULAR, 400)
    assert_equal(FontWeight.BOLD, 700)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
