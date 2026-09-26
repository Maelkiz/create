"""Gaussian blur of an alpha mask, for the shadows no formula describes.

A shape's blurred shadow is evaluated analytically (`_shadow.mojo`); a glyph's
or a sprite's silhouette is an arbitrary mask, so it is blurred as pixels
instead — once, and cached by whoever owns the mask.

Three box blurs in a row approximate a Gaussian closely, and each costs the
same per pixel whatever its width, through a running sum. The box widths come
from W. Kovesi, "Fast Almost-Gaussian Filtering" (2010): the two odd widths
bracketing the ideal one, mixed so the three passes' variances sum to
`sigma` squared.
"""

from std.math import floor, sqrt


comptime _PASSES = 3


comptime SHADOW_MASK_LIMIT = 256
"""Blurred sprite masks a cache keeps before it is dropped whole — the same
policy, for the same reason, as `_text._GLYPH_CACHE_LIMIT`. Both backends'
caches (CPU masks, GL textures) use it."""


def shadow_mask_key(image: Int, width: Int, height: Int, blur: Int) -> Int:
    """Pack what a blurred sprite mask depends on into one key: 24 bits of
    image id, 15 each of device width and height, and 10 of blur."""
    return (
        image
        | (min(width, 0x7FFF) << 24)
        | (min(height, 0x7FFF) << 39)
        | (min(blur, 0x3FF) << 54)
    )


struct BlurredMask(Movable):
    """An alpha mask blurred, grown by `pad` pixels on every side.

    The blur reaches exactly `pad` pixels past the source — a box kernel has
    compact support — so nothing is cut off and nothing wasted.
    """

    var pixels: List[UInt8]
    """8-bit alpha, row-major, `width` x `height`."""
    var width: Int
    var height: Int
    var pad: Int
    """How far the mask grew on each side; the source's `(0, 0)` sits at
    `(pad, pad)`."""

    def __init__(
        out self, var pixels: List[UInt8], width: Int, height: Int, pad: Int
    ):
        self.pixels = pixels^
        self.width = width
        self.height = height
        self.pad = pad


def box_widths(sigma: Float64) -> Array[Int, 3]:
    """The three odd box widths whose variances sum closest to `sigma`^2.

    Each is at least 1 (the identity), so a tiny `sigma` degrades to no blur
    rather than to nonsense.
    """
    var n = Float64(_PASSES)
    var ideal = sqrt(12.0 * sigma * sigma / n + 1.0)
    var lower = Int(floor(ideal))
    if lower % 2 == 0:
        lower -= 1
    lower = max(lower, 1)
    var upper = lower + 2
    var wl = Float64(lower)
    var m = Int(
        (12.0 * sigma * sigma - n * wl * wl - 4.0 * n * wl - 3.0 * n)
        / (-4.0 * wl - 4.0)
        + 0.5
    )
    var widths = Array[Int, 3](fill=upper)
    for i in range(_PASSES):
        if i < m:
            widths[i] = lower
    return widths^


def blur_reach(sigma: Float64) -> Int:
    """How far a blur of `sigma` pixels spreads past its source: the sum of
    the three boxes' radii, and so `BlurredMask.pad`."""
    if sigma <= 0.0:
        return 0
    var widths = box_widths(sigma)
    var reach = 0
    for i in range(_PASSES):
        reach += (widths[i] - 1) // 2
    return reach


def _box_rows(
    src: List[Float32], mut dst: List[Float32], width: Int, height: Int, r: Int
):
    """Each row of `src` averaged over a `2r + 1` window, zero outside."""
    var inv = Float32(1.0) / Float32(2 * r + 1)
    for y in range(height):
        var row = y * width
        var sum = Float32(0.0)
        for x in range(min(r, width - 1) + 1):
            sum += src[row + x]
        for x in range(width):
            dst[row + x] = sum * inv
            if x + r + 1 < width:
                sum += src[row + x + r + 1]
            if x - r >= 0:
                sum -= src[row + x - r]


def _box_columns(
    src: List[Float32], mut dst: List[Float32], width: Int, height: Int, r: Int
):
    """Each column of `src` averaged over a `2r + 1` window, zero outside."""
    var inv = Float32(1.0) / Float32(2 * r + 1)
    for x in range(width):
        var sum = Float32(0.0)
        for y in range(min(r, height - 1) + 1):
            sum += src[y * width + x]
        for y in range(height):
            dst[y * width + x] = sum * inv
            if y + r + 1 < height:
                sum += src[(y + r + 1) * width + x]
            if y - r >= 0:
                sum -= src[(y - r) * width + x]


def blur_alpha(
    alpha: List[UInt8], width: Int, height: Int, sigma: Float64
) -> BlurredMask:
    """`alpha` (`width` x `height`, one byte per pixel) blurred by a Gaussian
    of standard deviation `sigma` pixels, padded to hold all of it.

    Accumulates in `Float32` and rounds once at the end, so the three passes
    don't each lose half a level to rounding: the mask's total mass comes back
    to within rounding of what went in.
    """
    if sigma <= 0.0:
        return BlurredMask(alpha.copy(), width, height, 0)
    var widths = box_widths(sigma)
    var pad = blur_reach(sigma)
    var w = width + 2 * pad
    var h = height + 2 * pad
    var a = List[Float32](length=w * h, fill=0.0)
    var b = List[Float32](length=w * h, fill=0.0)
    for y in range(height):
        for x in range(width):
            a[(y + pad) * w + x + pad] = Float32(alpha[y * width + x])
    for i in range(_PASSES):
        var r = (widths[i] - 1) // 2
        if r == 0:
            continue
        _box_rows(a, b, w, h, r)
        _box_columns(b, a, w, h, r)
    var out = List[UInt8](length=w * h, fill=0)
    for i in range(w * h):
        out[i] = UInt8(min(max(Int(a[i] + 0.5), 0), 255))
    return BlurredMask(out^, w, h, pad)


def blur_sprite_alpha[
    so: Origin
](
    src: Pointer[UInt8, so],
    src_width: Int,
    src_height: Int,
    width: Int,
    height: Int,
    sigma: Float64,
) -> BlurredMask:
    """The alpha of the `src_width` x `src_height` RGBA image at `src`,
    resampled to `width` x `height` and blurred by `sigma` pixels.

    Resampled first, with the same nearest-neighbour mapping `blit_sprite`
    uses, so the blur is in device pixels: blurring a small image before
    scaling it up would magnify its blur into blocks.
    """
    var alpha = List[UInt8](length=width * height, fill=0)
    for row in range(height):
        var src_row = (row * src_height // height) * src_width
        for col in range(width):
            var src_col = col * src_width // width
            alpha[row * width + col] = src[
                unsafe_offset=(src_row + src_col) * 4 + 3
            ]
    return blur_alpha(alpha, width, height, sigma)
