"""What a transform means to a rasteriser, independent of which one.

Three questions every backend asks of a `DrawCommand`'s matrix — is it
axis-aligned, how many pixels is a world unit, how thick is a stroke — and one
answer each, so the CPU replay and the GL tessellator cannot disagree about
them. They lived in `_backend.mojo` until the GL backend needed them too;
importing them from there would have closed a cycle, since `_backend` reaches
the GL renderer and the GL renderer reaches the tessellator.

Device-space *scanning* is not here: `device_bounds` stays with the CPU replay
that scans, because nothing else has rows to walk.
"""

from std.math import abs, max

from create.math.matrix import Matrix

from ._style import Style


def uniform(m: Matrix[3, 3]) -> Bool:
    """True when `m` is an axis-aligned uniform scale plus a translation — a
    rect stays a rect, a circle stays a circle.

    The base mapping alone qualifies (it scales by `s` and `-s`), so plain
    drawing keeps the integer raster paths even under autoscale. Only
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

    Outline thickness, font size and sprite extents are authored in world
    units but rasterised in pixels, so they all scale by this. `fallback` is
    the frame's autoscale factor, used when `m` is not uniform and no single
    factor exists.
    """
    if uniform(m):
        return abs(m[0, 0])
    return fallback


def outline_thickness_px(
    style: Style, m: Matrix[3, 3], fallback: Float64
) -> Int:
    """Outline thickness in framebuffer pixels, never thinner than one."""
    return max(
        Int(Float64(style.outline_thickness) * pixel_scale(m, fallback) + 0.5),
        1,
    )
