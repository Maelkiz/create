"""One scene to run on each backend, CPU and GPU, made of the cases they
could disagree about.

    pixi run example backends                 # CPU
    pixi run example backends gpu             # the same scene through the GPU
    pixi run example backends gpu fullscreen  # letterboxed on a wide display

The two frames should be indistinguishable apart from the GPU's
multisampled edges. Everything on screen is deliberately such a case — the
five solid command kinds, a translucent fill under an outline, an
outline wider than its shape, a rotated rect, a diagonal line, and in
fullscreen a letterbox bar under `FIT`: the 4:3 design keeps its size, so
on a 16:9 display the bars are on screen from the first frame. A cycles
the antialiasing level, to compare the edges at each. Escape quits.
"""

from std.sys import argv

from create import *


@fieldwise_init
struct App(Program):
    var angle: Float64
    var logo: Image
    var fps: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # Twice, below, from one interned image and so one GL upload.
        var logo = Image.load(source_path("../../assets/logo/png/logo.png"))
        return App(0.0, logo^, 0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.angle += context.time.delta
        self.fps = Int(context.frame_rate())
        if context.input.key_pressed(Key.A):
            # The level is the canvas's: it lasts until changed, and covers
            # this whole frame.
            canvas.antialiasing(
                Antialiasing((canvas.antialiasing().value + 1) % 4)
            )

        canvas.background(Color(40, 40, 44))

        # A plain filled rect and an outlined one, side by side.
        with canvas.style(fill=Color(98, 104, 168), outline_enabled=False):
            canvas.rectangle((-260, 180), 160, 100)

        with canvas.style(
            fill=Color(201, 140, 150),
            outline=Color.BLACK,
            outline_thickness=6,
        ):
            canvas.rectangle((-60, 180), 160, 100)

        # An outline wider than the shape: all outline, no interior.
        with canvas.style(
            fill=Color(226, 46, 56),
            outline=Color(240, 236, 222),
            outline_thickness=30,
        ):
            canvas.rectangle((160, 180), 40, 40)

        # Translucent over the indigo rect — the case a double-blended fill
        # under its own outline would get visibly wrong.
        with canvas.style(
            fill=Color(201, 140, 150, 0x80),
            outline=Color(240, 236, 222, 0x80),
            outline_thickness=8,
        ):
            canvas.circle((-260, 180), 70)

        with canvas.style(fill=Color(226, 46, 56), outline_enabled=False):
            canvas.circle((0, 0), 90)

        with canvas.style(
            fill=Color(30, 30, 33),
            outline=Color(201, 140, 150),
            outline_thickness=10,
        ):
            canvas.circle((220, 0), 80)

        # A rotating rect: the transform is baked per vertex, so a rotated
        # outline ring has to follow the shape rather than stay axis-aligned.
        with canvas.transform(translate(-230, 0) @ rotate(self.angle)):
            with canvas.style(
                fill=Color(240, 236, 222),
                outline=Color.BLACK,
                outline_thickness=4,
            ):
                canvas.rectangle((0, 0), 120, 120)

        with canvas.style(outline=Color(150, 154, 206), outline_thickness=5):
            canvas.line((-340, -140), (340, -260))

        with canvas.style(
            fill=Color(150, 154, 206),
            outline=Color(240, 236, 222),
            outline_thickness=3,
        ):
            canvas.triangle((-140, -180), (40, -180), (-50, -30))

        # The same image at two sizes: one texture, one upload, and — since
        # the two renders are adjacent — one extra batch for the pair.
        # Text before the images: solids and glyphs share the atlas binding
        # and so share one batch, which the image texture then breaks.
        with canvas.style(
            text_color=Color(240, 236, 222),
            font_size=28,
            text_align=Align.CENTER,
        ):
            canvas.text("Centre / middle", (0, 0))

        with canvas.style(
            text_color=Color(201, 140, 150),
            font_size=20,
            text_align=Align.TOP_LEFT,
        ):
            canvas.text("Left / top", (canvas.left() + 12, canvas.top() - 12))

        with canvas.style(
            text_color=Color(240, 236, 222, 0xA0),
            font_size=20,
            text_align=Align.BOTTOM_RIGHT,
        ):
            canvas.text(
                "Right / bottom — translucent",
                (canvas.right() - 12, canvas.bottom() + 12),
            )

        canvas.image(self.logo, (250, -170), 140, 140)
        canvas.image(self.logo, (90, -230), 70, 70)

        with canvas.style(
            text_color=Color(240, 236, 222),
            font_size=20,
            text_align=Align.TOP_RIGHT,
        ):
            canvas.text(
                "FPS: " + String(self.fps),
                (canvas.right() - 12, canvas.top() - 12),
            )
            canvas.text(
                String(canvas.antialiasing()) + " (A to cycle)",
                (canvas.right() - 12, canvas.top() - 40),
            )


def main() raises:
    var mode = WindowMode.WINDOWED
    for i in range(1, len(argv())):
        if argv()[i] == "fullscreen":
            mode = WindowMode.FULLSCREEN
    run[App](
        "Backends",
        mode,
        width=800,
        height=600,
        backend=RenderBackend.from_arguments(),
    )
