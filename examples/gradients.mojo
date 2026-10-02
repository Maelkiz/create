"""Gradients: a sky behind everything, and a fill on every kind of shape.

    pixi run example gradients        # CPU
    pixi run example gradients gpu    # the same scene through the GPU backend

The background spans the whole window (`EXTEND`), so resize it to watch the
sky stretch. A gradient spans each shape's own box, so the card's turns with
it.

`run_gl` is internal while the GPU backend is being built, so this example
names it by path rather than through the preamble.
"""

from std.math import pi
from std.sys import argv

from create import *
from create.core._run_gl import run_gl


@fieldwise_init
struct App(Program):
    var sky: Gradient
    var card: Style
    var angle: Float64

    @staticmethod
    def create(mut context: Context) raises -> App:
        context.autoscale(AutoScale.EXTEND)
        # Built once: a gradient keeps its stops and ramp for as long as it
        # lives, so the GPU uploads it once.
        var sky = Gradient.linear(
            [
                (0.0, Color.hex(0x0B1D3A)),
                (0.55, Color.hex(0x5B3A7A)),
                (1.0, Color.hex(0xF4A261)),
            ]
        )
        # A style can carry a gradient like any colour.
        var card = Style(
            fill_gradient=Gradient.linear(
                Color.hex(0xFFE29A), Color.hex(0xFF7A59)
            ),
            outline_enabled=False,
            corner_radius=18,
            shadow=Color(0, 0, 0, 90),
            shadow_offset=Vector2D(0, -10),
            shadow_blur=16,
        )
        return App(sky, card, 0.0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(self.sky)
        self.angle += 0.5 * context.time.delta

        canvas.outline(Color.WHITE, thickness=2)
        # Left to right.
        canvas.fill(
            Gradient.linear(
                Color.hex(0x2EC4B6),
                Color.hex(0x3A86FF),
                direction=Vector2D.RIGHT,
            )
        )
        canvas.rectangle((-450, 120), 160, 110)
        # Lit from the top left: a radial off the box's centre.
        canvas.fill(
            Gradient.radial(
                Color.WHITE,
                Color.hex(0x3A86FF),
                Color.hex(0x10204A),
                center=(-0.35, 0.35),
            )
        )
        canvas.circle((-220, 120), 65)
        # Corner to corner, with no trigonometry.
        canvas.fill(
            Gradient.linear(
                Color.hex(0xFFBE0B),
                Color.hex(0xFB5607),
                direction=Vector2D(1, 1),
            )
        )
        canvas.triangle((-60, 55), (60, 55), (0, 185))
        # A sector spans its whole circle, so the slice shows part of it.
        canvas.fill(
            Gradient.linear(
                Color.hex(0x8338EC),
                Color.hex(0xFF006E),
                direction=Vector2D.RIGHT,
            )
        )
        canvas.sector((220, 120), 65.0, 0.5, 1.6 * pi)
        canvas.fill(Gradient.linear(Color.hex(0xFFD166), Color.hex(0xEF476F)))
        canvas.polygon(Polygon.star((450, 120), 70.0, 30.0, 5))

        # The card turns, and its gradient turns with it.
        with canvas.style(self.card):
            with canvas.transform(translate(-250, -140) @ rotate(self.angle)):
                canvas.rectangle((0, 0), 220, 130)

        # A fade to transparent: a glow over whatever is behind it.
        with canvas.style(fill=Color.hex(0x3A86FF), outline_enabled=False):
            canvas.circle((150, -140), 45)
        with canvas.style(
            fill_gradient=Gradient.radial(
                Color(255, 255, 255, 220), Color.WHITE.with_alpha(0)
            ),
            outline_enabled=False,
        ):
            canvas.circle((150, -140), 120)

        with canvas.style(text_color=Color.WHITE, font_size=18):
            canvas.text("linear", (-450, 30))
            canvas.text("radial", (-220, 30))
            canvas.text("diagonal", (0, 30))
            canvas.text("sector", (220, 30))
            canvas.text("polygon", (450, 30))
            canvas.text("turns with the shape", (-250, -250))
            canvas.text("fades to transparent", (150, -250))


def main() raises:
    var gpu = False
    for i in range(1, len(argv())):
        if argv()[i] == "gpu":
            gpu = True
    if gpu:
        run_gl[App]("Gradients (GPU)", width=1280, height=720)
    else:
        run[App]("Gradients", width=1280, height=720)
