"""One shape kind at a time, rendered on both backends, compared structurally.

The CPU replay is the reference implementation — every geometry decision the
GL path makes exists to agree with it — and `tests/render/test_tessellate.mojo`
only checks the arithmetic that leads up to a triangle. This is the other
half: that the triangle, once rasterised by a driver, lands where the CPU put
it.

**Why the comparison is structural, not pixel-exact.** Two rasterisers cannot
agree on exact pixels and neither is wrong for it: coverage is integer
arithmetic in `_raster.blend` and float arithmetic in the fragment shader, an
edge that falls between two pixel centres is claimed by the CPU's fill rule
or the GPU's and the two rules are not the same rule, and a glyph's coverage
multiplies the fill alpha on both sides but in a different order and
precision. A prior version of this test asserted a one-pixel dilation of each
backend's ink mask, which worked but pinned both rasterisers to *hard* edges
forever — an antialiased GPU edge is not a one-pixel dilation of a hard one,
so that tolerance would have had to widen until it caught nothing.

So this test asserts what a real divergence breaks and a fill-rule
disagreement — or, in the future, antialiasing — cannot: each shape's
bounding box, centroid and pixel coverage, each within a tolerance sized for
rasteriser disagreement, plus the interior colour away from every edge. One
frame per shape kind, rather than everything at once, because a failure then
names the shape instead of a pixel count.

Both directions were verified by breaking an emitter on purpose before this
was committed: shifting `_mapped_quad` down two pixels on the rect case fails
the bounding-box assertion, and changing the tessellator's fill colour fails
the interior colour assertion.

MSAA is deliberately off: the CPU path antialiases nothing, so multisampling
would compare a smooth edge against a hard one and prove nothing about
geometry. Turning it on is a separate change, one this rewrite exists to
unblock rather than to make.

**It skips with no GL context at all.** SDL3's offscreen video driver gives a
working GL 3.3 context with no display, so `pixi run test` falls back to it
when `DISPLAY`, `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` are all unset — this
test only skips if `GLWindow` construction itself raises.
"""

from std.math import abs, max, min, tau
from std.testing import TestSuite, assert_true

from create import *
from create.core._step import step
from create.render.render_backend import RenderBackend
from create.render._gl import GL
from create.render._gl_target import _GLTarget
from create.render.canvas import PersistentCanvasState
from create._window import GLWindow
from create.math.matrix import rotate

comptime _DESIGN_W = 200
comptime _DESIGN_H = 150
comptime _PIXEL_W = 240
"""Wider than the design, so `FIT` leaves a letterbox bar on each side while
the scale factor stays exactly 1 — a resampled image would be comparing two
interpolation rules rather than two backends."""
comptime _PIXEL_H = 150

comptime _CONTENT_X0 = (_PIXEL_W - _DESIGN_W) // 2
comptime _CONTENT_X1 = _CONTENT_X0 + _DESIGN_W
comptime _CONTENT_Y0 = (_PIXEL_H - _DESIGN_H) // 2
comptime _CONTENT_Y1 = _CONTENT_Y0 + _DESIGN_H
"""The FIT-mapped content rect, at the scale-1 mapping documented on
`_PIXEL_W`. Masking outside it excludes the letterbox bars, which are a
constant black rather than `_BACKGROUND` and would otherwise swamp every
shape's bounding box and centroid with two fixed strips neither backend
moves."""

comptime _BACKGROUND = Color(0x20, 0x30, 0x40)
comptime _INK_THRESHOLD = 8
"""How far from the background a pixel has to be to count as rendered on."""

comptime _BBOX_TOLERANCE = 2
"""Pixels either edge of a shape's bounding box may differ by. Sized for the
fill-rule disagreement documented above, same as the old dilation radius."""
comptime _CENTROID_TOLERANCE = 1.5
"""How far a shape's ink centroid may differ, in pixels."""
comptime _COVERAGE_TOLERANCE = 0.10
"""Relative difference the two backends' ink pixel counts may differ by."""
comptime _INTERIOR_ERROR_LIMIT = 2.0
"""Mean absolute channel error, out of 255, at pixels at least one pixel
inside both backends' ink — i.e. nowhere near an edge disagreement."""
comptime _INTERIOR_MARGIN = 3
"""Pixels a candidate must stay clear of any ink/background disagreement.
1 was enough while every shape's edges were straight, but a rounded
corner's fill/outline boundary is itself a curve, and the GPU tessellator
renders it as a fan of straight segments rather than the CPU rasteriser's
exact circle test — the same kind of disagreement the outer edge is
already allowed, just one pixel wider where two colours meet on an arc."""

