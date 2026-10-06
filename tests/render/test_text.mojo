# TextRenderer, driven straight onto an owned buffer.
#
# Hermetic: both faces ship in src/create/text/fonts/, so this asserts on real glyph
# pixels rather than mocking the rasteriser.

from std.testing import TestSuite, assert_equal, assert_true, assert_false

from create.render.align import Align
from create.color.color import Color
from create.text.font import Font, FontWeight, default_font_path, _GlyphInfo
from create.render.style import Style
from create.render.surface import MemorySurface
from create.render._text import (
    TextRenderer,
    _FONT_SLOTS,
    _GLYPH_CACHE_LIMIT,
    _MAX_BLUR,
    _MAX_SIZE,
    _MAX_WEIGHT,
    _pixel_size,
)


def _ink_box(m: MemorySurface) -> Tuple[Int, Int, Int, Int]:
    """Bounding box of everything rendered — `(x0, y0, x1, y1)`, inclusive.

    The buffer starts fully transparent, so any pixel with alpha is ink.
    Returns `(-1, -1, -1, -1)` when nothing was rendered.
    """
    var x0 = m.width
    var y0 = m.height
    var x1 = -1
    var y1 = -1
    for y in range(m.height):
        for x in range(m.width):
            if m.pixel(x, y).a > 0:
                x0 = min(x0, x)
                y0 = min(y0, y)
                x1 = max(x1, x)
                y1 = max(y1, y)
    if x1 < 0:
        return (-1, -1, -1, -1)
    return (x0, y0, x1, y1)


def _style(align: Align) -> Style:
    var s = Style()
    s.text_color = Color.WHITE
    s.font_size = 24
    s.text_align = align
    return s^


def _render(align: Align, x: Float64, y: Float64) raises -> MemorySurface:
    var m = MemorySurface(200, 120)
    var t = TextRenderer()
    t.render(m.surface(), "Hi", x, y, _style(align), 1.0)
    return m^


def _render_with(mut t: TextRenderer, var style: Style) raises -> MemorySurface:
    """Render "Hi" through an existing renderer, so its cache carries over."""
    var m = MemorySurface(200, 120)
    t.render(m.surface(), "Hi", 40.0, 30.0, style^, 1.0)
    return m^


def _same_pixels(a: MemorySurface, b: MemorySurface) -> Bool:
    if a.width != b.width or a.height != b.height:
        return False
    for y in range(a.height):
        for x in range(a.width):
            if a.pixel(x, y) != b.pixel(x, y):
                return False
    return True


def test_construction_touches_no_disk() raises -> None:
    # A program that renders no text must not pay the font load, and must not
    # fail on a missing file it never needed.
    var t = TextRenderer()
    assert_false(Bool(t._default))
    assert_equal(len(t._fallback_font), 0)
    assert_false(t._fallback_attempted)


def test_font_loads_lazily_on_first_render() raises -> None:
    var t = TextRenderer()
    t._ensure_font()
    assert_true(Bool(t._default))
    assert_true(t._fallback_attempted)


def test_fallback_is_attempted_at_most_once() raises -> None:
    # A missing fallback must not be retried on every glyph of every frame.
    var t = TextRenderer()
    t._ensure_font()
    var loaded = len(t._fallback_font)
    t._ensure_font()
    t._ensure_font()
    assert_equal(len(t._fallback_font), loaded)


def test_render_puts_ink_below_and_right_of_a_top_left_anchor() raises -> None:
    var m = _render(Align.TOP_LEFT, 40.0, 30.0)
    var box = _ink_box(m)
    assert_true(box[2] >= 0, "nothing was rendered")
    assert_true(box[0] >= 40, "ink started left of the anchor")
    assert_true(box[1] >= 30, "ink started above the anchor")
    assert_true(box[2] < 200 and box[3] < 120, "ink ran off the buffer")


def test_centre_align_shifts_ink_left_of_left_align() raises -> None:
    var left = _ink_box(_render(Align.TOP_LEFT, 100.0, 30.0))
    var centre = _ink_box(_render(Align.TOP, 100.0, 30.0))
    var right = _ink_box(_render(Align.TOP_RIGHT, 100.0, 30.0))
    assert_true(centre[0] < left[0], "CENTER did not shift left of LEFT")
    assert_true(right[0] < centre[0], "RIGHT did not shift left of CENTER")


