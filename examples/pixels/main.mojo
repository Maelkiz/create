"""Reading back what is drawn: each frame is drawn over a slightly larger,
fainter copy of the last one, so the circles leave trails that drift
outwards, and the swatch at the bottom shows the colour under the
mouse.
"""

from create import *


@fieldwise_init
struct Pixels(Program):
    var last: Optional[Image]

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Pixels:
        return Pixels(None)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(40, 40, 44))
        if self.last:
            # The last frame, 1% larger, faded by a translucent background:
            # a trail that drifts outwards.
            canvas.image(
                self.last.value(),
                (0, 0),
                canvas.width() * 1.01,
                canvas.height() * 1.01,
            )
            canvas.background(Color(40, 40, 44, 30))

        var t = context.time.elapsed
        canvas.outline_enabled(False)
        var colors: List[Color] = [
            Color(226, 46, 56),
            Color(201, 140, 150),
            Color(98, 104, 168),
        ]
        for i in range(3):
            var angle = t * (0.7 + 0.3 * Float64(i)) + Float64(i) * 2.1
            canvas.fill(colors[i])
            canvas.circle((cos(angle) * 180, sin(angle * 1.3) * 120), 18)

        # Kept before the swatch, so the trail never shows it.
        self.last = canvas.snapshot()

        var under = canvas.color_at(context.input.mouse)
        canvas.fill(under)
        canvas.outline(Color(240, 236, 222))
        canvas.rectangle((0, canvas.bottom() + 40), 60, 40)
        canvas.text_color(Color(240, 236, 222))
        canvas.text(String(under), (0, canvas.bottom() + 80))


def main() raises:
    run[Pixels]("Pixels", width=800, height=600)
