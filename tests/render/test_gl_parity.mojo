"""One shape kind at a time, drawn on both backends, compared structurally.

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

**It skips without a display.** There is no CI, `pixi run test` has to stay
runnable over SSH, and a GL context needs a compositor.
"""

from std.os import getenv
from std.math import abs, max, min
from std.testing import TestSuite, assert_true

from create import *
from create.core._frame import step
from create.render.render_backend import RenderBackend
from create.render._gl import (
    GL,
    GL_COLOR_ATTACHMENT0,
    GL_CLAMP_TO_EDGE,
    GL_FRAMEBUFFER,
    GL_FRAMEBUFFER_COMPLETE,
    GL_NEAREST,
    GL_RGBA,
    GL_RGBA8,
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_TEXTURE_MIN_FILTER,
    GL_TEXTURE_WRAP_S,
    GL_TEXTURE_WRAP_T,
    GL_UNSIGNED_BYTE,
    _UInts,
)
from create.render.canvas import PersistentCanvasState
from window import GLWindow

comptime _DESIGN_W = 200
comptime _DESIGN_H = 150
comptime _PIXEL_W = 240
"""Wider than the design, so `FIT` leaves a letterbox bar on each side while
the scale factor stays exactly 1 — a resampled sprite would be comparing two
interpolation rules rather than two backends."""
comptime _PIXEL_H = 150

comptime _CONTENT_X0 = (_PIXEL_W - _DESIGN_W) // 2
comptime _CONTENT_X1 = _CONTENT_X0 + _DESIGN_W
comptime _CONTENT_Y0 = (_PIXEL_H - _DESIGN_H) // 2
comptime _CONTENT_Y1 = _CONTENT_Y0 + _DESIGN_H
"""The FIT-mapped content rect, at the scale-1 mapping documented on
`_PIXEL_W`. Masking outside it excludes the letterbox bars, which are a
constant `0x22` rather than `_BACKGROUND` and would otherwise swamp every
shape's bounding box and centroid with two fixed strips neither backend
moves."""

comptime _BACKGROUND = Color(0x20, 0x30, 0x40)
comptime _INK_THRESHOLD = 8
"""How far from the background a pixel has to be to count as drawn on."""

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

comptime _SHAPE_RECT = 0
comptime _SHAPE_STROKED_RECT = 1
comptime _SHAPE_CIRCLE = 2
comptime _SHAPE_LINE = 3
comptime _SHAPE_TRIANGLE = 4
comptime _SHAPE_SPRITE = 5
comptime _SHAPE_TEXT = 6
comptime _SHAPE_ROTATED_RECT = 7
comptime _SHAPE_COUNT = 8


def _shape_name(shape: Int) -> String:
    if shape == _SHAPE_RECT:
        return "rect"
    elif shape == _SHAPE_STROKED_RECT:
        return "stroked rect"
    elif shape == _SHAPE_CIRCLE:
        return "circle"
    elif shape == _SHAPE_LINE:
        return "line"
    elif shape == _SHAPE_TRIANGLE:
        return "triangle"
    elif shape == _SHAPE_SPRITE:
        return "sprite"
    elif shape == _SHAPE_TEXT:
        return "text"
    else:
        return "rotated rect"


@fieldwise_init
struct _Parity(Program):
    """One command kind the GL backend implements, picked by `shape`."""

    var logo: Sprite
    var shape: Int

    @staticmethod
    def create(mut ctx: Context) raises -> _Parity:
        return _Parity.create(ctx, _SHAPE_RECT)

    @staticmethod
    def create(mut ctx: Context, shape: Int) raises -> _Parity:
        ctx.autoscale = AutoScale.FIT
        ctx.design(_DESIGN_W, _DESIGN_H)
        return _Parity(Sprite.load("tests/fixtures/test_2x2.png"), shape)

    def render(self, mut canvas: Canvas) raises:
        canvas.background(_BACKGROUND)

        if self.shape == _SHAPE_RECT:
            with canvas.style():
                canvas.no_stroke()
                canvas.fill(Color(0xE0, 0x40, 0x40))
                canvas.rectangle((-20, 20), 50, 30)
        elif self.shape == _SHAPE_STROKED_RECT:
            with canvas.style():
                canvas.fill(Color(0x40, 0xC0, 0xE0))
                canvas.stroke(Color.BLACK)
                canvas.stroke_width(4)
                canvas.rectangle((10, 40), 50, 30)
        elif self.shape == _SHAPE_CIRCLE:
            with canvas.style():
                canvas.no_stroke()
                canvas.fill(Color(0xF0, 0xC0, 0x30))
                canvas.circle((-60, -20), 24)
        elif self.shape == _SHAPE_LINE:
            with canvas.style():
                canvas.stroke(Color(0x80, 0xFF, 0x80))
                canvas.stroke_width(3)
                canvas.line((-90, -60), (90, -60))
        elif self.shape == _SHAPE_TRIANGLE:
            with canvas.style():
                canvas.no_stroke()
                canvas.fill(Color(0xA0, 0x60, 0xF0))
                canvas.triangle((20, -50), (70, -50), (45, -5))
        elif self.shape == _SHAPE_SPRITE:
            # Native size: at a scale of 1 neither backend resamples, so this
            # is testing the blit, not the filter.
            canvas.sprite(self.logo, 70, 50, 2, 2)
        elif self.shape == _SHAPE_TEXT:
            with canvas.style():
                canvas.no_stroke()
                canvas.fill(Color.WHITE)
                canvas.font_size(16)
                canvas.text_align(Align.CENTER)
                canvas.text("parity", 0, 0)
        else:
            # Rotation defeats the axis-aligned fast path on both backends,
            # so this exercises the CPU's non-uniform inverse-mapping branch
            # against the GL tessellator's per-vertex transform — the one
            # shape kind the parity set otherwise never touches.
            with canvas.style():
                canvas.no_stroke()
                canvas.fill(Color(0x60, 0xE0, 0x90))
                with canvas.transform(rotate(0.5)):
                    canvas.rectangle((30, -70), 40, 20)