def test_baseline_shifts_ink_up_the_buffer() raises -> None:
    # Glyphs rasterise upright regardless of the world y axis, so TOP must put
    # the box below the anchor and BOTTOM above it — in pixel rows, upward
    # means smaller.
    var top = _ink_box(_render(Align.TOP_LEFT, 40.0, 60.0))
    var middle = _ink_box(_render(Align.LEFT, 40.0, 60.0))
    var bottom = _ink_box(_render(Align.BOTTOM_LEFT, 40.0, 60.0))
    assert_true(middle[1] < top[1], "MIDDLE did not sit above TOP")
    assert_true(bottom[1] < middle[1], "BOTTOM did not sit above MIDDLE")


def test_pixel_scale_grows_the_glyphs() raises -> None:
    # Font size is authored in world units, so autoscale must reach the raster.
    var m1 = MemorySurface(200, 120)
    var t1 = TextRenderer()
    t1.render(
        m1.surface(),
        "Hi",
        20.0,
        20.0,
        _style(Align.TOP_LEFT),
        1.0,
    )
    var m2 = MemorySurface(200, 120)
    var t2 = TextRenderer()
    t2.render(
        m2.surface(),
        "Hi",
        20.0,
        20.0,
        _style(Align.TOP_LEFT),
        2.0,
    )
    var small = _ink_box(m1)
    var big = _ink_box(m2)
    assert_true(
        (big[2] - big[0]) > (small[2] - small[0]), "2x scale was not wider"
    )


def test_style_defaults() raises -> None:
    # What every frame starts with, since style does not survive the frame
    # boundary — a wrong default here silently changes the first render call of
    # every render that doesn't set that field.
    var s = Style()
    assert_equal(s.fill_color, Color.WHITE)
    assert_false(s.fill_enabled)
    assert_equal(s.outline_color, Color.BLACK)
    assert_equal(s.outline_thickness, 1)
    assert_true(s.outline_enabled)
    assert_equal(s.text_color, Color.BLACK)
    assert_equal(s.font_size, 16)
    assert_equal(s.font_weight, FontWeight.REGULAR)
    assert_true(s.text_align == Align.CENTER)


def test_repeating_a_render_adds_no_cache_entries() raises -> None:
    # The point of the cache: a static line of text rasterises its glyphs on
    # the frame it first appears and on no frame after.
    var t = TextRenderer()
    var top_left = _style(Align.TOP_LEFT)
    var first = _render_with(t, top_left)
    var after_first = len(t._glyphs)
    var second = _render_with(t, top_left)
    assert_true(after_first > 0, "nothing was cached")
    assert_equal(len(t._glyphs), after_first)
    # A cache that served a stale or wrongly-keyed mask would still render
    # something, so the pixels have to match, not just the entry count.
    assert_true(_same_pixels(first, second), "the cached render differed")


def test_size_and_weight_are_part_of_the_key() raises -> None:
    # Both change the mask, so neither may be served from the other's entry.
    var t = TextRenderer()
    var base = _style(Align.TOP_LEFT)

    var regular = _render_with(t, base)
    var entries = len(t._glyphs)

    var bigger = base
    bigger.font_size = base.font_size * 2
    var big = _render_with(t, bigger^)
    assert_true(len(t._glyphs) > entries, "a new size reused the old masks")
    entries = len(t._glyphs)
    assert_false(_same_pixels(regular, big), "a larger size drew the same ink")

    var bold = base
    bold.font_weight = FontWeight.BLACK
    var heavy = _render_with(t, bold^)
    assert_true(len(t._glyphs) > entries, "a new weight reused the old masks")
    assert_false(
        _same_pixels(regular, heavy), "a heavier weight drew the same ink"
    )


def _in(font: Font) raises -> Style:
    var style = _style(Align.TOP_LEFT)
    style.font = font
    return style^


def _italic(var style: Style) -> Style:
    style.font_italic = True
    return style^


