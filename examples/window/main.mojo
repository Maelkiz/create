"""The program and its window: how the 800x600 design maps onto a window of
any size, and the window's own settings.

Resize the window in each autoscale mode:

    FIT     the whole scene scales, with bars (in `letterbox_color`) where
            the window's shape differs from the design's
    EXTEND  same scale, no bars: the leftover becomes extra world, so the
            ball turns at the new window edge
    OFF     no scaling at all: the world is the window in pixels, so the
            scene stays put while the space around it grows

Space cycles the modes, F11 toggles fullscreen, R lets the window be resized
or not, F cycles the frame-rate cap.
"""

from create import *

comptime _BACKGROUND = Color(40, 40, 44)
comptime _BARS = Color(56, 58, 92)
"""Not black, so the bars FIT leaves are plain to see."""
comptime _BALL = Color(226, 46, 56)
comptime _BOX = Color(98, 104, 168)
comptime _TEXT = Color(240, 236, 222)
comptime _HINT = Color(176, 172, 162)


def _frame_caps() -> List[Int]:
    """The caps F cycles through; 0 is uncapped."""
    return [0, 60, 30, 10]


@fieldwise_init
struct App(Program):
    var x: Float64
    var dir: Float64
    var cap: Int
    """Which of `_frame_caps()` is set."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # A canvas setting that outlives the frame: set once, kept.
        canvas.letterbox_color(_BARS)
        return App(x=100.0, dir=1.0, cap=0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        ref input = context.input
        if input.key_pressed(Key.F11):
            if context.window_mode() == WindowMode.FULLSCREEN:
                context.window_mode(WindowMode.WINDOWED)
            else:
                context.window_mode(WindowMode.FULLSCREEN)
        if input.key_pressed(Key.SPACE):
            var mode = context.autoscale()
            if mode == Autoscale.FIT:
                context.autoscale(Autoscale.EXTEND)
            elif mode == Autoscale.EXTEND:
                context.autoscale(Autoscale.OFF)
            else:
                context.autoscale(Autoscale.FIT)
        if input.key_pressed(Key.R):
            context.resizable(not context.resizable())
        if input.key_pressed(Key.F):
            self.cap = (self.cap + 1) % len(_frame_caps())
            context.max_frame_rate(_frame_caps()[self.cap])

        self.x += self.dir * 200.0 * context.time.delta
        # Set the sign rather than flip it: under EXTEND/OFF a shrinking
        # window can move canvas.right()/left() past the ball between frames,
        # and a flip on an already-true condition alternates forever instead
        # of turning the ball back inward.
        if self.x > canvas.right() - 40.0:
            self.dir = -1.0
        elif self.x < canvas.left() + 40.0:
            self.dir = 1.0

        canvas.background(_BACKGROUND)
        with canvas.style(outline_enabled=False):
            canvas.fill(_BALL)
            canvas.circle((self.x, 150), 40)
            canvas.fill(_BOX)
            canvas.rectangle((0, 40), 200, 120, corner_radius=12)

        # The origin is the middle of the design area and y grows upward, so
        # the lines below centre sit at negative y.
        var cap = context.max_frame_rate()
        var lines: List[String] = [
            String(context.autoscale(), "   Scale ", round(canvas.scale(), 2)),
            String(
                "World ",
                Int(canvas.width()),
                " x ",
                Int(canvas.height()),
                "   Resizable ",
                context.resizable(),
            ),
            String(
                "Frame rate ",
                Int(context.frame_rate() + 0.5),
                "   Cap ",
                String(cap) if cap > 0 else "none",
            ),
        ]
        with canvas.style(text_color=_TEXT, font_size=24):
            for i in range(len(lines)):
                canvas.text(lines[i], (0, -70 - 40 * i))
        with canvas.style(text_color=_HINT, font_size=18):
            canvas.text(
                (
                    "Space: autoscale   F11: fullscreen   R: resizable   F:"
                    " frame-rate cap"
                ),
                (0, -210),
            )


def main() raises:
    run[App]("Window", width=800, height=600)
