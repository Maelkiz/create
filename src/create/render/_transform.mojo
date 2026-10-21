"""What a transform means to a rasteriser, independent of which one.

Three questions every backend asks of a `RenderCommand`'s matrix — is it
axis-aligned, how many pixels is a world unit, how thick is an outline — and one
answer each, so the CPU replay and the GL tessellator cannot disagree about
them. They lived in `_backend.mojo` until the GL backend needed them too;
importing them from there would have closed a cycle, since `_backend` reaches
the GL renderer and the GL renderer reaches the tessellator.

Device-space *scanning* is not here: `device_bounds` stays with the CPU replay
that scans, because nothing else has rows to walk.
"""

from std.math import abs, max, sqrt

from create.math.matrix import Matrix, scale as mat_scale, translate

from .style import Style


def uniform(m: Matrix[3, 3]) -> Bool:
    """True when `m` is an axis-aligned uniform scale plus a translation — a
    rect stays a rect, a circle stays a circle.

    The base mapping alone qualifies (it scales by `s` and `-s`), so plain
    rendering keeps the integer raster paths even under autoscale. Only
    rotation, shear, and non-uniform scales fall through to the per-pixel
    inverse mapping.
    """
    return (
        m[0, 1] == 0.0
        and m[1, 0] == 0.0
        and m[2, 0] == 0.0
        and m[2, 1] == 0.0
        and m[2, 2] == 1.0
        and abs(m[0, 0]) == abs(m[1, 1])
    )


def pixel_scale(m: Matrix[3, 3], fallback: Float64) -> Float64:
    """Pixels per world unit along `m`.

    Outline thickness, font size and image extents are authored in world
    units but rasterised in pixels, so they all scale by this. `fallback` is
    the frame's autoscale factor, used when `m` is not uniform and no single
    factor exists.
    """
    if uniform(m):
        return abs(m[0, 0])
    return fallback


def text_pixel_scale(m: Matrix[3, 3], fallback: Float64) -> Float64:
    """Pixels per world unit that text is laid out and rasterised at under
    `m`: `pixel_scale` where that has a single factor, and otherwise the
    square root of `m`'s area scale, so a turned, sheared or stretched
    string is rasterised at about the density it lands at rather than at
    the frame's. `fallback` only for a singular `m`."""
    if uniform(m):
        return abs(m[0, 0])
    var area = abs(m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0])
    if area == 0.0:
        return fallback
    return sqrt(area)


def text_upright(m: Matrix[3, 3]) -> Bool:
    """True when text under `m` lays out as it is drawn: an axis-aligned
    uniform scale, unmirrored, so glyphs land upright on whole pixels around
    the mapped anchor. Any other `m` lays text out upright first and maps
    the result through `glyph_transform`."""
    return uniform(m) and m[0, 0] > 0.0 and m[1, 1] < 0.0


def glyph_transform(
    m: Matrix[3, 3], x: Float64, y: Float64, pixel_scale: Float64
) -> Matrix[3, 3]:
    """Where text laid out upright around the origin, at `pixel_scale`
    pixels per unit (device-style: y down), lands under `m` when anchored
    at local `(x, y)`: back to local units about the anchor, then `m`."""
    return (
        m @ translate(x, y) @ mat_scale(1.0 / pixel_scale, -1.0 / pixel_scale)
    )


def outline_thickness_px(
    style: Style, m: Matrix[3, 3], fallback: Float64
) -> Int:
    """Outline thickness in framebuffer pixels, never thinner than one."""
    return max(
        Int(style.outline_thickness * pixel_scale(m, fallback) + 0.5),
        1,
    )