comptime _SHAPE_RECT = 0
comptime _SHAPE_STROKED_RECT = 1
comptime _SHAPE_CIRCLE = 2
comptime _SHAPE_LINE = 3
comptime _SHAPE_TRIANGLE = 4
comptime _SHAPE_IMAGE = 5
comptime _SHAPE_TEXT = 6
comptime _SHAPE_ROTATED_RECT = 7
comptime _SHAPE_ROUNDED_RECT = 8
comptime _SHAPE_ROUNDED_TRIANGLE = 9
comptime _SHAPE_SHADOWED_RECT = 10
comptime _SHAPE_SHADOWED_CIRCLE = 11
comptime _SHAPE_SHADOWED_TRIANGLE = 12
comptime _SHAPE_SHADOWED_LINE = 13
comptime _SHAPE_SHADOWED_TEXT = 14
comptime _SHAPE_SHADOWED_IMAGE = 15
comptime _SHAPE_BLURRED_RECT = 16
comptime _SHAPE_BLURRED_RING = 17
comptime _SHAPE_BLURRED_CIRCLE = 18
comptime _SHAPE_BLURRED_TRIANGLE = 19
comptime _SHAPE_BLURRED_TRIANGLE_RING = 20
comptime _SHAPE_BLURRED_LINE = 21
comptime _SHAPE_BLURRED_TEXT = 22
comptime _SHAPE_BLURRED_IMAGE = 23
comptime _SHAPE_INSET_RECT = 24
comptime _SHAPE_BLURRED_INSET_RECT = 25
comptime _SHAPE_INSET_ROUNDED_RECT = 26
comptime _SHAPE_BLURRED_INSET_ROUNDED_RECT = 27
comptime _SHAPE_INSET_CIRCLE = 28
comptime _SHAPE_BLURRED_INSET_CIRCLE = 29
comptime _SHAPE_INSET_TRIANGLE = 30
comptime _SHAPE_BLURRED_INSET_TRIANGLE = 31
comptime _SHAPE_BEZIER = 32
comptime _SHAPE_TRANSLUCENT_BEZIER = 33
comptime _SHAPE_SHADOWED_BEZIER = 34
comptime _SHAPE_BLURRED_BEZIER = 35
comptime _SHAPE_SPLINE = 36
comptime _SHAPE_TRANSLUCENT_CLOSED_SPLINE = 37
comptime _SHAPE_SHADOWED_CLOSED_SPLINE = 38
comptime _SHAPE_BLURRED_CLOSED_SPLINE = 39
comptime _SHAPE_TRANSLUCENT_ARC = 40
comptime _SHAPE_SECTOR = 41
comptime _SHAPE_TRANSLUCENT_PAC_MAN = 42
comptime _SHAPE_OUTLINED_DISC_SECTOR = 43
comptime _SHAPE_SHADOWED_SECTOR = 44
comptime _SHAPE_BLURRED_SECTOR_RING = 45
comptime _SHAPE_POLYGON = 46
comptime _SHAPE_CONCAVE_POLYGON = 47
comptime _SHAPE_TRANSLUCENT_STAR = 48
comptime _SHAPE_PENTAGRAM = 49
comptime _SHAPE_SHADOWED_STAR = 50
comptime _SHAPE_BLURRED_POLYGON_RING = 51
comptime _SHAPE_GRADIENT_RECT = 52
comptime _SHAPE_GRADIENT_ROUNDED_RECT = 53
comptime _SHAPE_RADIAL_CIRCLE = 54
comptime _SHAPE_RADIAL_ELLIPSE = 55
comptime _SHAPE_ROTATED_GRADIENT_RECT = 56
comptime _SHAPE_TRANSLUCENT_GRADIENT_RECT = 57
comptime _SHAPE_GRADIENT_TRIANGLE = 58
comptime _SHAPE_GRADIENT_ROUNDED_TRIANGLE = 59
comptime _SHAPE_GRADIENT_SECTOR = 60
comptime _SHAPE_GRADIENT_STAR = 61
comptime _SHAPE_ITALIC_TEXT = 62
comptime _SHAPE_COUNT = 63

comptime _SHADOW_INK = Color(0x10, 0x10, 0x10)
"""Opaque and far from `_BACKGROUND`, so a shadow counts as ink and its
colour is compared like any fill's."""


def _shadowed(var s: Style) -> Style:
    """`s` casting a hard, opaque shadow down-right."""
    s.shadow_enabled = True
    s.shadow_color = _SHADOW_INK
    s.shadow_offset = Vector2D(8, -8)
    s.shadow_blur = 0.0
    return s^


def _blurred(var s: Style) -> Style:
    """`s` casting a soft shadow: sigma 4, so it fades out 16 pixels past
    the silhouette. Both backends evaluate the same coverage functions at
    pixel centres, so the soft band compares like any interior colour."""
    s = _shadowed(s^)
    s.shadow_blur = 8.0
    return s^


def _inset(var s: Style, blur: Float64 = 0.0) -> Style:
    """`s` with an opaque inset shadow, its band along the top-left inner
    edges. Over a light fill the band is compared like any interior colour;
    over no fill it is the only ink inside the outline."""
    s = _shadowed(s^)
    s.shadow_inset = True
    s.shadow_blur = blur
    return s^


