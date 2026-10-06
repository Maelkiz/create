"""The headless GPU loop: `run_headless`'s frame, presented into an offscreen
`_GLTarget` instead of a `MemorySurface`, then read back into one.

Exists for the same reason `run_headless` does — no window, no display, a
plain owned buffer at the end — but through the GL backend, so a test can
assert on GPU-only behaviour (batching, texture-unit coexistence, vertex
buffer growth) that the CPU-vs-GPU parity test is structurally blind to.

Does **not** cover the drawable-size-versus-logical-size distinction that
`_run_gl.mojo` re-reads every frame: an FBO has one size and no
window manager to disagree with it. That stays a windowed-only concern.
"""

from create._window import GLWindow

from create.render._gl import GL
from create.render._gl_target import _GLTarget
from create.render.antialiasing import Antialiasing
from create.render.autoscale import AutoScale
from create.render.render_backend import RenderBackend
from create.render.canvas import PersistentCanvasState
from create.core.context import Context
from create.render.surface import MemorySurface

from ._step import first_step, step
from .headless import _FRAME_MILLIS
from .program import Program


def _open_headless_window() raises -> GLWindow:
    """Tiny and never rendered into — the frame lands in the `_GLTarget` FBO,
    and this exists only because a GL context needs a window to belong to.
    So it is not multisampled either, and offscreen: never shown, no display
    needed.

    This is what raises when there is no GL context at all.
    """
    return GLWindow("headless", 64, 64, offscreen=True)


def _run_headless_gl[
    P: Program
](
    width: Int,
    height: Int,
    frames: Int = 1,
    pixel_width: Int = 0,
    pixel_height: Int = 0,
    antialiasing: Antialiasing = Antialiasing.OFF,
    autoscale: AutoScale = AutoScale.FIT,
) raises -> MemorySurface:
    """Run `P` through the GPU backend — `create`'s frame, then `frames`
    calls to `update` — and return the last frame as a `MemorySurface`.

    Same contract as `run_headless`, down to which frame `step` sees — the
    only difference is where the pixels come from: a `_GLTarget` framebuffer
    object, read back once after the last frame rather than replayed onto an
    owned buffer every frame. Raises if no GL context can be created; never
    falls back to the CPU backend, which would let a "GPU" test pass without
    touching a driver.

    `antialiasing` multisamples as in a window: the renderer draws into its
    own multisampled framebuffer and resolves into the `_GLTarget`.
    """
    var pw = pixel_width if pixel_width > 0 else width
    var ph = pixel_height if pixel_height > 0 else height

    var win = _open_headless_window()
    var target = _GLTarget(GL(), pw, ph)

    # After the window: its GL resources need a current context.
    var state = PersistentCanvasState(RenderBackend.GPU)
    state.backend.antialiasing = antialiasing
    var context = Context()
    context.design_size(width, height)
    context.autoscale(autoscale)
    # Before create(), from the arguments, as in the windowed loops.
    context._set_viewport(state, pw, ph)
    var program = first_step[P](context, state)
    state.backend.present_gpu(pw, ph, state.view.scale)
    var now = 0
    context.time._start(now)
    for _ in range(frames):
        if context._quit:
            break
        # Re-derived every frame, as the windowed loops do, so a dial turned
        # in create() or a previous update() reaches this one.
        context._set_viewport(state, pw, ph)
        now += _FRAME_MILLIS
        context._advance_frame(now)
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
