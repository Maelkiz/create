from create.render.canvas import PersistentCanvasState
from create.core.context import Context
from create.render.antialiasing import Antialiasing
from create.render.autoscale import AutoScale
from create.render.render_backend import RenderBackend
from ._step import first_step, step
from ._headless_gl import _run_headless_gl
from .program import Program
from create.render.surface import MemorySurface

comptime _FRAME_MILLIS = 16
"""Synthetic frame duration, so a program that integrates delta is
reproducible run to run rather than dependent on how fast the test machine
got through the loop."""


def run_headless[
    P: Program
](
    width: Int,
    height: Int,
    frames: Int = 1,
    pixel_width: Int = 0,
    pixel_height: Int = 0,
    backend: RenderBackend = RenderBackend.CPU,
    antialiasing: Antialiasing = Antialiasing.MEDIUM,
    autoscale: AutoScale = AutoScale.FIT,
) raises -> MemorySurface:
    """Run `P` over an owned buffer — `create`'s frame, then `frames` calls
    to `update` — and return the buffer.

    The same sequence as `run`, minus the window: `create` draws frame 1,
    then `update` draws one frame per call, with the letterbox painted after
    each. `frames=0` returns `create`'s frame alone. `width`
    and `height` are the design size; `pixel_width`/`pixel_height` are
    the framebuffer, defaulting to the same size — pass a different shape to
    exercise autoscale, since a design that matches the framebuffer maps 1:1
    and leaves no bars.

    Time is synthetic and the input is empty, so the result depends only on
    the program.

    `backend=RenderBackend.GPU` runs the same frames through the GL backend
    into an offscreen framebuffer instead, reading the result back at the
    end rather than replaying onto the buffer every frame — see
    `_headless_gl.mojo`. It raises if no GL context can be created; it never
    falls back to the CPU backend.

    `antialiasing` is `run`'s, with the same default. The GPU's offscreen
    framebuffer is not multisampled, so there it reaches only pixel reads
    and `save_image`, which replay on the CPU.

    `autoscale` is `run`'s too: how the design maps onto the framebuffer.
    """
    if backend == RenderBackend.GPU:
        return _run_headless_gl[P](
            width,
            height,
            frames,
            pixel_width,
            pixel_height,
            antialiasing,
            autoscale,
        )
    var pw = pixel_width if pixel_width > 0 else width
    var ph = pixel_height if pixel_height > 0 else height
    var mem = MemorySurface(pw, ph)
    var state = PersistentCanvasState()
    state.backend.antialiasing = antialiasing
    var context = Context()
    context.design_size(width, height)
    context.autoscale(autoscale)
    # Before create(), from the arguments, as in the windowed loops.
    context._set_viewport(state, pw, ph)
    var program = first_step[P](context, state)
    state.backend.present(mem.surface(), state.view.scale)
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
        state.backend.present(mem.surface(), state.view.scale)
    return mem^
