from std.collections import Optional
from std.time import sleep

from window.window import Window
from create.render.render_backend import RenderBackend
from create.render.frame import PersistentFrameState
from ._events import apply_events
from ._step import create_program, step
from create.render.surface import Surface
from .input import Input
from create.render.autoscale import AutoScale
from .program import Program
from .window_mode import WindowMode
from ._run_gl import run_gl


def _update_dimensions(mut win: Window, mut state: PersistentFrameState) raises:
    state._set_viewport(win.width(), win.height())


def _wait_for_dimensions(
    mut win: Window, mut state: PersistentFrameState
) raises:
    # For fullscreen, SDL fires a bogus (1, 1) Resized before reporting real
    # dimensions — pump events until the window reports a usable size.
    _update_dimensions(win, state)
    while state.view.width <= 1 or state.view.height <= 1:
        _ = win.events()
        _update_dimensions(win, state)


def _process_events(
    mut win: Window, mut state: PersistentFrameState, mut input: Input
) raises:
    if apply_events(win.events(), state, input):
        win.close()


def _cap_frame_rate(
    mut win: Window, state: PersistentFrameState, frame_start: Int
) raises:
    """Sleep off whatever is left of the target frame duration, if any."""
    if state._fps_cap <= 0:
        return
    var worked_ms = win.ticks() - frame_start
    var target_ms = 1000.0 / Float64(state._fps_cap)
    var remaining_ms = target_ms - Float64(worked_ms)
    if remaining_ms > 0.0:
        sleep(remaining_ms / 1000.0)


def _run_loop[
    P: Program
](
    mut program: P,
    mut win: Window,
    var state: PersistentFrameState,
    mut input: Input,
) raises:
    # Seeded here rather than in run() so the program's create() — which may
    # load fonts or decode audio — does not land in the first frame's delta.
    state.time._start(win.ticks())
    while win.is_open() and not state._quit:
        # Dimensions are refreshed before events so pointer positions are
        # mapped with this frame's scale, not the previous one's.
        _update_dimensions(win, state)
        _process_events(win, state, input)
        # Re-derive after events: a resize this frame reallocated the pixel
        # buffer, so the mapping taken above is one frame stale while the
        # framebuffer is already the new size. Drawing that frame against the
        # old mapping puts it in a corner of the new buffer — one crooked
        # frame, and a permanent ghost in a program that never clears.
        _update_dimensions(win, state)
        var frame_start = win.ticks()
        state.time._tick(frame_start)
        # The Surface is taken here, after events, because Window._resize
        # reallocates the pixel buffer: one taken before them could point at
        # freed memory. Its extent comes from the window rather than the
        # viewport for the same reason — the viewport was measured before the
        # resize, and a stale width would run the raster loops off the new
        # buffer.
        var pixel_w = win.width()
        var pixel_h = win.height()
        state = step(program, input, state^)
        state.backend.present(
            Surface(win.pixels(), pixel_w, pixel_h), state.view.scale
        )
        win.present()
        _cap_frame_rate(win, state, frame_start)


def run[
    P: Program
](
    title: String,
    mode: WindowMode = WindowMode.WINDOWED,
    width: Int = 1280,
    height: Int = 720,
    backend: RenderBackend = RenderBackend.CPU,
    resizable: Bool = True,
) raises:
    """Open a window and run `P` in it until it quits.

    `width`/`height` are the resolution the program is **authored** in — the
    space `frame.width`/`height`, the frame edges and `input.mouse` are
    reported in. They are not a window size that happens to double as one: a
    `WINDOWED` or `BORDERLESS` launch opens a window of that size because the
    two coincide there, while `FULLSCREEN` and `MAXIMIZED` take the display or
    its work area and the design is scaled onto it. `mode=FULLSCREEN` with a
    size therefore means *author at that size, present fullscreen*.

    The scaling is `AutoScale.FIT` unless `create` sets `frame.autoscale`, so
    a program keeps its layout on any display:

    | call                                          | FIT / EXTEND             | OFF            |
    |-----------------------------------------------|--------------------------|----------------|
    | `run("T", width=1000, height=1000)`           | design 1000x1000, scaled | world = window |
    | `run("T", FULLSCREEN, width=1000, height=1000)`| design 1000x1000, scaled | world = monitor|
    | `run("T", WindowMode.FULLSCREEN)`             | design 1280x720, scaled  | world = monitor|

    `AutoScale.OFF` is the opt-out, and the only way the size here stops
    meaning anything: the design resolution goes unused and coordinates become
    the window's own pixels, which is how a program authors against the
    display rather than against a fixed space.

    `frame.design_resolution(w, h, mode)` pins the same space from inside `create`, which
    is where a program with an opinion of its own states it. The size here is
    the shorthand for the common case where the window and the design agree.

    `backend=RenderBackend.GPU` runs the same program through the GL backend
    instead — a different window, a different loop, and the same frame. It is
    a branch rather than a value the loop holds because Mojo 1.0 has no
    dynamic trait dispatch, which is also why `Backend` switches on a `kind`.
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
    # Style and loaded fonts live here rather than in the Frame, which is
    # rebuilt every frame; the transform stack deliberately does not, so each
    # frame starts unrotated and untranslated.
    var state = PersistentFrameState()
    # The size the program is authored against is always what the caller asked
    # for, never what the display handed back. In fullscreen SDL ignores the
    # requested size, so seeding this from the window would make the design
    # space a property of the user's monitor rather than of the program.
    state.view.set_design(width, height)
    # Scaling the design to the window is the default because the alternative
    # punishes the obvious way to write a program: laid-out coordinates that
    # break on a display the author never had. `create` can opt back out with
    # `frame.autoscale = AutoScale.OFF`.
    state.autoscale = AutoScale.FIT
    _wait_for_dimensions(win, state)
    var created = Optional[P]()
    state = create_program[P](state^, created)
    var program = created.take()
    # create() may have changed the mode or pinned its own design size, so the
    # mapping derived above is stale by the time it returns — re-derive it
    # before the first frame.
    _update_dimensions(win, state)
    var input = Input()
    _run_loop(program, win, state^, input)
