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

**Blur** is a Gaussian of standard deviation `sigma = shadow_blur / 2`, as in
CSS, evaluated analytically per pixel rather than by blurring an image: the
coverage functions at the bottom of this file give the blurred silhouette's
alpha at a point from its distances to the silhouette's edges. They are
spelled out again in the GL shader, so keep the two in step.
"""

from std.math import abs, exp, max, min, sqrt

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
from ._fillet import rect_corner_radius
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


# --- Blur coverage -----------------------------------------------------------
#
# Distances are signed, positive inside the silhouette, and already divided by
# sigma: that is what the GL path interpolates per vertex, and it keeps a zero
# sigma (a hard shadow) out of these functions entirely.


def gaussian_cdf(x: Float64) -> Float64:
    """The standard normal CDF: the share of a unit Gaussian left of `x`.

    Abramowitz and Stegun 7.1.26 for `erf`, good to 1.5e-7 — GLSL has no
    `erf`, so the shader uses the same polynomial and both replays agree.
    """
    # Past four sigma the result rounds to 0 or 1 in any 8-bit channel, and
    # skipping `exp` there makes a blurred shadow's interior nearly free.
    if x >= 4.0:
        return 1.0
    if x <= -4.0:
        return 0.0
    var z = abs(x) / sqrt(2.0)
    var t = 1.0 / (1.0 + 0.3275911 * z)
    var poly = t * (
        0.254829592
        + t
        * (
            -0.284496736
            + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))
        )
    )
    var erf = 1.0 - poly * exp(-z * z)
    return 0.5 * (1.0 + erf) if x >= 0.0 else 0.5 * (1.0 - erf)


def box_coverage(
    left: Float64, right: Float64, bottom: Float64, top: Float64
) -> Float64:
    """A blurred rectangle's alpha, exactly, from a point's distances to its
    four edges.

    The Gaussian is separable, so the blurred rectangle is the product of
    two blurred slabs, and a slab is the share of the Gaussian between its
    two edges: `cdf(left) + cdf(right) - 1`. Being isotropic, it holds for a
    rotated rectangle measured in its own frame.
    """
    var x = gaussian_cdf(left) + gaussian_cdf(right) - 1.0
    var y = gaussian_cdf(bottom) + gaussian_cdf(top) - 1.0
    return max(x, 0.0) * max(y, 0.0)


def edge_coverage(
    d0: Float64, d1: Float64, d2: Float64, d3: Float64 = 1e9
) -> Float64:
    """A blurred convex polygon's alpha, approximately, from a point's
    distances to up to four edges (a triangle leaves `d3` at its default).

    The product of the blurred half-planes: exact along an edge far from
    the others, slightly heavy where the shape narrows below a few sigma —
    there is no closed form for a blurred triangle. A rectangle has one, so
    it goes through `box_coverage` instead.
    """
    return (
        gaussian_cdf(d0)
        * gaussian_cdf(d1)
        * gaussian_cdf(d2)
        * gaussian_cdf(d3)
    )


def rounded_rect_coverage(
    px: Float64,
    py: Float64,
    half_w: Float64,
    half_h: Float64,
    radius: Float64,
) -> Float64:
    """A blurred rounded rectangle's alpha at `(px, py)` relative to its
    centre; every length already divided by sigma.

    One Gaussian step across the signed distance to the outline — exact
    along the straight edges, a close approximation around a corner. A
    circle is the case `half_w == half_h == radius`.
    """
    var r = min(radius, min(half_w, half_h))
    var qx = abs(px) - (half_w - r)
    var qy = abs(py) - (half_h - r)
    var ox = max(qx, 0.0)
    var oy = max(qy, 0.0)
    var sdf = sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0.0) - r
    return gaussian_cdf(-sdf)


# --- Blurred silhouettes -----------------------------------------------------

comptime BLUR_REACH = 4.0
"""How many sigma a blurred shadow reaches past its silhouette before
`gaussian_cdf` rounds it to nothing."""

comptime _SIL_RECT = 0
"""`[cx, cy, half_w, half_h, radius]`: a rectangle, rounded or not; a
circle is one with all three extents equal."""
comptime _SIL_TRIANGLE = 1
"""`[nx, ny, c] x 3`: each edge's inward unit normal and offset."""
comptime _SIL_LINE = 2
"""`[x0, y0, ux, uy, length, half_thickness]`: a stroke's rectangle, in its
own frame."""