def test_italic_is_a_face_of_its_own() raises -> None:
    # The italic takes a slot of its own, so it neither reuses the upright
    # masks nor evicts them.
    var t = TextRenderer()
    var upright = _style(Align.TOP_LEFT)
    var first = _render_with(t, upright)
    var after_upright = len(t._glyphs)
    var slanted = _render_with(t, _italic(upright))
    assert_true(len(t._glyphs) > after_upright, "italic reused upright masks")
    assert_false(_same_pixels(first, slanted), "italic drew the same ink")
    var after_italic = len(t._glyphs)
    var again = _render_with(t, upright)
    assert_equal(len(t._glyphs), after_italic, "upright rasterised again")
    assert_true(_same_pixels(first, again))


def test_italic_falls_back_to_an_italic() raises -> None:
    # The star is in the symbols face only; italic text gets it slanted.
    var star = "\u2605"
    assert_false(Font.load(default_font_path()).has_glyph(0x2605))
    var t = TextRenderer()
    var upright = _style(Align.TOP_LEFT)
    var a = MemorySurface(200, 120)
    t.render(a.surface(), star, 40.0, 30.0, upright, 1.0)
    var b = MemorySurface(200, 120)
    t.render(b.surface(), star, 40.0, 30.0, _italic(upright), 1.0)
    assert_true(_ink_box(a)[0] >= 0, "the star drew nothing")
    assert_false(_same_pixels(a, b), "the fallback star was not slanted")


def test_width_follows_the_italic() raises -> None:
    var t = TextRenderer()
    var style = _italic(_style(Align.LEFT))
    var right = style
    right.text_align = Align.RIGHT
    var left_glyphs = t.layout("Hi", 40.0, 30.0, style, 1.0)
    var right_glyphs = t.layout("Hi", 40.0, 30.0, right, 1.0)
    assert_equal(
        left_glyphs[0].x - right_glyphs[0].x, t.width("Hi", style, 1.0)
    )


def test_switching_fonts_keeps_the_cache() raises -> None:
    # Each face keys its glyphs by its own slot, so going back to a face finds
    # its masks still there rather than rasterising them again.
    var t = TextRenderer()
    var a = Font.load(default_font_path())
    var b = Font.load(default_font_path())
    _ = _render_with(t, _in(a))
    var after_a = len(t._glyphs)
    assert_true(after_a > 0, "nothing was cached")
    _ = _render_with(t, _in(b))
    var after_b = len(t._glyphs)
    assert_true(after_b > after_a, "b reused a's masks")
    _ = _render_with(t, _in(a))
    assert_equal(len(t._glyphs), after_b, "going back to a rasterised again")
    assert_equal(t.atlas_generation, 0, "a switch must not reset the atlas")


def test_the_same_glyph_in_two_faces_has_two_keys() raises -> None:
    var t = TextRenderer()
    var a = t._slot(Font.load(default_font_path()))
    var b = t._slot(Font.load(default_font_path()))
    assert_true(a != b)
    assert_true(
        t._glyph_key(a, ord("H"), 24, 400) != t._glyph_key(b, ord("H"), 24, 400)
    )


def test_running_out_of_slots_starts_over() raises -> None:
    var t = TextRenderer()
    var f = Font.load(default_font_path())
    for i in range(_FONT_SLOTS):
        # Distinct identities on one open face: slots, not faces, are tested.
        var copy = f.copy()
        copy._id = -1 - i
        _ = t._slot(copy)
    t._glyphs[1] = _GlyphInfo(0, 0, 0, 0, 4)
    assert_equal(t._slot(f), 0, "the first slot of a fresh start")
    assert_equal(len(t._glyphs), 0)
    assert_equal(t.atlas_generation, 1)


def test_an_oversized_font_is_clamped_not_overflowed() raises -> None:
    var big = _style(Align.TOP_LEFT)
    big.font_size = 5000
    assert_equal(_pixel_size(big, 1.0), _MAX_SIZE)
    var t = TextRenderer()
    var slot = t._slot(Font.load(default_font_path()))
    var key = t._glyph_key(slot, 0x10FFFF, _MAX_SIZE, _MAX_WEIGHT, _MAX_BLUR)
    assert_true(key > 0, "the packed key overflowed into the sign bit")


