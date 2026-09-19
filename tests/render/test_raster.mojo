from std.math import max, min
from std.testing import TestSuite, assert_equal, assert_true
from create.render.color import Color
from create.render._raster import (
    blend,
    blit_glyph,
    blit_sprite,
    fill_all,
    fill_pixels,
    fill_span,
    fill_triangle,
    line_pixels,
)
from create.render.font import _GlyphInfo
from create.render.surface import MemorySurface, Surface
from create.sprite.sprite import Sprite


def _filled(width: Int, height: Int, c: Color) raises -> MemorySurface:
    var mem = MemorySurface(width, height)
    fill_all(mem.surface(), c)
    return mem^


def test_an_opaque_blend_stores_the_color_outright() raises -> None:
    var mem = _filled(2, 2, Color(10, 20, 30, 40))
    blend(mem.surface(), mem.surface().offset(1, 1), Color(1, 2, 3, 255))
    assert_equal(mem.pixel(1, 1), Color(1, 2, 3, 255))


def test_a_fully_transparent_blend_is_a_no_op() raises -> None:
    var mem = _filled(2, 2, Color(10, 20, 30, 255))
    blend(mem.surface(), 0, Color(200, 200, 200, 0))
    assert_equal(mem.pixel(0, 0), Color(10, 20, 30, 255))


def test_a_partial_blend_composites_source_over() raises -> None:
    var dst = Color(0, 0, 0, 255)
    var src = Color(255, 100, 0, 128)
    var mem = _filled(1, 1, dst)
    blend(mem.surface(), 0, src)
    # Same arithmetic the raster path must not diverge from.
    assert_equal(mem.pixel(0, 0), src.over(dst))


def test_fill_all_covers_every_pixel() raises -> None:
    var mem = _filled(3, 2, Color.WHITE)
    for y in range(2):
        for x in range(3):
            assert_equal(
                mem.pixel(x, y),
                Color.WHITE,
                "pixel " + String(x) + "," + String(y),
            )


def test_fill_pixels_is_half_open() raises -> None:
    var mem = MemorySurface(4, 4)
    fill_pixels(mem.surface(), 1, 1, 3, 3, Color.WHITE)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(2, 2), Color.WHITE)
    # x1/y1 are exclusive.
    assert_equal(mem.pixel(3, 3).a, 0)
    assert_equal(mem.pixel(0, 0).a, 0)


def test_fill_pixels_clips_at_every_edge() raises -> None:
    var mem = MemorySurface(4, 4)
    # Straddles all four edges at once; must neither crash nor wrap a row.
    fill_pixels(mem.surface(), -10, -10, 20, 20, Color.WHITE)
    for y in range(4):
        for x in range(4):
            assert_equal(
                mem.pixel(x, y),
                Color.WHITE,
                "pixel " + String(x) + "," + String(y),
            )

    var edge = MemorySurface(4, 4)
    fill_pixels(edge.surface(), -3, 0, 1, 4, Color.WHITE)
    for y in range(4):
        assert_equal(edge.pixel(0, y), Color.WHITE, "pixel 0," + String(y))
        # A wrapped row would light up the right-hand column.
        assert_equal(edge.pixel(3, y).a, 0, "pixel 3," + String(y))


def test_fill_pixels_wholly_outside_writes_nothing() raises -> None:
    var mem = MemorySurface(4, 4)
    fill_pixels(mem.surface(), 10, 10, 20, 20, Color.WHITE)
    fill_pixels(mem.surface(), -20, -20, -10, -10, Color.WHITE)
    for y in range(4):
        for x in range(4):
            assert_equal(
                mem.pixel(x, y).a, 0, "pixel " + String(x) + "," + String(y)
            )


def test_line_pixels_covers_both_endpoints() raises -> None:
    var mem = MemorySurface(8, 8)
    line_pixels(mem.surface(), 1.0, 1.0, 6.0, 1.0, Color.WHITE, 1)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(6, 1), Color.WHITE)
    assert_equal(mem.pixel(0, 1).a, 0)
    assert_equal(mem.pixel(7, 1).a, 0)


