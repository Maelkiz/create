"""Shadows: drop, inset, on text, on turning shapes and on an image.

    pixi run example shadows        # CPU
    pixi run example shadows gpu    # the same scene through the GPU backend

Space toggles every shadow between soft and hard.

`run_gl` is internal while the GPU backend is being built, so this example
names it by path rather than through the preamble.
"""

from std.sys import argv

from create import *
from create.core._run_gl import run_gl


@fieldwise_init
struct App(Program):
    var logo: Image
    var angle: Float64
    var soft: Bool

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        return App(
            Image.load(source_path("../assets/logo/png/logo-cutout.png")),
            0.9,
            True,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(0xE4, 0xE6, 0xEB))
        if context.input.key_pressed("space"):
            self.soft = not self.soft
        self.angle += 0.6 * context.time.delta
        # One blur for the whole scene; spreads and offsets stay as set.
        var blur = 16.0 if self.soft else 0.0

        # A heading whose glyphs cast their own shadow.
        with canvas.style(
            text_color=Color(0x30, 0x40, 0x60),
            font_size=56,
            font_weight=FontWeight.BOLD,
            shadow=Color(0x30, 0x40, 0x60, 90),
            shadow_offset=Vector2D(3, -3),
            shadow_blur=blur / 4.0,
        ):
            canvas.text("Shadows", (0, canvas.top() - 70))

        # A card lifted off the page: soft, offset down, a rounded silhouette.
        with canvas.style(
            fill=Color.WHITE,
            outline_enabled=False,
            corner_radius=18,
            shadow=Color(0x20, 0x30, 0x50, 70),
            shadow_offset=Vector2D(0, -10),
            shadow_blur=blur * 1.5,
        ):
            canvas.rectangle((-330, 60), 380, 220)
        with canvas.style(text_color=Color(0x30, 0x40, 0x60), font_size=26):
            canvas.text("A card", (-330, 110))
        with canvas.style(text_color=Color(0x70, 0x78, 0x88), font_size=18):
            canvas.text("a drop shadow, offset straight down", (-330, 60))

        # A text field pressed into the page: the inset shadow darkens the
        # top-left inner edges, as if lit from above.
        with canvas.style(
            fill=Color(0xF6, 0xF7, 0xF9),
            outline=Color(0xB8, 0xBE, 0xC8),
            corner_radius=10,
            shadow=Color(0x20, 0x30, 0x50, 90),
            shadow_offset=Vector2D(3, -4),
            shadow_blur=blur / 2.0,
            shadow_inset=True,
        ):
            canvas.rectangle((-330, -170), 380, 60)
        with canvas.style(
            text_color=Color(0x98, 0xA0, 0xAC),
            font_size=20,
            text_align=Align.LEFT,
        ):
            canvas.text("Type here…", (-500, -170))

        # The same turning square twice. On the left the shadow is fixed to
        # the screen, as under a light overhead; on the right it turns with
        # the square.
        canvas.shadow(Color(0, 0, 0, 80), offset=Vector2D(14, -14), blur=blur)
        with canvas.style(
            fill=Color(0xF0, 0x90, 0x50),
            outline_enabled=False,
            corner_radius=14,
        ):
            with canvas.transform(translate(170, 110) @ rotate(self.angle)):
                canvas.rectangle((0, 0), 120, 120)
            with canvas.style(shadow_follows_transform=True):
                with canvas.transform(translate(430, 110) @ rotate(self.angle)):
                    canvas.rectangle((0, 0), 120, 120)

        # An image casts its alpha, not its box. Images move with a
        # transform but are never turned by one, so this one stands still.
        canvas.image(self.logo, (300, -170), 150, 150)
        canvas.shadow_enabled(False)

        with canvas.style(text_color=Color(0x50, 0x58, 0x68), font_size=18):
            canvas.text("fixed to the screen", (170, -20))
            canvas.text("follows the transform", (430, -20))
            canvas.text("an image's alpha", (300, -265))

        with canvas.style(text_color=Color(0x70, 0x78, 0x88), font_size=18):
            canvas.text(
                "space: " + ("soft" if self.soft else "hard") + " shadows",
                (0, canvas.bottom() + 40),
            )


def main() raises:
    var gpu = False
    for i in range(1, len(argv())):
        if argv()[i] == "gpu":
            gpu = True
    if gpu:
        run_gl[App]("Shadows (GPU)", width=1280, height=720)
    else:
        run[App]("Shadows", width=1280, height=720)