def test_the_cache_is_bounded() raises -> None:
    # Autoscale mints a fresh pixel size per window size, so the key space is
    # unbounded in a way a long-running program really reaches. The dict is
    # filled directly rather than through `_ensure_glyph`: what is under test
    # is the guard, and rasterising four thousand real glyphs to reach it
    # would cost the suite a minute and prove nothing extra.
    var t = TextRenderer()
    var slot = t._slot(t._face(Style()))
    for i in range(_GLYPH_CACHE_LIMIT):
        var key = t._glyph_key(slot, 0xE000 + i, 16, FontWeight.REGULAR)
        t._glyphs[key] = _GlyphInfo(0, 0, 0, 0, 4)
    assert_equal(len(t._glyphs), _GLYPH_CACHE_LIMIT)

    # The next miss drops the lot rather than growing past the limit, and the
    # render it came from still lands its ink.
    var top_left = _style(Align.TOP_LEFT)
    var m = _render_with(t, top_left^)
    assert_true(
        len(t._glyphs) < _GLYPH_CACHE_LIMIT, "the cache grew past its limit"
    )
    assert_true(_ink_box(m)[2] >= 0, "nothing was rendered after a cache drop")


def _alpha_column_peak(m: MemorySurface, y: Int) -> Int:
    """The column where row `y` is most opaque."""
    var best = 0
    for x in range(m.width):
        if m.pixel(x, y).a > m.pixel(best, y).a:
            best = x
    return best


def test_a_blurred_glyph_peaks_under_its_stem() raises -> None:
    # "l" is one vertical stem: blurred, it spreads sideways but stays
    # centred where the plain glyph's ink is.
    var style = _style(Align.CENTER)
    style.font_size = 40
    var plain = MemorySurface(120, 120)
    var blurred = MemorySurface(120, 120)
    var t = TextRenderer()
    t.render(plain.surface(), "l", 60.0, 60.0, style, 1.0)
    t.render(blurred.surface(), "l", 60.0, 60.0, style^, 1.0, 6)
    var box = _ink_box(plain)
    var wide = _ink_box(blurred)
    var mid = (box[1] + box[3]) // 2
    var stem = (box[0] + box[2]) // 2
    assert_true(abs(_alpha_column_peak(blurred, mid) - stem) <= 1)
    assert_true(wide[0] < box[0] and wide[2] > box[2], "the blur didn't spread")
    assert_true(blurred.pixel(stem, mid).a < 255, "the stem stayed hard")


def test_a_repeated_blurred_render_hits_the_cache() raises -> None:
    var t = TextRenderer()
    var m = MemorySurface(200, 120)
    t.render(m.surface(), "Hi", 40.0, 30.0, _style(Align.CENTER), 1.0, 4)
    var entries = len(t._glyphs)
    t.render(m.surface(), "Hi", 40.0, 30.0, _style(Align.CENTER), 1.0, 4)
    assert_equal(len(t._glyphs), entries)
    # A different blur is a different mask.
    t.render(m.surface(), "Hi", 40.0, 30.0, _style(Align.CENTER), 1.0, 5)
    assert_true(len(t._glyphs) > entries)


def test_align_writes_its_constant_name() raises -> None:
    assert_equal(String(Align.TOP), "Align.TOP")
    assert_equal(String(Align.BOTTOM_RIGHT), "Align.BOTTOM_RIGHT")
    assert_equal(String(Align(99)), "Align(99)")


def test_width_is_the_distance_alignment_moves_text_by() raises -> None:
    var t = TextRenderer()
    var left = t.layout("Hi", 40.0, 30.0, _style(Align.LEFT), 1.0)
    var right = t.layout("Hi", 40.0, 30.0, _style(Align.RIGHT), 1.0)
    assert_equal(left[0].x - right[0].x, t.width("Hi", _style(Align.LEFT), 1.0))


def test_width_of_a_string_is_the_sum_of_its_parts() raises -> None:
    var t = TextRenderer()
    var style = _style(Align.LEFT)
    var whole = t.width("Hé!", style, 1.0)
    assert_true(whole > 0)
    assert_equal(
        whole,
        t.width("H", style, 1.0)
        + t.width("é", style, 1.0)
        + t.width("!", style, 1.0),
    )
    assert_equal(t.width("", style, 1.0), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