def test_line_pixels_thickens_with_outline_thickness() raises -> None:
    var mem = MemorySurface(8, 8)
    line_pixels(mem.surface(), 1.0, 4.0, 6.0, 4.0, Color.WHITE, 3)
    # half = 3 // 2 = 1, so rows 3..5 around the line.
    assert_equal(mem.pixel(3, 3), Color.WHITE)
    assert_equal(mem.pixel(3, 4), Color.WHITE)
    assert_equal(mem.pixel(3, 5), Color.WHITE)
    assert_equal(mem.pixel(3, 6).a, 0)


def test_line_pixels_clips_outside_the_surface() raises -> None:
    var mem = MemorySurface(4, 4)
    line_pixels(mem.surface(), -5.0, 2.0, 9.0, 2.0, Color.WHITE, 1)
    for x in range(4):
        assert_equal(mem.pixel(x, 2), Color.WHITE)
    assert_equal(mem.pixel(0, 0).a, 0)


def test_line_pixels_composites_each_covered_pixel_exactly_once() raises -> (
    None
):
    # A thick alpha line must match one `over` per pixel, not several stacked
    # up from overlapping per-step stamps (which would read darker here).
    var src = Color(255, 255, 255, 128)
    var dst = Color(0, 0, 0, 255)
    var mem = _filled(8, 8, dst)
    line_pixels(mem.surface(), 1.0, 4.0, 6.0, 4.0, src, 3)
    assert_equal(mem.pixel(3, 4), src.over(dst))

    var vmem = _filled(8, 8, dst)
    line_pixels(vmem.surface(), 4.0, 1.0, 4.0, 6.0, src, 3)
    assert_equal(vmem.pixel(4, 3), src.over(dst))


def test_fill_triangle_covers_its_interior_not_its_outside() raises -> None:
    var mem = MemorySurface(8, 8)
    fill_triangle(mem.surface(), 0.0, 0.0, 6.0, 0.0, 0.0, 6.0, Color.WHITE)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(0, 0), Color.WHITE)
    # Beyond the hypotenuse.
    assert_equal(mem.pixel(5, 5).a, 0)
    assert_equal(mem.pixel(7, 7).a, 0)


def test_fill_triangle_zero_height_paints_nothing() raises -> None:
    var mem = MemorySurface(8, 8)
    fill_triangle(mem.surface(), 1.0, 3.0, 6.0, 3.0, 2.0, 3.0, Color.WHITE)
    for row in range(8):
        for col in range(8):
            assert_equal(mem.pixel(col, row).a, 0)


def test_fill_triangle_zero_width_paints_a_thin_column() raises -> None:
    var mem = MemorySurface(8, 8)
    fill_triangle(mem.surface(), 3.0, 1.0, 3.0, 6.0, 3.0, 3.0, Color.WHITE)
    for row in range(1, 7):
        assert_equal(mem.pixel(3, row), Color.WHITE)
    assert_equal(mem.pixel(2, 3).a, 0)
    assert_equal(mem.pixel(4, 3).a, 0)


def test_fill_triangle_collinear_vertices_do_not_crash() raises -> None:
    var mem = MemorySurface(8, 8)
    fill_triangle(mem.surface(), 0.0, 0.0, 3.0, 3.0, 6.0, 6.0, Color.WHITE)
    # A zero-area triangle: whatever it paints, it must not touch pixels far
    # off the line it degenerates to.
    assert_equal(mem.pixel(0, 7).a, 0)
    assert_equal(mem.pixel(7, 0).a, 0)


def test_fill_triangle_off_surface_vertices_clip_instead_of_crashing() raises -> (
    None
):
    var mem = MemorySurface(8, 8)
    # Left edge sits far off-surface at x = -20; the apex at (20, 4) is the
    # only row (y = 4) wide enough to reach all the way across the surface.
    fill_triangle(mem.surface(), -20.0, 2.0, 20.0, 4.0, -20.0, 6.0, Color.WHITE)
    assert_equal(mem.pixel(0, 4), Color.WHITE)
    assert_equal(mem.pixel(7, 4), Color.WHITE)
    assert_equal(mem.pixel(7, 7).a, 0)
    assert_equal(mem.pixel(0, 0).a, 0)