def _mask(pixels: List[UInt8]) -> List[Bool]:
    """Which pixels are not the background, restricted to the content rect.

    Outside it is the letterbox, painted the same fixed colour by both
    backends regardless of what `_Parity` draws — never ink, so a shape can
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
    eight neighbours are too — i.e. nowhere near an edge, where the two fill
    rules (or, later, antialiasing) are entitled to disagree.
    """
    var total = 0
    var count = 0
    for y in range(1, _PIXEL_H - 1):
        for x in range(1, _PIXEL_W - 1):
            var i = y * _PIXEL_W + x
            if not (cpu_mask[i] and gpu_mask[i]):
                continue
            var interior = True
            for dy in range(-1, 2):
                for dx in range(-1, 2):
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
        # Thin shapes (the line, the sprite at this size) may have no pixel
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


def _cpu_frame(shape: Int) raises -> MemorySurface:
    """One shape's frame through the CPU backend, onto an owned buffer.

    Not `run_headless`: that drives `Program.create`'s single-argument
    trait method, and `_Parity` needs the extra `shape` argument to pick
    which command it records this frame. Otherwise identical to it.
    """
    var mem = MemorySurface(_PIXEL_W, _PIXEL_H)
    var ctx = Context()
    ctx.view.set_design(_DESIGN_W, _DESIGN_H)
    ctx.autoscale = AutoScale.FIT
    ctx._set_viewport(_PIXEL_W, _PIXEL_H)
    var program = _Parity.create(ctx, shape)
    ctx._set_viewport(_PIXEL_W, _PIXEL_H)
    var input = Input()
    var state = PersistentCanvasState()
    ctx.time._start(0)
    ctx.time._tick(16)
    state = step(program, ctx, input, state^)
    state.backend.present(mem.surface(), ctx.view.scale)
    return mem^


def _has_display() -> Bool:
    return (
        getenv("DISPLAY").byte_length() > 0
        or getenv("WAYLAND_DISPLAY").byte_length() > 0
    )


def _gpu_frame(mut win: GLWindow, shape: Int) raises -> List[UInt8]:
    """One shape's frame through the GL backend, into an offscreen RGBA
    target.

    A framebuffer object rather than the window's own buffer: the pixel size
    has to be exactly `_PIXEL_W` x `_PIXEL_H` for the comparison to mean
    anything, and a window manager is free to hand back a different drawable.

    Returns rows top-down, matching `MemorySurface` — `GLRenderer.read_frame`
    does the flip.
    """
    var gl = GL()
    var names = List[UInt32](length=1, fill=0)
    gl.gen_textures(1, _UInts(unsafe_from_address=Int(names.unsafe_ptr())))
    var color = names[0]
    gl.bind_texture(GL_TEXTURE_2D, color)
    var blank = List[UInt8](length=_PIXEL_W * _PIXEL_H * 4, fill=0)
    gl.tex_image_2d(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        Int32(_PIXEL_W),
        Int32(_PIXEL_H),
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        Int(blank.unsafe_ptr()),
    )
    _ = blank^
    gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    gl.gen_framebuffers(1, _UInts(unsafe_from_address=Int(names.unsafe_ptr())))
    var fbo = names[0]
    gl.bind_framebuffer(GL_FRAMEBUFFER, fbo)
    gl.framebuffer_texture_2d(
        GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color, 0
    )
    if gl.check_framebuffer_status(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
        raise Error("the offscreen framebuffer is incomplete")

    var ctx = Context()
    ctx.view.set_design(_DESIGN_W, _DESIGN_H)
    ctx.autoscale = AutoScale.FIT
    ctx._set_viewport(_PIXEL_W, _PIXEL_H)
    var program = _Parity.create(ctx, shape)
    ctx._set_viewport(_PIXEL_W, _PIXEL_H)
    var input = Input()
    var state = PersistentCanvasState(RenderBackend.GPU)
    ctx.time._start(0)
    ctx.time._tick(16)
    state = step(program, ctx, input, state^)
    state.backend.present_gpu(_PIXEL_W, _PIXEL_H, ctx.view.scale)

    # The same readback `save_screenshot` uses, so the parity test and the
    # library cannot drift in how a GL frame is read or which way up it is.
    var out = state.backend.gl.value().read_frame(_PIXEL_W, _PIXEL_H)

    gl.bind_framebuffer(GL_FRAMEBUFFER, 0)
    gl.delete_framebuffers(
        1, _UInts(unsafe_from_address=Int(names.unsafe_ptr()))
    )
    # Rule 3: the renderer's GL objects are freed when `state` drops, which
    # must happen while the context is still current.
    _ = state^
    _ = names^
    return out^


def test_the_gl_backend_matches_the_cpu_backend() raises -> None:
    if not _has_display():
        print("SKIP — no DISPLAY or WAYLAND_DISPLAY, so no GL context")
        return
    var win: GLWindow
    try:
        # Tiny and never drawn into: the frame goes to an FBO, and this exists
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
