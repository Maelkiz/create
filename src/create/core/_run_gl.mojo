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

from create._window import GLWindow

from create.render.antialiasing import Antialiasing
from create.render.autoscale import AutoScale
from create.render.render_backend import RenderBackend
from create.render.canvas import PersistentCanvasState
from create.core.context import Context

from ._events import apply_events
from ._step import step
from ._window_loop import _finish_frame
from .program import Program
from .window_mode import WindowMode


def _open_window(
    title: String,
    mode: WindowMode,
    width: Int,
    height: Int,
    resizable: Bool,
    antialiasing: Antialiasing,
) raises -> GLWindow:
    """A GL window multisampled as asked, or as near below it as the driver
    allows.

    Antialiasing is the framebuffer's job here, not the tessellator's:
    analytic coverage per shape would cost a second geometry path for every
    kind. `GLWindow` deliberately does not degrade silently — an unsupported
    sample count fails context creation — so the step down is here, a level
    at a time until the driver accepts one. Only a failure with none at all
    raises.
    """
    var fullscreen = mode == WindowMode.FULLSCREEN
    var borderless = mode == WindowMode.BORDERLESS
    var maximized = mode == WindowMode.MAXIMIZED
    var level = antialiasing
    while True:
        try:
            return GLWindow(
                title,
                width,
                height,
                msaa=level._gpu_samples(),
                fullscreen=fullscreen,
                resizable=resizable,
                borderless=borderless,
                maximized=maximized,
            )
        except e:
            if level == Antialiasing.OFF:
                raise e
            level = level._lower()


def _update_dimensions(
    mut win: GLWindow, mut state: PersistentCanvasState, context: Context
) raises -> Float64:
    """Point the viewport at the backing pixels; return pixels per point.

    The ratio goes to the event arms, which receive pointer positions in
    logical coordinates and must map them through a viewport measured in
    pixels.
    """
    var drawable = win.drawable_size()
    context._set_viewport(state, drawable[0], drawable[1])
    var logical = win.width()
    return Float64(drawable[0]) / Float64(logical) if logical > 0 else 1.0


def _wait_for_dimensions(
    mut win: GLWindow, mut state: PersistentCanvasState, context: Context
) raises:
    # Same bogus (1, 1) as the windowed loop: pump until the size is usable.
    _ = _update_dimensions(win, state, context)
    while state.view.width <= 1 or state.view.height <= 1:
        _ = win.events()
        _ = _update_dimensions(win, state, context)


def _run_loop[
    P: Program
](
    mut program: P,
    mut win: GLWindow,
    var state: PersistentCanvasState,
    mut context: Context,
) raises:
    context.time._start(win.ticks())
    while win.is_open() and not context._quit:
        var px_per_point = _update_dimensions(win, state, context)
        if apply_events(win.events(), state.view, context, px_per_point):
            win.close()
        # Re-read after events: a resize this frame changed the drawable, and
        # the bars have to reach the edge of the *new* one. The viewport is
        # re-derived from it too — the mapping taken before the events is one
        # frame stale, and rendering against it puts the whole frame in a corner
        # of the resized drawable.
        _ = _update_dimensions(win, state, context)
        var frame_start = win.ticks()
        context._advance_frame(frame_start)
        var drawable = win.drawable_size()
        state = step(program, context, state^)
        state.backend.present_gpu(drawable[0], drawable[1], state.view.scale)
        win.swap_buffers()
        _finish_frame(win, context, frame_start)
    # Rule 3 from `_gl.mojo`: the context owner must outlive the last GL call,
    # and the renderer inside `state` makes them when it is destroyed.
    _ = state^
    _ = win


def run_gl[
    P: Program
](
    title: String,
    mode: WindowMode = WindowMode.WINDOWED,
    width: Int = 1280,
    height: Int = 720,
    vsync: Bool = True,
    resizable: Bool = True,
    antialiasing: Antialiasing = Antialiasing.MEDIUM,
    autoscale: AutoScale = AutoScale.FIT,
) raises:
    """Open a GL window and run `P` on the GPU backend until it quits.

    `mode` covers the display (`WindowMode.FULLSCREEN`/`BORDERLESS`); the
    design size is still `width`/`height`, so the program is authored
    in the same space either way and the viewport scales it to whatever the
    display turns out to be.

    `antialiasing` is the multisampling level, stepped down if the driver
    refuses it; pixel reads replay at the same level on the CPU. See
    `Antialiasing`.

    `vsync=False` is for benchmarking only: without it every frame waits for
    the display and the measurement is the refresh rate rather than the
    renderer.

    The design-size contract is `run`'s, unchanged: `width`/`height` are
    both the window size and the space the program is authored in, scaled to
    the window by `autoscale`.
    """
    var win = _open_window(title, mode, width, height, resizable, antialiasing)
    win.set_swap_interval(1 if vsync else 0)
    # Built after the window because its GL resources need a current context;
    # the state now carries the viewport too, so it has to exist before
    # `_wait_for_dimensions` rather than inside the loop.
    var state = PersistentCanvasState(RenderBackend.GPU)
    state.backend.antialiasing = antialiasing
    var context = Context()
    context.design_size(width, height)
    context.autoscale(autoscale)
    var program = P.create(context)
    # The mapping is derived once create() has had its say about the design
    # size and the mode.
    _wait_for_dimensions(win, state, context)
    _run_loop(program, win, state^, context)