def blurs_analytically(c: RenderCommand) -> Bool:
    """Whether `c`'s shadow blurs through `BlurredSilhouette` rather than
    as an image: the shapes and lines, whose edges are known exactly."""
    return (
        c.kind == CMD_RECT
        or c.kind == CMD_CIRCLE
        or c.kind == CMD_TRIANGLE
        or c.kind == CMD_LINE
    )


def local_outline_thickness(
    c: RenderCommand, m: Matrix[3, 3], scale: Float64
) -> Float64:
    """`c`'s outline as the rasterisers draw it — rounded to whole pixels,
    never under one — back in local units."""
    return Float64(outline_thickness_px(c.style, m, scale)) / pixel_scale(
        m, scale
    )


def _triangle_edges(
    xs: Array[Float64, 3], ys: Array[Float64, 3]
) -> Array[Float64, 9]:
    """Inward unit normal `(nx, ny)` and offset `c` per edge, so the signed
    distance of `(x, y)` inside edge `i` is `nx * x + ny * y + c`."""
    var out = Array[Float64, 9](fill=0.0)
    var cross = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (ys[1] - ys[0]) * (
        xs[2] - xs[0]
    )
    var sign = 1.0 if cross >= 0.0 else -1.0
    for i in range(3):
        var j = (i + 1) % 3
        var ex = xs[j] - xs[i]
        var ey = ys[j] - ys[i]
        var l = sqrt(ex * ex + ey * ey)
        if l <= 0.0:
            continue
        var nx = -ey / l * sign
        var ny = ex / l * sign
        out[3 * i] = nx
        out[3 * i + 1] = ny
        out[3 * i + 2] = -(nx * xs[i] + ny * ys[i])
    return out^


