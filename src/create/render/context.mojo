from .autoscale import AutoScale
from .color import Color


struct Context(Copyable, Movable):
    """The dials that outlive a frame: what the program sets, the loop reads.

    A `Canvas` is built and dropped inside one frame, so a setting that has to
    survive the frame boundary cannot live on it. These do — the autoscale
    mode and design resolution the next frame's mapping is derived from, the
    clear the next frame opens with, the letterbox colour, and the two the run
    loop reads after a frame has been released, `frame_cap` and `quit`.

    Handed to `Program.create` on its own, before any frame exists, and
    alongside the frame to `Program.update`. That is the whole reason it is a
    separate object rather than fields on `Canvas`: `create` has dials to turn
    and nothing to render on, so it is given exactly that — a program cannot
    record a command that will never be presented, and there is no discarded
    frame to explain.

    **Read at frame construction.** `Canvas` takes its copy of `autoclear`,
    `clear_color` and `letterbox` when it is built, and the loop re-derives
    the viewport from `autoscale` and the design size at the top of each
    frame. So a dial turned part-way through `update` applies to the *next*
    frame, uniformly — the clear of the frame being rendered was recorded before
    `update` was called, and one frame cannot record under two mappings. Set
    them in `create` to have them hold from frame one. `frame_cap` and `quit`
    are the exception, and only because the loop reads them after the frame
    body returns.
    """

    var autoscale: AutoScale
    """How the design resolution maps onto the window — see `AutoScale`."""
    var autoclear: Bool
    """Whether each frame opens with a clear to `clear_color`."""
    var clear_color: Color
    """What `autoclear` clears to, every frame. `canvas.background()` is the
    per-frame version: it paints at the point it is called and leaves this
    alone."""
    var letterbox: Color
    """The bars outside the design area under `AutoScale.FIT`."""
    var quit_on_escape: Bool
    var _design_w: Int
    var _design_h: Int
    var _fps_cap: Int
    var _quit: Bool

    def __init__(out self):
        self.autoscale = AutoScale.OFF
        self.autoclear = True
        self.clear_color = Color(200)
        self.letterbox = Color(0x22)
        self.quit_on_escape = True
        self._design_w = 0
        self._design_h = 0
        self._fps_cap = 0
        self._quit = False

    def design_resolution(
        mut self, width: Int, height: Int, mode: AutoScale = AutoScale.FIT
    ):
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
        self.autoscale = mode

    def frame_cap(mut self, fps: Int) raises:
        """Limit the loop to at most `fps` frames per second.

        A cap tighter than the display's own pacing (vsync, or the CPU
        backend's always-on vsync) slows the loop by sleeping at the end of
        each frame; a cap looser than it does nothing, since presentation is
        already waiting on the display. Not enforced by `run_headless`,
        which has no wall clock to cap against.
        """
        if fps <= 0:
            raise Error("frame_cap fps must be positive, got " + String(fps))
        self._fps_cap = fps

    def quit(mut self):
        """Ask the run loop to stop after the current frame.

        Unwinds normally, so the window tears down cleanly and program
        destructors run — unlike `std.sys.exit`, which aborts the process.
        """
        self._quit = True