def _shape_name(shape: Int) -> String:
    if shape == _SHAPE_RECT:
        return "rect"
    elif shape == _SHAPE_STROKED_RECT:
        return "outlined rect"
    elif shape == _SHAPE_CIRCLE:
        return "circle"
    elif shape == _SHAPE_LINE:
        return "line"
    elif shape == _SHAPE_TRIANGLE:
        return "triangle"
    elif shape == _SHAPE_IMAGE:
        return "image"
    elif shape == _SHAPE_TEXT:
        return "text"
    elif shape == _SHAPE_ITALIC_TEXT:
        return "italic text"
    elif shape == _SHAPE_ROTATED_RECT:
        return "rotated rect"
    elif shape == _SHAPE_ROUNDED_RECT:
        return "rounded rect"
    elif shape == _SHAPE_ROUNDED_TRIANGLE:
        return "rounded triangle"
    elif shape == _SHAPE_SHADOWED_RECT:
        return "shadowed rect"
    elif shape == _SHAPE_SHADOWED_CIRCLE:
        return "shadowed circle"
    elif shape == _SHAPE_SHADOWED_TRIANGLE:
        return "shadowed triangle"
    elif shape == _SHAPE_SHADOWED_LINE:
        return "shadowed line"
    elif shape == _SHAPE_SHADOWED_TEXT:
        return "shadowed text"
    elif shape == _SHAPE_SHADOWED_IMAGE:
        return "shadowed image"
    elif shape == _SHAPE_BLURRED_RECT:
        return "blurred rect"
    elif shape == _SHAPE_BLURRED_RING:
        return "blurred rounded ring"
    elif shape == _SHAPE_BLURRED_CIRCLE:
        return "blurred circle"
    elif shape == _SHAPE_BLURRED_TRIANGLE:
        return "blurred triangle"
    elif shape == _SHAPE_BLURRED_TRIANGLE_RING:
        return "blurred triangle ring"
    elif shape == _SHAPE_BLURRED_TEXT:
        return "blurred text"
    elif shape == _SHAPE_BLURRED_IMAGE:
        return "blurred image"
    elif shape == _SHAPE_INSET_RECT:
        return "inset rect"
    elif shape == _SHAPE_BLURRED_INSET_RECT:
        return "blurred inset rect"
    elif shape == _SHAPE_INSET_ROUNDED_RECT:
        return "inset rounded rect"
    elif shape == _SHAPE_BLURRED_INSET_ROUNDED_RECT:
        return "blurred inset rounded rect"
    elif shape == _SHAPE_INSET_CIRCLE:
        return "inset circle"
    elif shape == _SHAPE_BLURRED_INSET_CIRCLE:
        return "blurred inset circle"
    elif shape == _SHAPE_INSET_TRIANGLE:
        return "inset triangle"
    elif shape == _SHAPE_BLURRED_INSET_TRIANGLE:
        return "blurred inset rounded triangle"
    elif shape == _SHAPE_BEZIER:
        return "bezier"
    elif shape == _SHAPE_TRANSLUCENT_BEZIER:
        return "translucent bezier"
    elif shape == _SHAPE_SHADOWED_BEZIER:
        return "shadowed bezier"
    elif shape == _SHAPE_BLURRED_BEZIER:
        return "blurred bezier"
    elif shape == _SHAPE_SPLINE:
        return "spline"
    elif shape == _SHAPE_TRANSLUCENT_CLOSED_SPLINE:
        return "translucent closed spline"
    elif shape == _SHAPE_SHADOWED_CLOSED_SPLINE:
        return "shadowed closed spline"
    elif shape == _SHAPE_BLURRED_CLOSED_SPLINE:
        return "blurred closed spline"
    elif shape == _SHAPE_TRANSLUCENT_ARC:
        return "translucent arc"
    elif shape == _SHAPE_SECTOR:
        return "sector"
    elif shape == _SHAPE_TRANSLUCENT_PAC_MAN:
        return "translucent pac-man sector"
    elif shape == _SHAPE_OUTLINED_DISC_SECTOR:
        return "outlined whole-turn sector"
    elif shape == _SHAPE_SHADOWED_SECTOR:
        return "shadowed sector"
    elif shape == _SHAPE_BLURRED_SECTOR_RING:
        return "blurred sector ring"
    elif shape == _SHAPE_POLYGON:
        return "polygon"
    elif shape == _SHAPE_CONCAVE_POLYGON:
        return "concave polygon"
    elif shape == _SHAPE_TRANSLUCENT_STAR:
        return "translucent star"
    elif shape == _SHAPE_PENTAGRAM:
        return "pentagram"
    elif shape == _SHAPE_SHADOWED_STAR:
        return "shadowed star"
    elif shape == _SHAPE_BLURRED_POLYGON_RING:
        return "blurred polygon ring"
    elif shape == _SHAPE_GRADIENT_RECT:
        return "gradient rect"
    elif shape == _SHAPE_GRADIENT_ROUNDED_RECT:
        return "outlined rounded gradient rect"
    elif shape == _SHAPE_RADIAL_CIRCLE:
        return "radial circle"
    elif shape == _SHAPE_RADIAL_ELLIPSE:
        return "off-centre radial ellipse"
    elif shape == _SHAPE_ROTATED_GRADIENT_RECT:
        return "rotated gradient rect"
    elif shape == _SHAPE_TRANSLUCENT_GRADIENT_RECT:
        return "translucent gradient rect"
    elif shape == _SHAPE_GRADIENT_TRIANGLE:
        return "gradient triangle"
    elif shape == _SHAPE_GRADIENT_ROUNDED_TRIANGLE:
        return "rounded gradient triangle"
    elif shape == _SHAPE_GRADIENT_SECTOR:
        return "gradient sector"
    elif shape == _SHAPE_GRADIENT_STAR:
        return "gradient star"
    else:
        return "blurred line"


def _bezier(mut canvas: Canvas):
    """An S-curve with a sharp bend."""
    canvas.bezier(Bezier((-90, -50), (-60, 90), (60, -90), (90, 50)))


def _spline(mut canvas: Canvas, closed: Bool):
    """A wave through five unevenly spaced points; closed, a lopsided loop
    that turns sharply where it closes."""
    canvas.spline(
        [(-90, -40), (-50, 50), (0, -20), (20, 30), (80, 40)], closed=closed
    )