def _brute_triangle[
    o: Origin[mut=True]
](
    s: Surface[o],
    x1: Float64,
    y1: Float64,
    x2: Float64,
    y2: Float64,
    x3: Float64,
    y3: Float64,
    c: Color,
):
    """The retired per-pixel half-plane test, kept only as the reference
    that `fill_triangle`'s scanline rewrite is bounded against."""
    var W = s.width
    var H = s.height
    var min_x = max(Int(min(x1, min(x2, x3))), 0)
    var max_x = min(Int(max(x1, max(x2, x3))), W - 1)
    var min_y = max(Int(min(y1, min(y2, y3))), 0)
    var max_y = min(Int(max(y1, max(y2, y3))), H - 1)
    for row in range(min_y, max_y + 1):
        for col in range(min_x, max_x + 1):
            var d1 = (x2 - x1) * (Float64(row) - y1) - (y2 - y1) * (
                Float64(col) - x1
            )
            var d2 = (x3 - x2) * (Float64(row) - y2) - (y3 - y2) * (
                Float64(col) - x2
            )
            var d3 = (x1 - x3) * (Float64(row) - y3) - (y1 - y3) * (
                Float64(col) - x3
            )
            var has_neg = (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
            var has_pos = (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
            if not (has_neg and has_pos):
                blend(s, (row * W + col) * 4, c)


def _assert_dilation_bound(
    a: MemorySurface, b: MemorySurface, bound: Int
) raises:
    """Every ink pixel in `a` has an ink pixel in `b` within `bound` in
    Chebyshev distance, and vice versa — the same tolerance
    `test_gl_parity.mojo` applies across backends, applied here across the
    old and new triangle rasterisers."""
    var W = a.width
    var H = a.height
    for row in range(H):
        for col in range(W):
            if a.pixel(col, row).a > 0:
                var found = False
                for dy in range(-bound, bound + 1):
                    for dx in range(-bound, bound + 1):
                        var nx = col + dx
                        var ny = row + dy
                        if 0 <= nx < W and 0 <= ny < H:
                            if b.pixel(nx, ny).a > 0:
                                found = True
                assert_true(found)
            if b.pixel(col, row).a > 0:
                var found = False
                for dy in range(-bound, bound + 1):
                    for dx in range(-bound, bound + 1):
                        var nx = col + dx
                        var ny = row + dy
                        if 0 <= nx < W and 0 <= ny < H:
                            if a.pixel(nx, ny).a > 0:
                                found = True
                assert_true(found)


def test_fill_triangle_matches_the_old_half_plane_test_within_one_pixel() raises -> (
    None
):
    var triangles = List[
        Tuple[Float64, Float64, Float64, Float64, Float64, Float64]
    ]()
    triangles.append((2.0, 1.0, 15.0, 3.0, 5.0, 18.0))
    triangles.append((0.0, 0.0, 6.0, 0.0, 0.0, 6.0))
    triangles.append((3.0, 17.0, 19.0, 2.0, 1.0, 9.0))
    triangles.append((10.0, 10.0, 10.5, 20.0, 25.0, 15.0))
    triangles.append((-5.0, -5.0, 30.0, 4.0, -5.0, 30.0))
    for t in triangles:
        var got = MemorySurface(20, 20)
        var want = MemorySurface(20, 20)
        fill_triangle(
            got.surface(), t[0], t[1], t[2], t[3], t[4], t[5], Color.WHITE
        )
        _brute_triangle(
            want.surface(), t[0], t[1], t[2], t[3], t[4], t[5], Color.WHITE
        )
        _assert_dilation_bound(got, want, 1)


def test_blit_sprite_one_to_one() raises -> None:
    var sp = Sprite.solid(2, 2, 255, 0, 0)
    var mem = MemorySurface(4, 4)
    blit_sprite(
        mem.surface(), sp.pixels.unsafe_ptr(), sp.width, sp.height, 1, 1, 2, 2
    )
    assert_equal(mem.pixel(1, 1), Color(255, 0, 0, 255))
    assert_equal(mem.pixel(2, 2), Color(255, 0, 0, 255))
    assert_equal(mem.pixel(0, 0).a, 0)
    assert_equal(mem.pixel(3, 3).a, 0)


def test_blit_sprite_downscales_by_nearest_neighbour() raises -> None:
    var sp = Sprite(4, 4)
    var ptr = sp.pixels.unsafe_ptr()
    # Left half red, right half blue — a downscale must keep both halves.
    for row in range(4):
        for col in range(4):
            var off = (row * 4 + col) * 4
            ptr[unsafe_offset=off] = 255 if col < 2 else 0
            ptr[unsafe_offset=off + 1] = 0
            ptr[unsafe_offset=off + 2] = 0 if col < 2 else 255
            ptr[unsafe_offset=off + 3] = 255
    var mem = MemorySurface(4, 4)
    blit_sprite(
        mem.surface(), sp.pixels.unsafe_ptr(), sp.width, sp.height, 0, 0, 2, 2
    )
    assert_equal(mem.pixel(0, 0), Color(255, 0, 0, 255))
    assert_equal(mem.pixel(1, 0), Color(0, 0, 255, 255))
    assert_equal(mem.pixel(0, 2).a, 0)


def test_blit_sprite_skips_transparent_source_pixels() raises -> None:
    var sp = Sprite(2, 1)
    var ptr = sp.pixels.unsafe_ptr()
    ptr[unsafe_offset=0] = 255
    ptr[unsafe_offset=3] = 255  # opaque red
    ptr[unsafe_offset=7] = 0  # fully transparent
    var mem = _filled(2, 1, Color(9, 9, 9, 255))
    blit_sprite(
        mem.surface(), sp.pixels.unsafe_ptr(), sp.width, sp.height, 0, 0, 2, 1
    )
    assert_equal(mem.pixel(0, 0), Color(255, 0, 0, 255))
    assert_equal(mem.pixel(1, 0), Color(9, 9, 9, 255))


def test_blit_sprite_clips_against_every_edge() raises -> None:
    var sp = Sprite.solid(4, 4, 255, 255, 255)
    var mem = MemorySurface(4, 4)
    # Anchored off the top-left: only the bottom-right quarter lands.
    blit_sprite(
        mem.surface(), sp.pixels.unsafe_ptr(), sp.width, sp.height, -2, -2, 4, 4
    )
    assert_equal(mem.pixel(0, 0), Color.WHITE)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(2, 2).a, 0)

    var far = MemorySurface(4, 4)
    blit_sprite(
        far.surface(), sp.pixels.unsafe_ptr(), sp.width, sp.height, 3, 3, 4, 4
    )
    assert_equal(far.pixel(3, 3), Color.WHITE)
    # A wrapped row would light up column 0.
    assert_equal(far.pixel(0, 3).a, 0)


def _glyph(width: Int, height: Int, coverage: UInt8) raises -> _GlyphInfo:
    var g = _GlyphInfo(width, height, 0, 0, width)
    var p = g.pixels.unsafe_ptr()
    for i in range(width * height):
        p[unsafe_offset=i] = coverage
    return g^


def test_blit_glyph_scales_the_fill_alpha_by_coverage() raises -> None:
    var g = _glyph(2, 2, 128)
    var mem = _filled(4, 4, Color(0, 0, 0, 255))
    blit_glyph(mem.surface(), g, 1, 1, Color(255, 255, 255, 255))
    # cov 128 of an opaque white fill: half-strength, composited over black.
    var expected = Color(255, 255, 255, UInt8(128 * 255 // 255)).over(
        Color(0, 0, 0, 255)
    )
    assert_equal(mem.pixel(1, 1), expected)
    assert_equal(mem.pixel(0, 0), Color(0, 0, 0, 255))


def test_blit_glyph_skips_zero_coverage() raises -> None:
    var g = _glyph(2, 2, 0)
    var mem = _filled(2, 2, Color(7, 7, 7, 255))
    blit_glyph(mem.surface(), g, 0, 0, Color.WHITE)
    assert_equal(mem.pixel(0, 0), Color(7, 7, 7, 255))


def test_blit_glyph_clips_against_the_surface() raises -> None:
    var g = _glyph(4, 4, 255)
    var mem = MemorySurface(4, 4)
    blit_glyph(mem.surface(), g, -2, -2, Color.WHITE)
    assert_equal(mem.pixel(0, 0), Color.WHITE)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(2, 2).a, 0)

    var far = MemorySurface(4, 4)
    blit_glyph(far.surface(), g, 3, 3, Color.WHITE)
    assert_equal(far.pixel(3, 3), Color.WHITE)
    assert_equal(far.pixel(0, 3).a, 0)


def _blend_span_reference(
    mut mem: MemorySurface, x0: Int, count: Int, y: Int, c: Color
) raises:
    """The per-pixel loop `fill_span` replaces, kept here as the ground truth
    its output must still match byte-for-byte."""
    var s = mem.surface()
    for i in range(count):
        blend(s, (y * mem.width + x0 + i) * 4, c)


def test_fill_span_is_half_open() raises -> None:
    var mem = MemorySurface(4, 4)
    fill_span(mem.surface(), (1 * 4 + 1) * 4, 2, Color.WHITE)
    assert_equal(mem.pixel(1, 1), Color.WHITE)
    assert_equal(mem.pixel(2, 1), Color.WHITE)
    assert_equal(mem.pixel(3, 1).a, 0)
    assert_equal(mem.pixel(0, 1).a, 0)


def test_fill_span_opaque_matches_blend() raises -> None:
    var mem = MemorySurface(6, 1)
    var expected = MemorySurface(6, 1)
    fill_span(mem.surface(), 4, 4, Color(10, 20, 30, 255))
    _blend_span_reference(expected, 1, 4, 0, Color(10, 20, 30, 255))
    for x in range(6):
        assert_equal(
            mem.pixel(x, 0), expected.pixel(x, 0), "pixel " + String(x)
        )


def test_fill_span_alpha_matches_blend() raises -> None:
    var mem = _filled(6, 1, Color(5, 6, 7, 255))
    var expected = _filled(6, 1, Color(5, 6, 7, 255))
    fill_span(mem.surface(), 4, 4, Color(200, 100, 0, 128))
    _blend_span_reference(expected, 1, 4, 0, Color(200, 100, 0, 128))
    for x in range(6):
        assert_equal(
            mem.pixel(x, 0), expected.pixel(x, 0), "pixel " + String(x)
        )


def test_fill_span_with_zero_alpha_is_a_no_op() raises -> None:
    var mem = _filled(3, 1, Color(1, 2, 3, 255))
    fill_span(mem.surface(), 0, 3, Color(200, 200, 200, 0))
    for x in range(3):
        assert_equal(mem.pixel(x, 0), Color(1, 2, 3, 255))


def test_fill_span_alpha_matches_over_exhaustively() raises -> None:
    """Every 8-bit alpha value must blend identically through the SIMD span
    path and through `Color.over` — not just the handful of values the other
    tests happen to exercise. `fill_span` widens to `uint32` lanes with the
    source alpha lane set to 255 rather than `c.a`; this is the test that
    the resulting `(src*a + dst*ia) // 255` agrees with `Color.over`'s
    scalar formula at every value, including the a=0 and a=255 edges routed
    through different branches entirely.
    """
    var dst = Color(200, 150, 50, 255)
    var src_rgb = Color(10, 90, 180, 0)
    for a in range(256):
        var c = Color(src_rgb.r, src_rgb.g, src_rgb.b, UInt8(a))
        var expected = c.over(dst)
        var mem = _filled(4, 1, dst)
        fill_span(mem.surface(), 0, 4, c)
        for x in range(4):
            assert_equal(mem.pixel(x, 0), expected, "alpha " + String(a))


def test_fill_all_matches_the_reference_blend_loop() raises -> None:
    var opaque = _filled(5, 5, Color(9, 8, 7, 255))
    var ref_opaque = MemorySurface(5, 5)
    _blend_span_reference(ref_opaque, 0, 25, 0, Color(9, 8, 7, 255))
    for i in range(25):
        assert_equal(
            opaque.pixel(i % 5, i // 5), ref_opaque.pixel(i % 5, i // 5)
        )

    var alpha = _filled(5, 5, Color(9, 8, 7, 128))
    var ref_alpha = MemorySurface(5, 5)
    _blend_span_reference(ref_alpha, 0, 25, 0, Color(9, 8, 7, 128))
    for i in range(25):
        assert_equal(alpha.pixel(i % 5, i // 5), ref_alpha.pixel(i % 5, i // 5))


def test_fill_pixels_matches_the_reference_blend_loop() raises -> None:
    var mem = MemorySurface(8, 8)
    var expected = MemorySurface(8, 8)
    var c = Color(50, 60, 70, 90)
    fill_pixels(mem.surface(), 2, 2, 6, 6, c)
    for y in range(2, 6):
        _blend_span_reference(expected, 2, 4, y, c)
    for y in range(8):
        for x in range(8):
            assert_equal(
                mem.pixel(x, y),
                expected.pixel(x, y),
                "pixel " + String(x) + "," + String(y),
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
