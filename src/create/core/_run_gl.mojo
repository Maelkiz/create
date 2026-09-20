"""The GPU run loop — the same frame, presented from GL instead of a buffer.

It differs from `run.mojo` in exactly three places, and each is forced:

- the window is a `GLWindow`, so there is a context for `GLRenderer` to bind
  against and no host pixel buffer at all;
- the viewport is sized from `drawable_size()` rather than `width()`/
  `height()`, because those are SDL's *logical* size and differ from the
  backing pixels under HiDPI or fractional scaling — sizing `glViewport` from
  the logical number stretches or clips the frame;
- presenting is `present_gpu` plus `swap_buffers` rather than `present` onto a
  `Surface`.

Everything else — the event arms, the clock, `step` — is shared code, so the
two loops cannot drift in what a frame is.
"""

from std.time import sleep

from window import GLWindow

from create.render.render_backend import RenderBackend
from create.render.autoscale import AutoScale
from create.render.canvas import PersistentCanvasState

from ._events import apply_events
from ._frame import step
from .context import Context
from .input import Input
from .program import Program
from .window_mode import WindowMode

comptime _MSAA_SAMPLES = 4
"""Antialiasing is the framebuffer's job here, not the tessellator's: the CPU
path antialiases nothing, and analytic coverage per shape would cost a second
geometry path for every kind. A driver that refuses the request fails context
creation outright, so the caller retries once without it."""


def _open_window(
    title: String,
    width: Int,
    height: Int,
    mode: Int,
    resizable: Bool,
) raises -> GLWindow:
    """A multisampled GL window, falling back to none if the driver refuses.

    `GLWindow` deliberately does not degrade silently — an unsupported sample
    count fails context creation — so the retry is here, where a missing
    antialias is a better outcome than a program that will not start.
    """
    var fullscreen = mode == WindowMode.FULLSCREEN
    var borderless = mode == WindowMode.BORDERLESS
    try:
        return GLWindow(
            title,
            width,
            height,
            msaa=_MSAA_SAMPLES,
            fullscreen=fullscreen,
            resizable=resizable,
            borderless=borderless,
        )
    except:
        return GLWindow(
            title,
            width,
            height,
            fullscreen=fullscreen,
            resizable=resizable,
            borderless=borderless,
        )


def _update_dimensions(mut win: GLWindow, mut ctx: Context) raises -> Float64:
    """Point the viewport at the backing pixels; return pixels per point.

    The ratio goes to the event arms, which receive pointer positions in
    logical coordinates and must map them through a viewport measured in
    pixels.
    """
    var drawable = win.drawable_size()
    ctx._set_viewport(drawable[0], drawable[1])
    var logical = win.width()
    return Float64(drawable[0]) / Float64(logical) if logical > 0 else 1.0


def _wait_for_dimensions(mut win: GLWindow, mut ctx: Context) raises:
    # Same bogus (1, 1) as the windowed loop: pump until the size is usable.
    _ = _update_dimensions(win, ctx)
    while ctx.width <= 1 or ctx.height <= 1:
        _ = win.events()
        _ = _update_dimensions(win, ctx)


def _cap_frame_rate(mut win: GLWindow, ctx: Context, frame_start: Int) raises:
    """Sleep off whatever is left of the target frame duration, if any."""
    if ctx._frame_cap_fps <= 0:
        return
    var worked_ms = win.ticks() - frame_start
    var target_ms = 1000.0 / Float64(ctx._frame_cap_fps)
    var remaining_ms = target_ms - Float64(worked_ms)
    if remaining_ms > 0.0:
        sleep(remaining_ms / 1000.0)


def _run_loop[
    P: Program
](mut program: P, mut win: GLWindow, mut ctx: Context, mut input: Input) raises:
    # Built after the window because its GL resources need a current context.
    var state = PersistentCanvasState(RenderBackend.GPU)
    ctx.time._start(win.ticks())
    while win.is_open() and not ctx._quit:
        var px_per_point = _update_dimensions(win, ctx)
        if apply_events(win.events(), ctx, input, px_per_point):
            win.close()
        var frame_start = win.ticks()
        ctx.time._tick(frame_start)
        # Re-read after events: a resize this frame changed the drawable, and
        # the bars have to reach the edge of the *new* one.
        var drawable = win.drawable_size()
        state = step(program, ctx, input, state^)
        state.backend.present_gpu(drawable[0], drawable[1], ctx.view.scale)
        win.swap_buffers()
        _cap_frame_rate(win, ctx, frame_start)
    # Rule 3 from `_gl.mojo`: the context owner must outlive the last GL call,
    # and the renderer inside `state` makes them when it is destroyed.
    _ = state^
    _ = win


def run_gl[
    P: Program
](
    title: String,
    width: Int = 1280,
    height: Int = 720,
    mode: Int = WindowMode.WINDOWED,
    vsync: Bool = True,
    resizable: Bool = True,
) raises:
    """Open a GL window and run `P` on the GPU backend until it quits.

    `mode` covers the display (`WindowMode.FULLSCREEN`/`BORDERLESS`); the
    design resolution is still `width`/`height`, so the program is authored
    in the same space either way and the viewport scales it to whatever the
    display turns out to be.

    `vsync=False` is for benchmarking only: without it every frame waits for
    the display and the measurement is the refresh rate rather than the
    renderer.

    The design-resolution contract is `run`'s, unchanged: `width`/`height` are
    both the window size and the space the program is authored in, scaled to
    the window by `AutoScale.FIT` unless `create` says otherwise.
    """
    var win = _open_window(title, width, height, mode, resizable)
    win.set_swap_interval(1 if vsync else 0)
    var ctx = Context()
    ctx.view.set_design(width, height)
    ctx.autoscale = AutoScale.FIT
    _wait_for_dimensions(win, ctx)
    var program = P.create(ctx)
    # create() may have pinned its own design size or changed the mode.
    _ = _update_dimensions(win, ctx)
    var input = Input()
    _run_loop(program, win, ctx, input)