@fieldwise_init
struct _Parity(Program):
    """One command kind the GL backend implements, picked by `shape`."""

    var image: Image
    var block: Image
    """Opaque and large enough that its blurred shadow clears the ink
    threshold; drawn at native size, like `image`, so neither backend
    resamples the image itself."""
    var shape: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> _Parity:
        return _Parity.create(context, _SHAPE_RECT)

    @staticmethod
    def create(mut context: Context, shape: Int) raises -> _Parity:
        context.design_size(_DESIGN_W, _DESIGN_H)
        return _Parity(
            Image.load("tests/fixtures/test_2x2.png"),
            Image.solid(30, 30, 0xE0, 0x90, 0x40),
            shape,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(_BACKGROUND)

        if self.shape == _SHAPE_RECT:
            with canvas.style():
                canvas.outline_enabled(False)
                canvas.fill(Color(0xE0, 0x40, 0x40))
                canvas.rectangle((-20, 20), 50, 30)
        elif self.shape == _SHAPE_STROKED_RECT:
            with canvas.style():
                canvas.fill(Color(0x40, 0xC0, 0xE0))
                canvas.outline(Color.BLACK, thickness=4)
                canvas.rectangle((10, 40), 50, 30)
        elif self.shape == _SHAPE_CIRCLE:
            with canvas.style():
                canvas.outline_enabled(False)
                canvas.fill(Color(0xF0, 0xC0, 0x30))
                canvas.circle((-60, -20), 24)
        elif self.shape == _SHAPE_LINE:
            with canvas.style():
                canvas.outline(Color(0x80, 0xFF, 0x80), thickness=3)
                canvas.line((-90, -60), (90, -60))
        elif self.shape == _SHAPE_TRIANGLE:
            with canvas.style():
                canvas.outline_enabled(False)
                canvas.fill(Color(0xA0, 0x60, 0xF0))
                canvas.triangle((20, -50), (70, -50), (45, -5))
        elif self.shape == _SHAPE_IMAGE:
            # Native size: at a scale of 1 neither backend resamples, so this
            # is testing the blit, not the filter.
            canvas.image(self.image, (70, 50), 2, 2)
        elif self.shape == _SHAPE_TEXT:
            with canvas.style():
                canvas.outline_enabled(False)
                canvas.text_color(Color.WHITE)
                canvas.font_size(16)
                canvas.text_align(Align.CENTER)
                canvas.text("parity", (0, 0))
        elif self.shape == _SHAPE_ITALIC_TEXT:
            with canvas.style(
                outline_enabled=False,
                text_color=Color.WHITE,
                font_size=16,
                font_italic=True,
            ):
                canvas.text("parity", (0, 0))
        elif self.shape == _SHAPE_ROTATED_RECT:
            # Rotation defeats the axis-aligned fast path on both backends,
            # so this exercises the CPU's non-uniform inverse-mapping branch
            # against the GL tessellator's per-vertex transform — the one
            # shape kind the parity set otherwise never touches.
            with canvas.style():
                canvas.outline_enabled(False)
                canvas.fill(Color(0x60, 0xE0, 0x90))
                with canvas.transform(rotate(0.5)):
                    canvas.rectangle((30, -70), 40, 20)
        elif self.shape == _SHAPE_ROUNDED_RECT:
            # Filled and outlined, so both the fill's cross decomposition and
            # the outline's inset ring get exercised on both backends.
            with canvas.style():
                canvas.fill(Color(0xE0, 0x90, 0x40))
                canvas.outline(Color.BLACK, thickness=4)
                canvas.corner_radius(10)
                canvas.rectangle((-70, 40), 44, 30)
        elif self.shape == _SHAPE_SHADOWED_RECT:
            # Outlined, so the silhouette has to cover the ring as one layer.
            with canvas.style(
                _shadowed(
                    Style(
                        fill=Color(0x40, 0xC0, 0xE0),
                        outline=Color.BLACK,
                        outline_thickness=4,
                        corner_radius=6,
                    )
                )
            ):
                canvas.rectangle((10, 20), 50, 30)
        elif self.shape == _SHAPE_SHADOWED_CIRCLE:
            with canvas.style(
                _shadowed(
                    Style(fill=Color(0xF0, 0xC0, 0x30), outline_enabled=False)
                )
            ):
                canvas.circle((-60, -20), 24)
        elif self.shape == _SHAPE_SHADOWED_TRIANGLE:
            # Outlined: the silhouette grows by half the centred band.
            with canvas.style(
                _shadowed(
                    Style(
                        fill=Color(0xA0, 0x60, 0xF0),
                        outline=Color.BLACK,
                        outline_thickness=4,
                    )
                )
            ):
                canvas.triangle((20, -50), (70, -50), (45, -5))
        elif self.shape == _SHAPE_SHADOWED_LINE:
            with canvas.style(
                _shadowed(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=3)
                )
            ):
                canvas.line((-90, -40), (90, -40))
        elif self.shape == _SHAPE_SHADOWED_TEXT:
            with canvas.style(
                _shadowed(
                    Style(
                        outline_enabled=False,
                        text_color=Color.WHITE,
                        font_size=16,
                    )
                )
            ):
                canvas.text("parity", (0, 0))
        elif self.shape == _SHAPE_SHADOWED_IMAGE:
            # Native size, like the plain image: the silhouette is the same
            # blit through the image's alpha.
            with canvas.style(_shadowed(Style())):
                canvas.image(self.image, (70, 50), 2, 2)
        elif self.shape == _SHAPE_BLURRED_RECT:
            # Sharp corners: the exact separable form.
            with canvas.style(
                _blurred(
                    Style(fill=Color(0x40, 0xC0, 0xE0), outline_enabled=False)
                )
            ):
                canvas.rectangle((-20, 10), 60, 40)
        elif self.shape == _SHAPE_BLURRED_RING:
            # Outline only, and thicker than sigma, so the hole shows.
            with canvas.style(
                _blurred(
                    Style(
                        outline=Color(0xE0, 0x90, 0x40),
                        outline_thickness=12,
                        corner_radius=14,
                    )
                )
            ):
                canvas.rectangle((-10, 10), 90, 70)
        elif self.shape == _SHAPE_BLURRED_CIRCLE:
            with canvas.style(
                _blurred(
                    Style(fill=Color(0xF0, 0xC0, 0x30), outline_enabled=False)
                )
            ):
                canvas.circle((-40, 0), 28)
        elif self.shape == _SHAPE_BLURRED_TRIANGLE:
            with canvas.style(
                _blurred(
                    Style(
                        fill=Color(0xA0, 0x60, 0xF0),
                        outline=Color.BLACK,
                        outline_thickness=4,
                    )
                )
            ):
                canvas.triangle((-50, -40), (40, -40), (0, 45))
        elif self.shape == _SHAPE_BLURRED_TRIANGLE_RING:
            with canvas.style(
                _blurred(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=12)
                )
            ):
                canvas.triangle((-60, -45), (50, -45), (-5, 50))
        elif self.shape == _SHAPE_BLURRED_LINE:
            # Diagonal, so the quad follows the stroke's own frame.
            with canvas.style(
                _blurred(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=6)
                )
            ):
                canvas.line((-70, -40), (50, 40))
        elif self.shape == _SHAPE_BLURRED_TEXT:
            # Large, so the blurred stems stay above the ink threshold.
            with canvas.style(
                _blurred(
                    Style(
                        outline_enabled=False,
                        text_color=Color.WHITE,
                        font_size=40,
                    )
                )
            ):
                canvas.text("Il", (0, 0))
        elif self.shape == _SHAPE_BLURRED_IMAGE:
            # Both backends blit the same cached mask one-to-one.
            with canvas.style(_blurred(Style())):
                canvas.image(self.block, (-20, 10), 30, 30)
        elif self.shape == _SHAPE_INSET_RECT:
            with canvas.style(
                _inset(
                    Style(
                        fill=Color(0xF0, 0xE0, 0xC0),
                        outline=Color(0x30, 0x60, 0xC0),
                        outline_thickness=4,
                    )
                )
            ):
                canvas.rectangle((-10, 5), 100, 70)
        elif self.shape == _SHAPE_BLURRED_INSET_RECT:
            with canvas.style(
                _inset(
                    Style(fill=Color(0xF0, 0xE0, 0xC0), outline_enabled=False),
                    8.0,
                )
            ):
                canvas.rectangle((-10, 5), 100, 70)
        elif self.shape == _SHAPE_INSET_ROUNDED_RECT:
            # No fill: the band is the only ink inside the outline.
            var s = _inset(
                Style(
                    outline=Color(0x30, 0x60, 0xC0),
                    outline_thickness=4,
                    corner_radius=16,
                )
            )
            s.shadow_spread = 3.0
            with canvas.style(s):
                canvas.rectangle((-10, 5), 100, 70)
        elif self.shape == _SHAPE_BLURRED_INSET_ROUNDED_RECT:
            with canvas.style(
                _inset(
                    Style(
                        fill=Color(0xF0, 0xE0, 0xC0),
                        outline=Color(0x30, 0x60, 0xC0),
                        outline_thickness=4,
                        corner_radius=16,
                    ),
                    8.0,
                )
            ):
                canvas.rectangle((-10, 5), 100, 70)
        elif self.shape == _SHAPE_INSET_CIRCLE:
            with canvas.style(
                _inset(
                    Style(outline=Color(0x30, 0x60, 0xC0), outline_thickness=4)
                )
            ):
                canvas.circle((-20, 0), 40)
        elif self.shape == _SHAPE_BLURRED_INSET_CIRCLE:
            with canvas.style(
                _inset(
                    Style(fill=Color(0xF0, 0xE0, 0xC0), outline_enabled=False),
                    8.0,
                )
            ):
                canvas.circle((-20, 0), 40)
        elif self.shape == _SHAPE_INSET_TRIANGLE:
            with canvas.style(
                _inset(
                    Style(
                        fill=Color(0xF0, 0xE0, 0xC0),
                        outline=Color(0x30, 0x60, 0xC0),
                        outline_thickness=4,
                    )
                )
            ):
                canvas.triangle((-60, -45), (50, -45), (-5, 50))
        elif self.shape == _SHAPE_BLURRED_INSET_TRIANGLE:
            with canvas.style(
                _inset(
                    Style(
                        fill=Color(0xF0, 0xE0, 0xC0),
                        outline_enabled=False,
                        corner_radius=10,
                    ),
                    8.0,
                )
            ):
                canvas.triangle((-60, -45), (50, -45), (-5, 50))
        elif self.shape == _SHAPE_BEZIER:
            with canvas.style():
                canvas.outline(Color(0x80, 0xFF, 0x80), thickness=5)
                _bezier(canvas)
        elif self.shape == _SHAPE_TRANSLUCENT_BEZIER:
            # Translucent, so a joint painted twice would show as a darker
            # seam in the interior colour.
            with canvas.style():
                canvas.outline(Color(0x20, 0x40, 0xFF, 0x80), thickness=8)
                _bezier(canvas)
        elif self.shape == _SHAPE_SHADOWED_BEZIER:
            with canvas.style(
                _shadowed(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=5)
                )
            ):
                _bezier(canvas)
        elif self.shape == _SHAPE_BLURRED_BEZIER:
            with canvas.style(
                _blurred(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=5)
                )
            ):
                _bezier(canvas)
        elif self.shape == _SHAPE_SPLINE:
            with canvas.style():
                canvas.outline(Color(0x80, 0xFF, 0x80), thickness=5)
                _spline(canvas, closed=False)
        elif self.shape == _SHAPE_TRANSLUCENT_CLOSED_SPLINE:
            # Translucent, so a seam painted twice would show darker.
            with canvas.style():
                canvas.outline(Color(0x20, 0x40, 0xFF, 0x80), thickness=8)
                _spline(canvas, closed=True)
        elif self.shape == _SHAPE_SHADOWED_CLOSED_SPLINE:
            with canvas.style(
                _shadowed(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=5)
                )
            ):
                _spline(canvas, closed=True)
        elif self.shape == _SHAPE_BLURRED_CLOSED_SPLINE:
            with canvas.style(
                _blurred(
                    Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=5)
                )
            ):
                _spline(canvas, closed=True)
        elif self.shape == _SHAPE_TRANSLUCENT_ARC:
            # Clockwise past a turn, so it closes; translucent, so the
            # closing joint would show darker if painted twice.
            with canvas.style():
                canvas.outline(Color(0x20, 0x40, 0xFF, 0x80), thickness=8)
                canvas.arc((0, 0), 70, 0.5, -7.0)
        elif self.shape == _SHAPE_SECTOR:
            # Under a half turn, rotated, filled and outlined.
            with canvas.style():
                canvas.fill(Color(0x50, 0xA0, 0xD0))
                canvas.outline(Color.BLACK, thickness=6)
                with canvas.transform(rotate(0.4)):
                    canvas.sector((-40, -55), 110, 0.2, 1.1)
        elif self.shape == _SHAPE_TRANSLUCENT_PAC_MAN:
            # Past a half turn, clockwise, so the tip is round; translucent,
            # so a seam between fill and outline would show darker.
            with canvas.style():
                canvas.fill(Color(0xFF, 0xC0, 0x20, 0x80))
                canvas.outline(Color(0x20, 0x40, 0xFF, 0x80), thickness=10)
                canvas.sector((0, 0), 65, -0.6, -(tau - 1.2))
        elif self.shape == _SHAPE_OUTLINED_DISC_SECTOR:
            # A whole turn, outline only: a ring.
            with canvas.style():
                canvas.fill_enabled(False)
                canvas.outline(Color(0x80, 0xFF, 0x80), thickness=8)
                canvas.sector((0, 0), 60, 1.0, tau)
        elif self.shape == _SHAPE_SHADOWED_SECTOR:
            # Past a half turn and spread, so the shadow reaches round the
            # tip into the missing wedge.
            var s = _shadowed(
                Style(fill=Color(0xFF, 0xC0, 0x20), outline_thickness=4)
            )
            s.shadow_spread = 6.0
            with canvas.style(s):
                canvas.sector((-10, 10), 60, 0.6, tau - 1.2)
        elif self.shape == _SHAPE_BLURRED_SECTOR_RING:
            # Outline only, under a half turn: the blurred mask of a ring.
            var s = _blurred(
                Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=8)
            )
            s.shadow_spread = 3.0
            with canvas.style(s):
                canvas.sector((-50, -40), 110, 0.2, 1.2)
        elif self.shape == _SHAPE_POLYGON:
            # A hexagon under rotation and non-uniform scale, outlined.
            with canvas.style():
                canvas.fill(Color(0x50, 0xA0, 0xD0))
                canvas.outline(Color.BLACK, thickness=6)
                with canvas.transform(rotate(0.3) @ scale(1.3, 0.8)):
                    canvas.polygon(Polygon.regular((0, 0), 70, 6))
        elif self.shape == _SHAPE_CONCAVE_POLYGON:
            # An L: the outline rounds off round the reflex corner.
            with canvas.style():
                canvas.fill(Color(0xFF, 0xC0, 0x20))
                canvas.outline(Color.BLACK, thickness=8)
                canvas.polygon(
                    (-80, -70),
                    (80, -70),
                    (80, -10),
                    (-20, -10),
                    (-20, 70),
                    (-80, 70),
                )
        elif self.shape == _SHAPE_TRANSLUCENT_STAR:
            # Translucent, so a seam between quads would show darker.
            with canvas.style():
                canvas.fill(Color(0xFF, 0xC0, 0x20, 0x80))
                canvas.outline(Color(0x20, 0x40, 0xFF, 0x80), thickness=8)
                canvas.polygon(Polygon.star((0, 0), 80, 35, 5))
        elif self.shape == _SHAPE_PENTAGRAM:
            # Five self-crossing edges: the centre is wound twice.
            var tips = Polygon.regular((0, 0), 80, 5).vertices.copy()
            with canvas.style():
                canvas.fill(Color(0x80, 0xFF, 0x80))
                canvas.outline(Color.BLACK, thickness=3)
                canvas.polygon(tips[0], tips[2], tips[4], tips[1], tips[3])
        elif self.shape == _SHAPE_SHADOWED_STAR:
            # Spread, so the shadow rounds off every tip and fills the
            # notches between them.
            var s = _shadowed(
                Style(fill=Color(0xFF, 0xC0, 0x20), outline_thickness=4)
            )
            s.shadow_spread = 6.0
            with canvas.style(s):
                canvas.polygon(Polygon.star((-10, 10), 70, 30, 5))
        elif self.shape == _SHAPE_BLURRED_POLYGON_RING:
            # Outline only, concave: the blurred mask of a ring.
            var s = _blurred(
                Style(outline=Color(0x80, 0xFF, 0x80), outline_thickness=8)
            )
            s.shadow_spread = 3.0
            with canvas.style(s):
                canvas.polygon(
                    (-80, -70),
                    (60, -70),
                    (60, -10),
                    (-20, -10),
                    (-20, 50),
                    (-80, 50),
                )
        elif self.shape == _SHAPE_GRADIENT_RECT:
            # Three stops, one off-centre, so the ramp has a bend in it.
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.linear(
                        [
                            (0.0, Color(0xFF, 0x40, 0x20)),
                            (0.3, Color(0x20, 0xFF, 0x80)),
                            (1.0, Color(0x40, 0x20, 0xFF)),
                        ]
                    )
                )
                canvas.rectangle((0, 0), 160, 110)
        elif self.shape == _SHAPE_GRADIENT_ROUNDED_RECT:
            with canvas.style():
                canvas.outline(Color.BLACK, thickness=5)
                canvas.corner_radius(18)
                canvas.fill(
                    Gradient.linear(
                        Color(0xFF, 0xE0, 0x40),
                        Color(0xC0, 0x20, 0x80),
                        direction=Vector2D(1, 1),
                    )
                )
                canvas.rectangle((0, 0), 150, 100)
        elif self.shape == _SHAPE_RADIAL_CIRCLE:
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.radial(Color.WHITE, Color(0x20, 0x60, 0xFF))
                )
                canvas.circle((0, 0), 60)
        elif self.shape == _SHAPE_RADIAL_ELLIPSE:
            # A long box, so the radial is an ellipse, centred off its middle.
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.radial(
                        Color(0xFF, 0xFF, 0xA0),
                        Color(0x80, 0x20, 0x20),
                        center=(-0.4, 0.3),
                    )
                )
                canvas.rectangle((0, 0), 170, 90)
        elif self.shape == _SHAPE_ROTATED_GRADIENT_RECT:
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.linear(
                        Color(0xFF, 0x80, 0x20), Color(0x20, 0x80, 0xFF)
                    )
                )
                with canvas.transform(rotate(0.6)):
                    canvas.rectangle((0, 0), 120, 70)
        elif self.shape == _SHAPE_TRANSLUCENT_GRADIENT_RECT:
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.linear(
                        Color(0xFF, 0x40, 0x40, 0xF0),
                        Color(0xFF, 0x40, 0x40, 0x30),
                        direction=Vector2D.RIGHT,
                    )
                )
                canvas.rectangle((0, 0), 160, 100)
        elif self.shape == _SHAPE_GRADIENT_TRIANGLE:
            with canvas.style():
                canvas.outline(Color.BLACK, thickness=3)
                canvas.fill(
                    Gradient.linear(
                        Color(0xFF, 0xD0, 0x20), Color(0xD0, 0x20, 0x20)
                    )
                )
                canvas.triangle((-80, -60), (80, -50), (10, 65))
        elif self.shape == _SHAPE_GRADIENT_ROUNDED_TRIANGLE:
            with canvas.style(outline_enabled=False):
                canvas.corner_radius(12)
                canvas.fill(
                    Gradient.radial(
                        Color(0xA0, 0xFF, 0xA0), Color(0x20, 0x60, 0x20)
                    )
                )
                canvas.triangle((-80, -60), (80, -50), (10, 65))
        elif self.shape == _SHAPE_GRADIENT_SECTOR:
            with canvas.style():
                canvas.outline(Color.BLACK, thickness=3)
                canvas.fill(
                    Gradient.linear(
                        Color(0x40, 0xFF, 0x40),
                        Color(0x20, 0x20, 0xC0),
                        direction=Vector2D.RIGHT,
                    )
                )
                canvas.sector((0, 0), 65.0, 0.4, 4.8)
        elif self.shape == _SHAPE_GRADIENT_STAR:
            with canvas.style(outline_enabled=False):
                canvas.fill(
                    Gradient.linear(
                        Color(0xFF, 0xA0, 0x40), Color(0xFF, 0x60, 0xC0)
                    )
                )
                canvas.polygon(Polygon.star((0, 0), 70, 30, 5))
        else:
            # Scalene (one acute, one obtuse vertex) and outlined, so both
            # the per-vertex `pi - theta` span math and the centred-outline
            # convention are exercised against the CPU's.
            with canvas.style():
                canvas.fill(Color(0x50, 0xA0, 0xD0))
                canvas.outline(Color.BLACK, thickness=4)
                canvas.corner_radius(9)
                canvas.triangle((40, 5), (95, 15), (65, 70))


