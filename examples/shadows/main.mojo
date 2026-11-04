"""Shadows: drop, inset, on text, on turning shapes and on an image.

    pixi run example shadows        # CPU
    pixi run example shadows gpu    # the same scene through the GPU backend

Space toggles every shadow between soft and hard.
"""

from create import *


@fieldwise_init
struct App(Program):
    var logo: Image
    var angle: Float64
    var soft: Bool

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        return App(
            Image.load(source_path("../../assets/logo/png/logo-cutout.png")),
            0.9,
            True,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(240, 236, 222))
        if context.input.key_pressed(Key.SPACE):
            self.soft = not self.soft
        self.angle += 0.6 * context.time.delta
        # One blur for the whole scene; spreads and offsets stay as set.
        var blur = 16.0 if self.soft else 0.0

        # A heading whose glyphs cast their own shadow.
        with canvas.style(
            text_color=Color(40, 40, 44),
            font_size=56,
            font_weight=FontWeight.BOLD,
            shadow=Color(40, 40, 44, 90),
            shadow_offset=Vector2D(3, -3),
            shadow_blur=blur / 4.0,
        ):
            canvas.text("Shadows", (0, canvas.top() - 70))

        # A card lifted off the page: soft, offset down, a rounded silhouette.
        with canvas.style(
            fill=Color.WHITE,
            outline_enabled=False,
            shadow=Color(40, 40, 44, 70),
            shadow_offset=Vector2D(0, -10),
            shadow_blur=blur * 1.5,
        ):
            canvas.rectangle((-330, 60), 380, 220, corner_radius=18)
        with canvas.style(text_color=Color(40, 40, 44), font_size=26):
            canvas.text("A card", (-330, 110))
        with canvas.style(text_color=Color(110, 108, 104), font_size=18):
            canvas.text("A drop shadow, offset straight down", (-330, 60))

        # A text field pressed into the page: the inset shadow darkens the
        # top-left inner edges, as if lit from above.
        with canvas.style(
            fill=Color(250, 248, 242),
            outline=Color(200, 196, 186),
            shadow=Color(40, 40, 44, 90),
            shadow_offset=Vector2D(3, -4),
            shadow_blur=blur / 2.0,
            shadow_inset=True,
        ):
            canvas.rectangle((-330, -170), 380, 60, corner_radius=10)
        with canvas.style(
            text_color=Color(150, 146, 138),
            font_size=20,
            font_italic=True,
            text_align=Align.LEFT,
        ):
            canvas.text("Type here…", (-500, -170))

        # The same turning square twice. On the left the shadow is fixed to
        # the screen, as under a light overhead; on the right it turns with
        # the square.
        canvas.shadow(Color(0, 0, 0, 80), offset=Vector2D(14, -14), blur=blur)
        var square = Rectangle((0, 0), 120, 120, corner_radius=14)
        with canvas.style(fill=Color(98, 104, 168), outline_enabled=False):
            with canvas.transform(translate(170, 110) @ rotate(self.angle)):
                canvas.draw(square)
            with canvas.style(shadow_follows_transform=True):
                with canvas.transform(translate(430, 110) @ rotate(self.angle)):
                    canvas.draw(square)

        # An image casts its alpha, not its box.
        canvas.image(self.logo, (300, -170), 150, 150)
        canvas.shadow_enabled(False)

        with canvas.style(text_color=Color(80, 78, 74), font_size=18):
            canvas.text("Fixed to the screen", (170, -20))
            canvas.text("Follows the transform", (430, -20))
            canvas.text("An image's alpha", (300, -265))

        with canvas.style(text_color=Color(110, 108, 104), font_size=18):
            canvas.text(
                "Space: " + ("soft" if self.soft else "hard") + " shadows",
                (0, canvas.bottom() + 40),
            )


def main() raises:
    run[App](
        "Shadows",
        width=1280,
        height=720,
        backend=RenderBackend.from_arguments(),
    )
