from create.math.matrix import Matrix
from create.render.autoscale import AutoScale
from .time import Time
from create.render.viewport import Viewport


struct Context(Movable):
    """Per-frame state the run loop hands the program, and the dials it can
    turn back.

    `width`/`height` are the screen extent and `left`/`right`/`bottom`/`top`
    its edges — use those rather than width arithmetic, since the origin is
    centred and two of them are negative. `time` is the frame clock, `scale`
    the autoscale factor, `view` the mapping they all come from. Screen space
    is camera-independent — `Context` and `Input` don't know a `Camera`
    exists, since a program sets one on `Canvas`, not on either of these.

    Written from both sides, which is why it is a `mut` parameter: the loop
    refreshes the geometry and the clock each frame, and the program sets
    `autoscale`, `quit_on_escape`, or calls `design` and `quit`.
    """

    var time: Time
    var width: Int
    var height: Int
    var quit_on_escape: Bool
    var autoscale: Int
    var scale: Float64
    var view: Viewport
    var _quit: Bool
    var _fps_cap: Int

    def __init__(out self):
        self.time = Time()
        self.width = 0
        self.height = 0
        self.quit_on_escape = True
        self.autoscale = AutoScale.OFF
        self.scale = 1.0
        self.view = Viewport()
        self._quit = False
        self._fps_cap = 0

    def design(mut self, width: Int, height: Int, mode: Int = AutoScale.FIT):
        """Author this program in a fixed world size, scaled to any window.

        Overrides the size passed to `run`, so a program can pin its own
        coordinate space no matter how it is launched — including fullscreen,
        where the window size is the display's rather than the caller's. The
        mapping is recomputed here rather than on the next frame, so `width`,
        `height` and the edge helpers are correct for the rest of `create`.
        """
        self.view.set_design(width, height)
        self.autoscale = mode
        self._set_viewport(self.view.pixel_w, self.view.pixel_h)

    def _set_viewport(mut self, pixel_w: Int, pixel_h: Int):
        """Remap onto a framebuffer of this size and republish the result.

        `autoscale` is a public field a program may have written since the last
        frame, so it is pushed into the viewport before remapping; the reported
        size and scale are mirrored back out after.
        """
        self.view.autoscale = self.autoscale
        self.view.set_size(pixel_w, pixel_h)
        self.width = self.view.width
        self.height = self.view.height
        self.scale = self.view.scale

    def left(self) -> Float64:
        """Screen x of the left edge — negative, since the origin is centred."""
        return self.view.left()

    def right(self) -> Float64:
        return self.view.right()

    def bottom(self) -> Float64:
        """Screen y of the bottom edge — negative, since y grows upward."""
        return self.view.bottom()

    def top(self) -> Float64:
        return self.view.top()

    def _base_matrix(self) -> Matrix[3, 3]:
        """The screen-to-pixel mapping: origin centred, y up."""
        return self.view.base_matrix()

    def to_screen(self, x: Float64, y: Float64) -> Tuple[Float64, Float64]:
        """Map a window pixel position into screen space."""
        return self.view.to_screen(x, y)

    def framerate(self) -> Float64:
        """Current frames per second, derived from the last frame's delta.

        `0.0` on the first frame, where `delta` is still `0.0` and there is
        no prior frame to measure against.
        """
        if self.time.delta == 0.0:
            return 0.0
        return 1.0 / self.time.delta

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
