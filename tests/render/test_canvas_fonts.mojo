"""The font as part of the style: several faces in one frame, each `text`
call keeping the face it was drawn in.

The two packaged faces stand in for two fonts. Noto Sans Symbols carries
Latin letters too, hinted a little differently, so "H" comes out differently
in it by a few pixels. Each scene is compared against references drawn in
one face alone, so the tests never depend on how.

On an offscreen 100 x 40 canvas: the left half is x < 50, the right x >= 50.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.text.font import default_font_path, fallback_font_path


def _canvas() raises -> Canvas:
    var canvas = Canvas(100, 40, antialiasing=Antialiasing.OFF)
    canvas.text_color(Color.BLACK)
    canvas.font_size(24)
    return canvas^


def _symbols() raises -> Font:
    return Font.load(fallback_font_path())


def _alone(font: Optional[Font], x: Float64) raises -> Image:
    """ "H" at `x` in one face, nothing else."""
    var canvas = _canvas()
    if font:
        canvas.font(font.value())
    canvas.text("H", (x, 0))
    return canvas.snapshot()


def _differing_in_half(a: Image, b: Image, right: Bool) -> Int:
    """Pixels that differ between `a` and `b` in one half."""
    var n = 0
    var x0 = 50 if right else 0
    for y in range(a.height):
        for x in range(x0, x0 + 50):
            if a.pixel(x, y) != b.pixel(x, y):
                n += 1
    return n


def test_the_two_faces_draw_h_differently() raises -> None:
    # The premise of every test below.
    var sans = _alone(None, -25)
    var symbols = _alone(_symbols(), -25)
    assert_true(_differing_in_half(sans, symbols, right=False) > 0)


def test_two_fonts_share_a_frame() raises -> None:
    var canvas = _canvas()
    canvas.font(_symbols())
    canvas.text("H", (-25, 0))
    canvas.font(Font.load(default_font_path()))
    canvas.text("H", (25, 0))
    var both = canvas.snapshot()
    assert_equal(
        _differing_in_half(both, _alone(_symbols(), -25), right=False), 0
    )
    assert_equal(_differing_in_half(both, _alone(None, 25), right=True), 0)


def test_text_keeps_the_font_it_was_drawn_in() raises -> None:
    # A later `canvas.font` must not reach back: the face is recorded with the
    # call, not looked up when the frame is drawn.
    var canvas = _canvas()
    canvas.text("H", (-25, 0))
    canvas.font(_symbols())
    canvas.text("H", (25, 0))
    var shot = canvas.snapshot()
    assert_equal(_differing_in_half(shot, _alone(None, -25), right=False), 0)
    assert_equal(
        _differing_in_half(shot, _alone(_symbols(), 25), right=True), 0
    )


def test_a_style_block_restores_the_font() raises -> None:
    var canvas = _canvas()
    with canvas.style(font=_symbols()):
        canvas.text("H", (-25, 0))
    canvas.text("H", (25, 0))
    var shot = canvas.snapshot()
    assert_equal(
        _differing_in_half(shot, _alone(_symbols(), -25), right=False), 0
    )
    assert_equal(_differing_in_half(shot, _alone(None, 25), right=True), 0)


def test_text_width_follows_the_font() raises -> None:
    var canvas = _canvas()
    # Each of these is a pixel wider in the symbols face at this size; "H" is
    # the same width in both.
    var sans = canvas.text_width("BDJLO")
    canvas.font(_symbols())
    assert_true(canvas.text_width("BDJLO") != sans)


def test_a_style_prints_its_font() raises -> None:
    var font = _symbols()
    var style = Style(font=font)
    assert_true(String(style).find('font=Font.load("' + font.path + '")') >= 0)
    assert_true(String(Style()).find("font=None") >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
