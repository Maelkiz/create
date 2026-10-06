"""`Font` and the packaged faces, outside any renderer."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from create.text.font import (
    Font,
    FontWeight,
    _Face,
    _GlyphInfo,
    default_font_path,
    fallback_font_path,
)

comptime _SLNT_FIXTURE = "tests/fixtures/fonts/RobotoFlex-slnt.ttf"
"""Roboto Flex cut down to A-Z, a-z and its `wght` and `slnt` axes: a face
whose italic is an axis of the same file."""


def _first_ink(g: _GlyphInfo, row: Int) -> Int:
    """The column of the first half-covered pixel in `row`, or -1."""
    for x in range(g.width):
        if g.pixels[row * g.width + x] >= 128:
            return x
    return -1


def _lean(g: _GlyphInfo) -> Int:
    """How far right a stem's left edge moves from its foot to its top, in
    pixels: 0 for an upright `I`, positive for a forward lean."""
    return _first_ink(g, 1) - _first_ink(g, g.height - 2)


def test_the_packaged_faces_load_from_the_text_package() raises -> None:
    # They are located from font.mojo's own path, so moving the file must
    # take them with it.
    assert_true(default_font_path().endswith("text/fonts/NotoSans.ttf"))
    var f = Font.load(default_font_path())
    assert_true(f.has_glyph(ord("A")))
    # Loading raises if the file is not where the path says.
    _ = Font.load(fallback_font_path())


def test_a_glyph_renders() raises -> None:
    var f = Font.load(default_font_path())
    var g = f.render(ord("A"), 24)
    assert_true(g.width > 0 and g.height > 0)
    assert_true(g.advance_x > 0)


def test_font_weights_are_design_space_values() raises -> None:
    assert_equal(FontWeight.REGULAR, 400)
    assert_equal(FontWeight.BOLD, 700)


def test_an_upright_face_does_not_lean() raises -> None:
    var face = _Face(default_font_path(), 48, FontWeight.REGULAR)
    assert_equal(_lean(face.render(ord("I"), 48)), 0)
    assert_true(not face.sheared)


def test_a_face_without_an_italic_is_sheared() raises -> None:
    var upright = _Face(default_font_path(), 48, FontWeight.REGULAR)
    var slanted = _Face(
        default_font_path(), 48, FontWeight.REGULAR, slanted=True
    )
    assert_true(slanted.sheared)
    var g = slanted.render(ord("I"), 48)
    # tan(12°) across a ~34 pixel stem is ~7 pixels.
    assert_true(_lean(g) >= 5, String("lean ", _lean(g)))
    assert_equal(g.advance_x, upright.render(ord("I"), 48).advance_x)
    assert_true(slanted.has_glyph(ord("I")))


def test_a_slnt_axis_is_the_italic_of_its_own_file() raises -> None:
    var upright = _Face(_SLNT_FIXTURE, 48, FontWeight.REGULAR)
    var slanted = _Face(_SLNT_FIXTURE, 48, FontWeight.REGULAR, slanted=True)
    assert_true(not slanted.sheared, "the axis, not a transform")
    assert_equal(_lean(upright.render(ord("I"), 48)), 0)
    assert_true(_lean(slanted.render(ord("I"), 48)) >= 4)
    # The weight is solved together with the slant, so changing it keeps
    # the lean.
    slanted._set_weight(FontWeight.BOLD)
    assert_true(_lean(slanted.render(ord("I"), 48)) >= 4)


def test_load_of_a_missing_file_raises() raises -> None:
    with assert_raises(contains="not found"):
        _ = Font.load("/nonexistent/face.ttf")


def test_a_copy_shares_the_face() raises -> None:
    var a = Font.load(default_font_path())
    var b = a.copy()
    assert_equal(b._id, a._id)
    assert_equal(Int(a._face.count()), 2, "one face, two holders")
    _ = b^  # Kept alive to here: Mojo would destroy it after its last use.


def test_each_load_is_its_own_font() raises -> None:
    var a = Font.load(default_font_path())
    var b = Font.load(default_font_path())
    assert_true(a._id != b._id)
    assert_true(a._id > 0)


def test_a_font_prints_as_it_is_loaded() raises -> None:
    var f = Font.load(default_font_path())
    assert_equal(String(f), 'Font.load("' + default_font_path() + '")')


def _copy_of_a_dropped_font() raises -> Font:
    var original = Font.load(default_font_path())
    return original.copy()


def test_a_copy_renders_after_the_original_is_gone() raises -> None:
    var copy = _copy_of_a_dropped_font()
    var g = copy.render(ord("A"), 24)
    assert_true(g.width > 0 and g.height > 0)


def test_fonts_are_closed_when_dropped() raises -> None:
    # A smoke test for `_Face.__del__`: opening and dropping many faces must
    # neither fail nor crash. It cannot prove nothing leaks.
    for _ in range(50):
        var f = Font.load(default_font_path())
        _ = f.has_glyph(ord("A"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
