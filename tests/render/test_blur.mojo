from std.testing import TestSuite, assert_equal, assert_true

from create.render._blur import blur_alpha, blur_image_alpha, box_widths


def _block(
    width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int
) -> List[UInt8]:
    """A `width` x `height` mask, opaque over `[x0, x1) x [y0, y1)`."""
    var a = List[UInt8](length=width * height, fill=0)
    for y in range(y0, y1):
        for x in range(x0, x1):
            a[y * width + x] = 255
    return a^


def _mass(a: List[UInt8]) -> Int:
    var total = 0
    for v in a:
        total += Int(v)
    return total


def test_box_widths_are_odd_and_sum_to_the_variance() raises -> None:
    for sigma in [0.8, 2.0, 4.0, 7.5, 20.0]:
        var w = box_widths(sigma)
        var variance = 0.0
        for i in range(3):
            assert_equal(w[i] % 2, 1)
            variance += Float64(w[i] * w[i] - 1) / 12.0
        # Kovesi's mix lands within one width step of sigma^2.
        assert_true(abs(variance - sigma * sigma) <= sigma + 1.0)


def test_zero_sigma_returns_the_mask_unchanged() raises -> None:
    var a = _block(6, 5, 1, 1, 4, 3)
    var m = blur_alpha(a, 6, 5, 0.0)
    assert_equal(m.pad, 0)
    assert_equal(m.width, 6)
    assert_equal(m.height, 5)
    for i in range(30):
        assert_equal(m.pixels[i], a[i])


def test_the_mask_grows_by_the_kernel_reach() raises -> None:
    var m = blur_alpha(_block(10, 8, 0, 0, 10, 8), 10, 8, 4.0)
    var w = box_widths(4.0)
    var reach = (w[0] - 1) // 2 + (w[1] - 1) // 2 + (w[2] - 1) // 2
    assert_equal(m.pad, reach)
    assert_equal(m.width, 10 + 2 * reach)
    assert_equal(m.height, 8 + 2 * reach)
    # Ink reaches all but the last pixel of the reach, whose share of the
    # kernel rounds away — so the pad cuts nothing off.
    var edge = 0
    for x in range(m.width):
        edge += Int(m.pixels[m.width + x])
    assert_true(edge > 0)


def test_the_kernel_preserves_mass() raises -> None:
    var a = _block(24, 24, 6, 6, 18, 18)
    var m = blur_alpha(a, 24, 24, 3.0)
    var before = _mass(a)
    var after = _mass(m.pixels)
    # Rounding each pixel once costs at most half a level per pixel.
    assert_true(abs(after - before) <= m.width * m.height // 2)
    assert_true(abs(after - before) * 100 <= before)


def test_a_blur_is_symmetric_and_peaks_in_the_middle() raises -> None:
    var m = blur_alpha(_block(9, 9, 3, 3, 6, 6), 9, 9, 2.0)
    var mid = m.height // 2
    var row = mid * m.width
    for x in range(m.width):
        assert_equal(m.pixels[row + x], m.pixels[row + m.width - 1 - x])
    var peak = m.pixels[row + m.width // 2]
    for x in range(m.width):
        assert_true(m.pixels[row + x] <= peak)
    # A 3x3 block spread by sigma 2 no longer reaches full alpha.
    assert_true(peak < 255)


def test_a_image_is_resampled_before_blurring() raises -> None:
    # 2x1 RGBA, left texel transparent, right opaque, drawn 8x4: the opaque
    # half covers device columns 4..7, so the unblurred mask splits there.
    var src = List[UInt8](length=8, fill=0)
    src[7] = 255
    var m = blur_image_alpha(src.unsafe_ptr(), 2, 1, 8, 4, 0.0)
    assert_equal(m.width, 8)
    assert_equal(m.height, 4)
    for y in range(4):
        for x in range(8):
            assert_equal(m.pixels[y * 8 + x], UInt8(255 if x >= 4 else 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
