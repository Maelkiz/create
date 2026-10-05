from create._window.window import Window
from create.render.antialiasing import Antialiasing
from create.render.autoscale import AutoScale
from create.render.render_backend import RenderBackend
from create.render.canvas import PersistentCanvasState
from create.core.context import Context
from ._events import apply_events
from ._step import first_step, step
from ._window_loop import _finish_frame
from create.render.surface import Surface
from .program import Program
from .window_mode import WindowMode
from ._run_gl import run_gl


def _update_dimensions(
    mut win: Window, mut state: PersistentCanvasState, context: Context
) raises:
    context._set_viewport(state, win.width(), win.height())


def _wait_for_dimensions(
    mut win: Window, mut state: PersistentCanvasState, context: Context
) raises:
    # For fullscreen, SDL fires a bogus (1, 1) Resized before reporting real
    # dimensions — pump events until the window reports a usable size.
    _update_dimensions(win, state, context)
    while state.view.width <= 1 or state.view.height <= 1:
        _ = win.events()
        _update_dimensions(win, state, context)


def _process_events(
    mut win: Window,
    state: PersistentCanvasState,
    mut context: Context,
) raises:
    if apply_events(win.events(), state.view, context):
        win.close()


def _present(mut win: Window, mut state: PersistentCanvasState) raises:
    var pixel_w = win.width()
    var pixel_h = win.height()
    state.backend.present(
        Surface(win.pixels(), pixel_w, pixel_h), state.view.scale
    )
    win.present()


def _run_loop[
    P: Program
](
    mut program: P,
    mut win: Window,
    var state: PersistentCanvasState,
    mut context: Context,
) raises:
    # Seeded here rather than in run() so the program's create() — which may
    # load fonts or decode audio — does not land in the first frame's delta.
    context.time._start(win.ticks())
    while win.is_open() and not context._quit:
        # Dimensions are refreshed before events so pointer positions are
        # mapped with this frame's scale, not the previous one's.
        _update_dimensions(win, state, context)
        _process_events(win, state, context)
        # Re-derive after events: a resize this frame reallocated the pixel
        # buffer, so the mapping taken above is one frame stale while the
        # framebuffer is already the new size. Rendering that frame against the
        # old mapping puts it in a corner of the new buffer — one crooked
        # frame, and a permanent ghost in a program that never clears.
        _update_dimensions(win, state, context)
        var frame_start = win.ticks()
        context._advance_frame(frame_start)
        # The Surface is taken here, after events, because Window._resize
        # reallocates the pixel buffer: one taken before them could point at
        # freed memory. Its extent comes from the window rather than the
        # viewport for the same reason — the viewport was measured before the
        # resize, and a stale width would run the raster loops off the new
        # buffer.
        state = step(program, context, state^)
        _present(win, state)
        _finish_frame(win, context, frame_start)


def run[
    P: Program
](
    title: String,
    mode: WindowMode = WindowMode.WINDOWED,
    width: Int = 1280,
    height: Int = 720,
    backend: RenderBackend = RenderBackend.CPU,
    resizable: Bool = True,
    antialiasing: Antialiasing = Antialiasing.MEDIUM,
    autoscale: AutoScale = AutoScale.FIT,
) raises:
    """Open a window and run `P` in it until it quits.

    `width`/`height` are the design size: the space the program is
    **authored** in, and the one `canvas.width`/`height`, the canvas edges and
    `context.input.mouse` are reported in. They are not a window size that happens to double as one: a
    `WINDOWED` or `BORDERLESS` launch opens a window of that size because the
    two coincide there, while `FULLSCREEN` and `MAXIMIZED` take the display or
    its work area and the design is scaled onto it. `mode=FULLSCREEN` with a
    size therefore means *author at that size, present fullscreen*.

    The scaling is `autoscale`, `AutoScale.FIT` by default, so a program keeps
    its layout on any display:

    | call                                          | FIT / EXTEND             | OFF            |
    |-----------------------------------------------|--------------------------|----------------|
    | `run("T", width=1000, height=1000)`           | design 1000x1000, scaled | world = window |
    | `run("T", FULLSCREEN, width=1000, height=1000)`| design 1000x1000, scaled | world = monitor|
    | `run("T", WindowMode.FULLSCREEN)`             | design 1280x720, scaled  | world = monitor|

    `AutoScale.OFF` is the opt-out, and the only way the size here stops
    meaning anything: the design size goes unused and coordinates become
    the window's own pixels, which is how a program authors against the
    display rather than against a fixed space. `context.autoscale(mode)`
    switches it later in the run.

    `context.design_size(w, h)` pins the same space from inside `create`, which
    is where a program with an opinion of its own states it. The size here is
    the shorthand for the common case where the window and the design agree.

    `backend=RenderBackend.GPU` runs the same program through the GL backend
    instead — a different window, a different loop, and the same frame. It is
    a branch rather than a value the loop holds because Mojo 1.0 has no
    dynamic trait dispatch, which is also why `Backend` switches on a `kind`.

    `antialiasing` smooths the edges of shapes on either backend
    (`Antialiasing.MEDIUM` by default, `OFF` for hard pixels). See
    `Antialiasing`.
    """
    var fullscreen = mode == WindowMode.FULLSCREEN
    var borderless = mode == WindowMode.BORDERLESS
    var maximized = mode == WindowMode.MAXIMIZED
    if backend == RenderBackend.GPU:
        run_gl[P](
            title,
            mode,
            width,
            height,
            resizable=resizable,
            antialiasing=antialiasing,
            autoscale=autoscale,
        )
        return
    var win = Window(
        title,
        width,
        height,
        fullscreen,
        resizable=resizable,
        borderless=borderless,
        maximized=maximized,
    )
    # Style and loaded fonts live here rather than in the Canvas, which is
    # rebuilt every frame; the transform stack deliberately does not, so each
    # frame starts unrotated and untranslated.
    var state = PersistentCanvasState()
    state.backend.antialiasing = antialiasing
    # The size the program is authored against is always what the caller asked
    # for, never what the display handed back. In fullscreen SDL ignores the
    # requested size, so seeding this from the window would make the design
    # space a property of the user's monitor rather than of the program.
    #
    # Scaling that design to the window is the default because the alternative
    # punishes the obvious way to write a program: laid-out coordinates that
    # break on a display the author never had. `autoscale=AutoScale.OFF` opts
    # back out.
    var context = Context()
    context.design_size(width, height)
    context.autoscale(autoscale)
    # The mapping comes from `run`'s arguments and is in place before
    # create(), so a dial create() turns applies from the next frame, as it
    # does from `update`.
    _wait_for_dimensions(win, state, context)
    var program = first_step[P](context, state)
    _present(win, state)
    _run_loop(program, win, state^, context)
