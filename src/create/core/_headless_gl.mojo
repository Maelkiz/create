"""The headless GPU loop: `run_headless`'s frame, presented into an offscreen
`_GLTarget` instead of a `MemorySurface`, then read back into one.

Exists for the same reason `run_headless` does — no window, no display, a
plain owned buffer at the end — but through the GL backend, so a test can
assert on GPU-only behaviour (batching, texture-unit coexistence, vertex
buffer growth) that the CPU-vs-GPU parity test is structurally blind to.

Does **not** cover the drawable-size-versus-logical-size distinction that
`_run_gl.mojo` re-reads every frame (Gotcha 6): an FBO has one size and no
window manager to disagree with it. That stays a windowed-only concern.
"""

from create._window import GLWindow

from create.render._gl import GL
from create.render._gl_target import _GLTarget
from create.render.render_backend import RenderBackend
from create.render.autoscale import AutoScale
from create.render.canvas import PersistentCanvasState
from create.render.context import Context
from create.render.surface import MemorySurface

from ._step import step
from .headless import _FRAME_MILLIS
from .program import Program

comptime _HEADLESS_MSAA_SAMPLES = 4


def _open_headless_window(msaa: Bool) raises -> GLWindow:
    """Tiny and never rendered into — the frame lands in the `_GLTarget` FBO,
    and this exists only because a GL context needs a window to belong to.

    This is what raises when there is no GL context at all.
    """
    if msaa:
        try:
            return GLWindow("headless", 64, 64, msaa=_HEADLESS_MSAA_SAMPLES)
        except:
            pass
    return GLWindow("headless", 64, 64)


def _run_headless_gl[
    P: Program
](
    width: Int,
    height: Int,
    frames: Int = 1,
    pixel_width: Int = 0,
    pixel_height: Int = 0,
    msaa: Bool = False,
) raises -> MemorySurface:
    """Run `P` for `frames` frames through the GPU backend and return the
    last frame as a `MemorySurface`.

    Same contract as `run_headless`, down to which frame `step` sees — the
    only difference is where the pixels come from: a `_GLTarget` framebuffer
    object, read back once after the last frame rather than replayed onto an
    owned buffer every frame. Raises if no GL context can be created; never
    falls back to the CPU backend, which would let a "GPU" test pass without
    touching a driver.

    `msaa` is a lever for later antialiasing work — off by default, matching
    why the parity test also disables it — and does not yet change how the
    `_GLTarget` itself is built.
    """
    var pw = pixel_width if pixel_width > 0 else width
    var ph = pixel_height if pixel_height > 0 else height

    var win = _open_headless_window(msaa)
    var target = _GLTarget(GL(), pw, ph)

    # After the window: its GL resources need a current context.
    var state = PersistentCanvasState(RenderBackend.GPU)
    var context = Context()
    context.design_resolution(width, height, AutoScale.FIT)
    var program = P.create(context)
    # After create(), which may have pinned its own design size or mode.
    state._set_viewport(context, pw, ph)
    var now = 0
    context.time._start(now)
    for _ in range(frames):
        if context._quit:
            break
        now += _FRAME_MILLIS
        context.time._tick(now)
        state = step(program, context, state^)
        state.backend.present_gpu(pw, ph, state.view.scale)

    var pixels = state.backend.gl.value().read_frame(pw, ph)
    var mem = MemorySurface(pw, ph)
    mem.data = pixels^

    # Rule 3 from `_gl.mojo`: the context owner must outlive the last GL
    # call, and both `state`'s renderer and `target` make them when torn
    # down.
    _ = state^
    _ = target^
    _ = win^
    return mem^
