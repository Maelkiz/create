from create.render.autoscale import AutoScale
from create.render.canvas import Canvas, PersistentCanvasState
from create.color.color import Color

from .time import Time
from .input import Input


@fieldwise_init
struct _Rumble(ImplicitlyCopyable, Movable):
    """One `rumble` call, addressed to the pad by SDL's id rather than its
    slot, so the slot it named when called is the one that rumbles."""

    var id: Int
    var low_frequency: Float64
    var high_frequency: Float64
    var seconds: Float64


struct Context(Copyable, Movable):
    """The run's state: everything that outlives a frame.

    Two directions share it. The loop writes `time` and `input` before each
    `update`, for the program to read; the program sets the dials, for the
    loop to read. Every dial is a method, like the `Canvas` style setters:
    `context.autoclear(False)`, `context.max_frame_rate(30)`. Called with no
    arguments, each reads back the value as set, for a debug overlay or a
    settings screen to show.

    A `Canvas` is built and dropped inside one frame, so a setting that has to
    survive the frame boundary cannot live on it. These do — the autoscale
    mode and design size the next frame's mapping is derived from,
    whether the next frame opens with a clear, the letterbox colour, and the
    ones the run loop reads after a frame has been released, `max_frame_rate`,
    `quit` and `rumble`.

    Handed to `Program.create` on its own, before any frame exists, and
    alongside the `Canvas` to `Program.update`. That is the whole reason it is a
    separate object rather than fields on `Canvas`: `create` has dials to turn
    and nothing to render on, so it is given exactly that — a program cannot
    record a command that will never be presented, and there is no discarded
    frame to explain.

    **Read at frame construction.** `Canvas` takes its copy of `autoclear`
    and `letterbox_color` when it is built, and the loop
    re-derives the viewport from `autoscale` and the design size at the top of
    each frame. So a dial turned part-way through `update` applies to the *next*
    frame, uniformly — the clear of the frame being rendered was recorded before
    `update` was called, and one frame cannot record under two mappings. Set
    them in `create` to have them hold from frame one. `max_frame_rate`,
    `quit` and `rumble` are the exception, and only because the loop reads
    them after the frame body returns. A dial read back after such a change
    reports the new value, not the one the frame in hand was built with.
    """

    var time: Time
    """The frame clock. The run loop ticks it before each `update`; read
    `delta` and `elapsed` here, and don't write it — the loop derives the
    next delta from it."""
    var input: Input
    """Keyboard, mouse and gamepad state. The run loop folds each frame's events into
    it before `update`, so it is settled for the whole frame. Read it, don't
    write it: the loop carries it into the next frame."""
    var _autoscale: AutoScale
    var _autoclear: Bool
    var _letterbox_color: Color
    var _quit_on_escape: Bool
    var _design_w: Int
    var _design_h: Int
    var _frame_count: Int
    var _max_frame_rate: Int
    var _quit: Bool
    # This frame's `rumble` calls, sent by the windowed loops after `update`
    # and dropped at the next frame's start either way.
    var _rumbles: List[_Rumble]

    def __init__(out self):
        self.time = Time()
        self.input = Input()
        self._autoscale = AutoScale.FIT
        self._autoclear = True
        self._letterbox_color = Color.BLACK
        self._quit_on_escape = True
        self._design_w = 0
        self._design_h = 0
        self._frame_count = 0
        self._max_frame_rate = 0
        self._quit = False
        self._rumbles = []

    def design_size(self) -> Tuple[Int, Int]:
        """The width and height the program is authored in: the size passed
        to `run` unless set."""
        return (self._design_w, self._design_h)

    def design_size(mut self, width: Int, height: Int):
        """Author this program in a fixed world size, scaled to any window.

        Overrides the size passed to `run`, so a program can pin its own
        coordinate space no matter how it is launched — including fullscreen,
        where the window size is the display's rather than the caller's.

        Takes effect on the next frame, like every dial here: the frame being
        rendered keeps the mapping it was built with, since one frame cannot
        record under two of them. From `create` there is no frame yet, so it
        applies to frame one.
        """
        self._design_w = width
        self._design_h = height

    def autoscale(self) -> AutoScale:
        """How the design size maps onto the window. `FIT` unless set."""
        return self._autoscale

    def autoscale(mut self, mode: AutoScale):
        """Choose how the design size maps onto the window — see
        `AutoScale`."""
        self._autoscale = mode

    def autoclear(self) -> Bool:
        """Whether each frame opens with a clear. `True` unless set."""
        return self._autoclear

    def autoclear(mut self, enabled: Bool):
        """Switch the clear each frame opens with off or back on.

        On by default, clearing to gray 200 so the default style is visible
        on a program that never calls `canvas.background()`. Off lets ink
        accumulate across frames.
        """
        self._autoclear = enabled

    def letterbox_color(self) -> Color:
        """The colour of the bars under `AutoScale.FIT`. Black unless set."""
        return self._letterbox_color

    def letterbox_color(mut self, color: Color):
        """Colour the bars outside the design area under `AutoScale.FIT`.

        Black by default.
        """
        self._letterbox_color = color

    def quit_on_escape(self) -> Bool:
        """Whether Escape stops the run loop. `True` unless set."""
        return self._quit_on_escape

    def quit_on_escape(mut self, enabled: Bool):
        """Whether Escape stops the run loop. On by default."""
        self._quit_on_escape = enabled

    def frame_count(self) -> Int:
        """Frames rendered so far. 1 during the first `update`."""
        return self._frame_count

    def frame_rate(self) -> Float64:
        """Current frames per second, derived from the last frame's delta.

        `0.0` on the first frame, where `delta` is still `0.0` and there is
        no prior frame to measure against.
        """
        if self.time.delta == 0.0:
            return 0.0
        return 1.0 / self.time.delta

    def max_frame_rate(self) -> Int:
        """The frame-rate cap. `0` unless set, meaning uncapped."""
        return self._max_frame_rate

    def max_frame_rate(mut self, fps: Int) raises:
        """Limit the loop to at most `fps` frames per second.

        A cap tighter than the display's own pacing (vsync, or the CPU
        backend's always-on vsync) slows the loop by sleeping at the end of
        each frame; a cap looser than it does nothing, since presentation is
        already waiting on the display. Not enforced by `run_headless`,
        which has no wall clock to cap against.
        """
        if fps <= 0:
            raise Error(
                "max_frame_rate fps must be positive, got " + String(fps)
            )
        self._max_frame_rate = fps

    def _set_viewport(
        self, mut state: PersistentCanvasState, pixel_w: Int, pixel_h: Int
    ):
        """Remap `state` onto a framebuffer of this size under the design
        size and autoscale dials, at the top of a frame."""
        state._set_viewport(
            self._autoscale, self._design_w, self._design_h, pixel_w, pixel_h
        )

    def _new_canvas(self, var state: PersistentCanvasState) -> Canvas:
        """Build this frame's `Canvas` under the dials as they stand now."""
        return Canvas(
            state^,
            autoclear=self._autoclear,
            letterbox_color=self._letterbox_color,
        )

    def _advance_frame(mut self, now: Int):
        """Tick the clock and count the frame, before each `update`.

        Also drops last frame's rumbles: the windowed loops sent them already,
        and the headless one has nowhere to send them.
        """
        self._rumbles.clear()
        self.time._tick(now)
        self._frame_count += 1

    def quit(mut self):
        """Ask the run loop to stop after the current frame.

        Unwinds normally, so the window tears down cleanly and program
        destructors run — unlike `std.sys.exit`, which aborts the process.
        """
        self._quit = True

    def rumble(
        mut self,
        seconds: Float64,
        low_frequency: Float64 = 1.0,
        high_frequency: Float64 = 1.0,
        player: Int = 0,
    ):
        """Shake player `player`'s gamepad for `seconds`.

        Most pads have two motors: `low_frequency` is the heavy one, a thud
        or an engine, and `high_frequency` the light buzz; each is 0 (off) to
        1 (full). Both at full by default, so `context.rumble(0.2)` is a
        short jolt. A new rumble replaces the one running, so
        `context.rumble(0, 0, 0)` stops it early. Sent after `update`
        returns, like `quit`; a pad without motors, an empty slot and a
        headless run ignore it.
        """
        var pad = self.input.gamepad(player)
        if pad.connected:
            self._rumbles.append(
                _Rumble(pad._id, low_frequency, high_frequency, seconds)
            )