struct BlurredSilhouette(Copyable, Movable):
    """A shadow silhouette with its Gaussian blur, as coverage at any local
    point.

    Built from the command `shadow_command` returns, in that command's
    local units. A ring (an outline-only shape) is the outer shape minus the
    inner one: blurring is linear, so the blurred ring is the difference of
    the two blurred shapes, exactly. A triangle's `corner_radius` is left
    out — its blurred corners are the product of their two edges'.
    """

    var kind: Int
    var inv_sigma: Float64
    var outer: Array[Float64, 9]
    var inner: Array[Float64, 9]
    var has_inner: Bool
    var x0: Float64
    var y0: Float64
    var x1: Float64
    var y1: Float64
    """The outer silhouette's local bounds, before the blur's reach."""

    def __init__(out self, sh: RenderCommand, thickness: Float64):
        """`sh` is a shadow command; `thickness` its outline in local units
        (see `local_outline_thickness`)."""
        self.inv_sigma = (
            2.0 / sh.style.shadow_blur if sh.style.shadow_blur > 0.0 else 0.0
        )
        self.outer = Array[Float64, 9](fill=0.0)
        self.inner = Array[Float64, 9](fill=0.0)
        self.has_inner = False
        var ring = not sh.style._fill_visible()
        if sh.kind == CMD_RECT or sh.kind == CMD_CIRCLE:
            self.kind = _SIL_RECT
            var hw = sh.geom[2] / 2.0
            var hh = sh.geom[3] / 2.0
            var r = rect_corner_radius(
                Float64(sh.style.corner_radius), sh.geom[2], sh.geom[3]
            )
            if sh.kind == CMD_CIRCLE:
                hw = sh.geom[2]
                hh = hw
                r = hw
            self.outer[0] = sh.geom[0]
            self.outer[1] = sh.geom[1]
            self.outer[2] = hw
            self.outer[3] = hh
            self.outer[4] = r
            self.x0 = sh.geom[0] - hw
            self.x1 = sh.geom[0] + hw
            self.y0 = sh.geom[1] - hh
            self.y1 = sh.geom[1] + hh
            # Both outlines are inset rings.
            if ring and hw - thickness > 0.0 and hh - thickness > 0.0:
                self.has_inner = True
                self.inner[0] = sh.geom[0]
                self.inner[1] = sh.geom[1]
                self.inner[2] = hw - thickness
                self.inner[3] = hh - thickness
                self.inner[4] = max(r - thickness, 0.0)
        elif sh.kind == CMD_TRIANGLE:
            self.kind = _SIL_TRIANGLE
            var o = sh.copy()
            var i = sh.copy()
            if ring:
                # A centred band: half the stroke out, half in.
                _grow_triangle(o, thickness / 2.0)
                self.has_inner = _inradius(sh) > thickness / 2.0
                _grow_triangle(i, -thickness / 2.0)
            var xs = Array[Float64, 3](fill=0.0)
            var ys = Array[Float64, 3](fill=0.0)
            for k in range(3):
                xs[k] = o.geom[2 * k]
                ys[k] = o.geom[2 * k + 1]
            self.outer = _triangle_edges(xs, ys)
            self.x0 = min(xs[0], min(xs[1], xs[2]))
            self.x1 = max(xs[0], max(xs[1], xs[2]))
            self.y0 = min(ys[0], min(ys[1], ys[2]))
            self.y1 = max(ys[0], max(ys[1], ys[2]))
            if self.has_inner:
                for k in range(3):
                    xs[k] = i.geom[2 * k]
                    ys[k] = i.geom[2 * k + 1]
                self.inner = _triangle_edges(xs, ys)
        else:
            self.kind = _SIL_LINE
            var ax = sh.geom[0]
            var ay = sh.geom[1]
            var ex = sh.geom[2] - ax
            var ey = sh.geom[3] - ay
            var l = sqrt(ex * ex + ey * ey)
            var h = thickness / 2.0
            self.outer[0] = ax
            self.outer[1] = ay
            self.outer[2] = ex / l if l > 0.0 else 1.0
            self.outer[3] = ey / l if l > 0.0 else 0.0
            self.outer[4] = l
            self.outer[5] = h
            self.x0 = min(ax, sh.geom[2]) - h
            self.x1 = max(ax, sh.geom[2]) + h
            self.y0 = min(ay, sh.geom[3]) - h
            self.y1 = max(ay, sh.geom[3]) + h

    def reach(self) -> Float64:
        """How far past the silhouette, in local units, any coverage lands."""
        return BLUR_REACH / self.inv_sigma if self.inv_sigma > 0.0 else 0.0

    def _one(self, g: Array[Float64, 9], x: Float64, y: Float64) -> Float64:
        var k = self.inv_sigma
        if self.kind == _SIL_RECT:
            var dx = x - g[0]
            var dy = y - g[1]
            if g[4] <= 0.0:
                return box_coverage(
                    (g[2] + dx) * k,
                    (g[2] - dx) * k,
                    (g[3] + dy) * k,
                    (g[3] - dy) * k,
                )
            return rounded_rect_coverage(
                dx * k, dy * k, g[2] * k, g[3] * k, g[4] * k
            )
        if self.kind == _SIL_TRIANGLE:
            return edge_coverage(
                (g[0] * x + g[1] * y + g[2]) * k,
                (g[3] * x + g[4] * y + g[5]) * k,
                (g[6] * x + g[7] * y + g[8]) * k,
            )
        var dx = x - g[0]
        var dy = y - g[1]
        var along = dx * g[2] + dy * g[3]
        var across = dx * g[3] - dy * g[2]
        return box_coverage(
            along * k,
            (g[4] - along) * k,
            (g[5] + across) * k,
            (g[5] - across) * k,
        )

    def coverage(self, x: Float64, y: Float64) -> Float64:
        """The blurred silhouette's alpha, 0 to 1, at local `(x, y)`."""
        var c = self._one(self.outer, x, y)
        if self.has_inner and c > 0.0:
            c -= self._one(self.inner, x, y)
        return max(c, 0.0)


def _inradius(c: RenderCommand) -> Float64:
    """Twice the area over the perimeter: how far a triangle can shrink."""
    var ax = c.geom[0]
    var ay = c.geom[1]
    var bx = c.geom[2]
    var by = c.geom[3]
    var cx = c.geom[4]
    var cy = c.geom[5]
    var area2 = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
    var p = (
        sqrt((bx - ax) ** 2 + (by - ay) ** 2)
        + sqrt((cx - bx) ** 2 + (cy - by) ** 2)
        + sqrt((ax - cx) ** 2 + (ay - cy) ** 2)
    )
    return area2 / p if p > 0.0 else 0.0
