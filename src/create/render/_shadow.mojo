"""A `RenderCommand`'s shadow, as another `RenderCommand`.

Both replays paint an outer shadow by rendering the command this builds
before the command itself, so what a shadow *is* — where it lands, which
silhouette it takes, how spread grows it — is decided once, here, and the CPU
and GL paths cannot drift on it.

**One layer.** A shadow is a single silhouette in `shadow_color`, never a
fill-shadow plus an outline-shadow: those overlap along the outline, and a
translucent shadow colour would darken the overlap twice. With the fill
visible the silhouette is the whole shape out to the outline's outer edge;
with only the outline visible it is the ring.

**Growing a shape by `d`** (the outline's outward extent plus spread) is the
Minkowski sum with a disc of radius `d`: every edge moves out by `d` and every
corner rounds by `d` more, centred on the original vertex. That is exactly
what a larger `corner_radius` on the grown rectangle or triangle renders, so
no new shape kind is needed. `corner_radius` is a whole number of world
units, so the rounding is to the nearest unit; the edges themselves are exact.
"""

from std.math import abs, max, sqrt

from create.math.matrix import Matrix, translate

from ._command import (
    CMD_CIRCLE,
    CMD_LINE,
    CMD_RECT,
    CMD_SPRITE,
    CMD_TEXT,
    CMD_TRIANGLE,
    RenderCommand,
)
from ._transform import outline_thickness_px, pixel_scale


def casts_outer_shadow(c: RenderCommand) -> Bool:
    """Whether `c` paints an outer shadow before itself.

    Only render calls cast one — never a clear or the letterbox — and only
    when they paint something a silhouette could be taken from.
    """
    if not c.style._shadow_visible() or c.style.shadow_inset:
        return False
    if c.kind == CMD_RECT or c.kind == CMD_CIRCLE or c.kind == CMD_TRIANGLE:
        return c.style._fill_visible() or c.style._outline_visible()
    if c.kind == CMD_LINE:
        return c.style._outline_visible()
    if c.kind == CMD_TEXT:
        return c.style.text_color.a > 0
    return c.kind == CMD_SPRITE


def shadow_transform(c: RenderCommand, scale: Float64) -> Matrix[3, 3]:
    """`c.transform` moved by the shadow offset.

    Screen-fixed by default: the offset becomes a device translation composed
    *after* the transform, so a rotating shape keeps its shadow falling the
    same way — only its length follows the pixel scale (autoscale, camera
    zoom). Device rows run downwards, hence `-oy`. With
    `shadow_follows_transform` the offset is local, composed *before* the
    transform, and turns with the shape.
    """
    var o = c.style.shadow_offset
    if c.style.shadow_follows_transform:
        return c.transform @ translate(o.x, o.y)
    var sf = pixel_scale(c.transform, scale)
    return translate(o.x * sf, -o.y * sf) @ c.transform


def _grow_triangle(mut c: RenderCommand, d: Float64):
    """Move each vertex out along its corner's bisector so every edge lands
    `d` further out. Shrinks for a negative `d`; a degenerate triangle is left
    alone."""
    var xs = Array[Float64, 3](fill=0.0)
    var ys = Array[Float64, 3](fill=0.0)
    var out = Array[Float64, 6](fill=0.0)
    for i in range(3):
        xs[i] = c.geom[2 * i]
        ys[i] = c.geom[2 * i + 1]
    for i in range(3):
        var px = xs[(i + 2) % 3]
        var py = ys[(i + 2) % 3]
        var nx = xs[(i + 1) % 3]
        var ny = ys[(i + 1) % 3]
        var l1 = sqrt((px - xs[i]) ** 2 + (py - ys[i]) ** 2)
        var l2 = sqrt((nx - xs[i]) ** 2 + (ny - ys[i]) ** 2)
        if l1 <= 0.0 or l2 <= 0.0:
            return
        var ux = (px - xs[i]) / l1
        var uy = (py - ys[i]) / l1
        var wx = (nx - xs[i]) / l2
        var wy = (ny - ys[i]) / l2
        # `u + w` points inward along the bisector; its length is
        # `2 cos(theta/2)` and the vertex has to move `d / sin(theta/2)`.
        var bx = ux + wx
        var by = uy + wy
        var bl = sqrt(bx * bx + by * by)
        var cross = ux * wy - uy * wx
        var sin_half = sqrt(max(0.0, (1.0 - (ux * wx + uy * wy)) / 2.0))
        if bl <= 1e-12 or sin_half <= 1e-6 or abs(cross) <= 1e-12:
            return
        var k = d / sin_half
        out[2 * i] = xs[i] - bx / bl * k
        out[2 * i + 1] = ys[i] - by / bl * k
    for i in range(6):
        c.geom[i] = out[i]


def shadow_command(c: RenderCommand, scale: Float64) -> RenderCommand:
    """The hard silhouette `c` casts, ready to replay before `c`.

    Assumes `casts_outer_shadow(c)`. Blur is carried along in the style for
    the replays that soften it; the geometry here is the unblurred shape.
    Spread is in world units, like the outline thickness, and rounds to it
    where it widens a stroke.
    """
    var s = c.copy()
    s.transform = shadow_transform(c, scale)
    s.style.shadow_enabled = False
    var color = c.style.shadow_color
    var spread = c.style.shadow_spread

    if c.kind == CMD_TEXT:
        s.style.text_color = color
        return s^
    if c.kind == CMD_SPRITE:
        s.style.fill_color = color
        s.silhouette = True
        return s^

    var ring = not c.style._fill_visible() or c.kind == CMD_LINE
    if ring:
        # The stroke alone, dilated by `spread` on both sides.
        s.style.fill_enabled = False
        s.style.outline_color = color
        s.style.outline_enabled = True
        s.style.outline_thickness = max(
            c.style.outline_thickness + Int(round(2.0 * spread)), 0
        )
        if c.kind == CMD_RECT:
            s.geom[2] = max(s.geom[2] + 2.0 * spread, 0.0)
            s.geom[3] = max(s.geom[3] + 2.0 * spread, 0.0)
            s.style.corner_radius = max(
                c.style.corner_radius + Int(round(spread)), 0
            )
        elif c.kind == CMD_CIRCLE:
            s.geom[2] = max(s.geom[2] + spread, 0.0)
        return s^

    s.style.fill_color = color
    s.style.fill_enabled = True
    s.style.outline_enabled = False
    # Rectangle and circle outlines are inset rings, so the fill's edge is
    # already the outer edge; a triangle's outline is centred on its edges and
    # reaches half its width further out.
    var d = spread
    if c.kind == CMD_TRIANGLE and c.style._outline_visible():
        var sf = pixel_scale(c.transform, scale)
        d += Float64(outline_thickness_px(c.style, c.transform, scale)) / (
            2.0 * sf
        )
    if c.kind == CMD_RECT:
        s.geom[2] = max(s.geom[2] + 2.0 * d, 0.0)
        s.geom[3] = max(s.geom[3] + 2.0 * d, 0.0)
        s.style.corner_radius = max(c.style.corner_radius + Int(round(d)), 0)
    elif c.kind == CMD_CIRCLE:
        s.geom[2] = max(s.geom[2] + d, 0.0)
    elif c.kind == CMD_TRIANGLE:
        _grow_triangle(s, d)
        s.style.corner_radius = max(c.style.corner_radius + Int(round(d)), 0)
    return s^
