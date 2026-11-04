from create import *

comptime _ROW_SPACING = 70.0
comptime _TOP_ROW = 250.0
comptime _TRACK_START = -360.0
comptime _TRACK_END = 580.0


def _curves() -> List[Easing]:
    # LINEAR first so every other row reads as a departure from it.
    return [
        Easing.LINEAR,
        Easing.IN_OUT_QUAD,
        Easing.OUT_CUBIC,
        Easing.IN_OUT_CUBIC,
        Easing.OUT_SINE,
        Easing.OUT_EXPO,
        Easing.OUT_BACK,
        Easing.OUT_ELASTIC,
        Easing.OUT_BOUNCE,
    ]


@fieldwise_init
struct App(Program):
    var clock: Tween
    """The hovered row's playhead. The rows differ only in which curve they
    bend `clock.progress` with, so one tween serves whichever is hovered:
    `ease` needs no state of its own."""

    var curves: List[Easing]
    var hovered: Int
    """The row under the mouse, or -1 for none."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        return App(clock=Tween(1.6), curves=_curves(), hovered=-1)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var hovered = -1
        for i in range(len(self.curves)):
            if abs(context.input.mouse.y - _row_y(i)) < _ROW_SPACING / 2.0:
                hovered = i
        if hovered != self.hovered:
            # ping_pong rather than loop: progress runs back down on the
            # return leg, so the dot travels its curve backwards instead of
            # snapping to the start.
            self.hovered = hovered
            self.clock.ping_pong()
        # Nothing else advances a tween. A tween never updated sits at its
        # start forever, exactly like an un-ticked Animator.
        self.clock.update(context.time.delta)

        canvas.background(Color(18, 18, 24))

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Easing and Tweens", (0, 362))
        canvas.font_size(18)
        canvas.text_color(Color(140, 140, 155))
        canvas.text("hover over a curve to play it", (0, 318))

        canvas.text_align(Align.LEFT)
        for i in range(len(self.curves)):
            var y = _row_y(i)
            var active = i == self.hovered
            canvas.outline(
                Color(70, 70, 92) if active else Color(44, 44, 58), thickness=3
            )
            canvas.line((_TRACK_START, y), (_TRACK_END, y))

            # A resting row sits at the start of its track. OUT_BACK and
            # OUT_ELASTIC leave 0..1 mid-run, so the hovered dot visibly
            # overshoots the ends of its track.
            var t = 0.0
            if active:
                t = ease(self.curves[i], self.clock.progress())
            with canvas.style(fill=Color(90, 170, 255), outline_enabled=False):
                canvas.circle((lerp(_TRACK_START, _TRACK_END, t), y), 11)

            canvas.text_color(
                Color(235, 120, 70) if active else Color(140, 140, 155)
            )
            canvas.text(String(self.curves[i]), (-614.0, y))


def _row_y(i: Int) -> Float64:
    return _TOP_ROW - Float64(i) * _ROW_SPACING


def main() raises:
    run[App]("Easing and Tweens", width=1280, height=800)
