from std.math import pi, tau

from create import *

comptime _BACKGROUND = Color(40, 42, 56)

comptime _RING_RADIUS = 140.0
comptime _RING_THICKNESS = 18


@fieldwise_init
struct App(Program):
    var progress: Tween
    """Walks both rings from empty to full."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        var progress = Tween(3.0, Easing.IN_OUT_CUBIC)
        progress.loop()
        return App(progress=progress)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.progress.update(context.time.delta)

        canvas.background(_BACKGROUND)
        canvas.fill_enabled(False)

        # Two progress rings off one tween. Angles count counter-clockwise
        # from +x because y is up, so the clockwise ring (blue, like a
        # clock's hand) starts at the top and sweeps negatively.
        var sweep = tau * self.progress.value
        var clockwise = Point2D(-200.0, -20.0)
        var counter = Point2D(200.0, -20.0)
        canvas.outline(Color(62, 64, 82), thickness=_RING_THICKNESS)
        canvas.arc(clockwise, _RING_RADIUS, 0.0, tau)
        canvas.arc(counter, _RING_RADIUS, 0.0, tau)
        canvas.outline(Color(90, 170, 255))
        canvas.arc(clockwise, _RING_RADIUS, pi / 2.0, -sweep)
        canvas.outline(Color(235, 120, 70))
        canvas.arc(counter, _RING_RADIUS, pi / 2.0, sweep)

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Arcs", (0, 362))
        canvas.font_size(18)
        canvas.text(
            "one tween, swept clockwise and counter-clockwise from the top",
            (0, 322),
        )


def main() raises:
    run[App]("Arcs", width=1280, height=800)