def _mask(pixels: List[UInt8]) -> List[Bool]:
    """Which pixels are not the background, restricted to the content rect.

    Outside it is the letterbox, painted the same fixed colour by both
    backends regardless of what `_Parity` renders — never ink, so a shape can
    never be found out there.
    """
    var m = List[Bool](length=_PIXEL_W * _PIXEL_H, fill=False)
    for y in range(_CONTENT_Y0, _CONTENT_Y1):
        for x in range(_CONTENT_X0, _CONTENT_X1):
            var i = y * _PIXEL_W + x
            var dr = Int(pixels[i * 4]) - Int(_BACKGROUND.r)
            var dg = Int(pixels[i * 4 + 1]) - Int(_BACKGROUND.g)
            var db = Int(pixels[i * 4 + 2]) - Int(_BACKGROUND.b)
            m[i] = max(max(abs(dr), abs(dg)), abs(db)) > _INK_THRESHOLD
    return m^


def _mask_stats(
    mask: List[Bool],
) -> Tuple[Int, Int, Int, Int, Float64, Float64, Int]:
    """Bounding box `(x0, y0, x1, y1)`, centroid `(cx, cy)`, and ink count, in
    one pass. Bbox is `(-1, -1, -1, -1)` and centroid `(0, 0)` when empty.
    """
    var x0 = _PIXEL_W
    var y0 = _PIXEL_H
    var x1 = -1
    var y1 = -1
    var sx = 0
    var sy = 0
    var count = 0
    for y in range(_PIXEL_H):
        for x in range(_PIXEL_W):
            if mask[y * _PIXEL_W + x]:
                x0 = min(x0, x)
                y0 = min(y0, y)
                x1 = max(x1, x)
                y1 = max(y1, y)
                sx += x
                sy += y
                count += 1
    if count == 0:
        return (-1, -1, -1, -1, 0.0, 0.0, 0)
    return (
        x0,
        y0,
        x1,
        y1,
        Float64(sx) / Float64(count),
        Float64(sy) / Float64(count),
        count,
    )


def _assert_structural_match(
    shape_name: String, cpu_mask: List[Bool], gpu_mask: List[Bool]
) raises:
    var cx0: Int
    var cy0: Int
    var cx1: Int
    var cy1: Int
    var ccx: Float64
    var ccy: Float64
    var ccount: Int
    cx0, cy0, cx1, cy1, ccx, ccy, ccount = _mask_stats(cpu_mask)
    var gx0: Int
    var gy0: Int
    var gx1: Int
    var gy1: Int
    var gcx: Float64
    var gcy: Float64
    var gcount: Int
    gx0, gy0, gx1, gy1, gcx, gcy, gcount = _mask_stats(gpu_mask)

    assert_true(ccount > 0, shape_name + ": the CPU backend drew nothing")
    assert_true(gcount > 0, shape_name + ": the GPU backend drew nothing")

    assert_true(
        abs(cx0 - gx0) <= _BBOX_TOLERANCE,
        shape_name
        + ": bbox left edge, cpu="
        + String(cx0)
        + " gpu="
        + String(gx0),
    )
    assert_true(
        abs(cy0 - gy0) <= _BBOX_TOLERANCE,
        shape_name
        + ": bbox top edge, cpu="
        + String(cy0)
        + " gpu="
        + String(gy0),
    )
    assert_true(
        abs(cx1 - gx1) <= _BBOX_TOLERANCE,
        shape_name
        + ": bbox right edge, cpu="
        + String(cx1)
        + " gpu="
        + String(gx1),
    )
    assert_true(
        abs(cy1 - gy1) <= _BBOX_TOLERANCE,
        shape_name
        + ": bbox bottom edge, cpu="
        + String(cy1)
        + " gpu="
        + String(gy1),
    )

    assert_true(
        abs(ccx - gcx) <= _CENTROID_TOLERANCE,
        shape_name + ": centroid x, cpu=" + String(ccx) + " gpu=" + String(gcx),
    )
    assert_true(
        abs(ccy - gcy) <= _CENTROID_TOLERANCE,
        shape_name + ": centroid y, cpu=" + String(ccy) + " gpu=" + String(gcy),
    )

    var rel = abs(Float64(ccount - gcount)) / Float64(max(ccount, gcount))
    assert_true(
        rel <= _COVERAGE_TOLERANCE,
        shape_name
        + ": coverage, cpu="
        + String(ccount)
        + " gpu="
        + String(gcount)
        + " ("
        + String(rel * 100.0)
        + "% off)",
    )


def _assert_interior_colour_matches(
    shape_name: String,
    cpu: List[UInt8],
    gpu: List[UInt8],
    cpu_mask: List[Bool],
    gpu_mask: List[Bool],
) raises:
    """Compares channels only at pixels that are ink in both masks and whose
    full `_INTERIOR_MARGIN`-radius neighbourhood is too — i.e. nowhere near
    an edge, where the two fill rules (or, later, antialiasing) are entitled
    to disagree.
    """
    var total = 0
    var count = 0
    for y in range(_INTERIOR_MARGIN, _PIXEL_H - _INTERIOR_MARGIN):
        for x in range(_INTERIOR_MARGIN, _PIXEL_W - _INTERIOR_MARGIN):
            var i = y * _PIXEL_W + x
            if not (cpu_mask[i] and gpu_mask[i]):
                continue
            var interior = True
            for dy in range(-_INTERIOR_MARGIN, _INTERIOR_MARGIN + 1):
                for dx in range(-_INTERIOR_MARGIN, _INTERIOR_MARGIN + 1):
                    var j = (y + dy) * _PIXEL_W + (x + dx)
                    if not (cpu_mask[j] and gpu_mask[j]):
                        interior = False
            if not interior:
                continue
            for ch in range(3):
                var a = Int(cpu[i * 4 + ch])
                var b = Int(gpu[i * 4 + ch])
                total += a - b if a > b else b - a
            count += 1
    if count == 0:
        # Thin shapes (the line, the image at this size) may have no pixel
        # fully surrounded by ink in both masks — nothing to check.
        return
    var mean = Float64(total) / Float64(count * 3)
    assert_true(
        mean < _INTERIOR_ERROR_LIMIT,
        shape_name
        + ": interior colour mean error "
        + String(mean)
        + " exceeds the tolerance",
    )


def _create(
    mut context: Context, mut state: PersistentCanvasState, shape: Int
) raises -> _Parity:
    """`_Parity.create` with the extra `shape` argument, then the mapping.

    Hand-rolled rather than the trait's own `create` because this one needs
    `shape` to pick which command it records. The viewport is derived after
    it returns, exactly as the loops do it — `create` is where the design
    size is pinned.
    """
    var program = _Parity.create(context, shape)
    context._set_viewport(state, _PIXEL_W, _PIXEL_H)
    return program^


def _cpu_frame(shape: Int) raises -> MemorySurface:
    """One shape's frame through the CPU backend, onto an owned buffer.

    Not `run_headless`: that drives `Program.create`'s trait method, and `_Parity` needs the extra `shape` argument to pick
    which command it records this frame. Otherwise identical to it.
    """
    var mem = MemorySurface(_PIXEL_W, _PIXEL_H)
    var state = PersistentCanvasState()
    var context = Context()
    var program = _create(context, state, shape)
    context.time._start(0)
    context.time._tick(16)
    state = step(program, context, state^)
    state.backend.present(mem.surface(), state.view.scale)
    return mem^


def _gpu_frame(mut win: GLWindow, shape: Int) raises -> List[UInt8]:
    """One shape's frame through the GL backend, into an offscreen RGBA
    target.

    A framebuffer object rather than the window's own buffer: the pixel size
    has to be exactly `_PIXEL_W` x `_PIXEL_H` for the comparison to mean
    anything, and a window manager is free to hand back a different drawable.

    Returns rows top-down, matching `MemorySurface` — `GLRenderer.read_frame`
    does the flip.
    """
    var target = _GLTarget(GL(), _PIXEL_W, _PIXEL_H)

    var state = PersistentCanvasState(RenderBackend.GPU)
    var context = Context()
    var program = _create(context, state, shape)
    context.time._start(0)
    context.time._tick(16)
    state = step(program, context, state^)
    state.backend.present_gpu(_PIXEL_W, _PIXEL_H, state.view.scale)

    # The same readback `save_screenshot` uses, so the parity test and the
    # library cannot drift in how a GL frame is read or which way up it is.
    var out = state.backend.gl.value().read_frame(_PIXEL_W, _PIXEL_H)

    # Rule 3: both renderers' GL objects are freed while the context — still
    # owned by `win`, in the caller — is current.
    _ = state^
    _ = target^
    return out^


def test_the_gl_backend_matches_the_cpu_backend() raises -> None:
    var win: GLWindow
    try:
        # Tiny and never rendered into: the frame goes to an FBO, and this exists
        # only because a GL context needs a window to belong to.
        win = GLWindow("parity", 64, 64)
    except e:
        print("SKIP — no GL context:", e)
        return

    for shape in range(_SHAPE_COUNT):
        var name = _shape_name(shape)
        var gpu = _gpu_frame(win, shape)
        var cpu = _cpu_frame(shape)

        var cpu_mask = _mask(cpu.data)
        var gpu_mask = _mask(gpu)
        _assert_structural_match(name, cpu_mask, gpu_mask)
        _assert_interior_colour_matches(name, cpu.data, gpu, cpu_mask, gpu_mask)

    _ = win^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
