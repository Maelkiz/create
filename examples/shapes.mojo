"""The five solid command kinds, rendered on the GPU backend.

The visual comparison target for the CPU path: run this, then drop the
`backend=RenderBackend.GPU` argument, and the two frames should be indistinguishable
apart from the GPU's multisampled edges. Everything on screen is deliberately
a case the two backends could disagree about — a translucent fill under an
outline, an outline wider than its shape, a rotated rect, a diagonal line, a
letterbox bar under `FIT`.

    pixi run example gl_shapes
    pixi run example gl_shapes fullscreen
    mojo build -I src examples/gl_shapes.mojo -o build/gl_shapes && ./build/gl_shapes

`WindowMode.FULLSCREEN` covers the display without changing the design
resolution, so the letterbox bars stay in the frame and just get wider — the
GPU backend takes the mode exactly as the CPU one does. Escape quits.
"""

from create import *


@fieldwise_init
struct App(Program):
    var angle: Float64
    var logo: Sprite
    var fps: Int

    @staticmethod
    def create(mut context: Context) raises -> App:
        # FIT with a 4:3 design in a 16:9 window, so the letterbox bars are
        # on screen from the first frame.
        context.autoscale = AutoScale.FIT
        context.design_resolution(800, 600)
        # Twice, below, from one interned image and so one GL upload.
        var logo = Sprite.load(source_path("../assets/logo/png/logo.png"))
        return App(0.0, logo^, 0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.angle += context.time.delta
        self.fps = Int(context.framerate())

        canvas.background(Color(0x20, 0x24, 0x2C))

        # A plain filled rect and an outlined one, side by side.
        with canvas.style():
            canvas.outline_enabled(False)
            canvas.fill(Color(0x3D, 0x8B, 0xFD))
            canvas.rectangle((-260, 180), 160, 100)

        with canvas.style():
            canvas.fill(Color(0xFD, 0xA4, 0x3D))
            canvas.outline(Color.BLACK, thickness=6)
            canvas.rectangle((-60, 180), 160, 100)

        # An outline wider than the shape: all outline, no interior.
        with canvas.style():
            canvas.fill(Color.RED)
            canvas.outline(Color.WHITE, thickness=30)
            canvas.rectangle((160, 180), 40, 40)

        # Translucent over the blue rect — the case a double-blended fill
        # under its own outline would get visibly wrong.
        with canvas.style():
            canvas.fill(Color(0x00, 0xFF, 0x88, 0x80))
            canvas.outline(Color(0xFF, 0xFF, 0xFF, 0x80), thickness=8)
            canvas.circle((-260, 180), 70)

        with canvas.style():
            canvas.outline_enabled(False)
            canvas.fill(Color(0xE0, 0x50, 0x90))
            canvas.circle((0, 0), 90)

        with canvas.style():
            canvas.fill(Color(0x30, 0x30, 0x38))
            canvas.outline(Color(0x9C, 0xE8, 0x6E), thickness=10)
            canvas.circle((220, 0), 80)

        # A rotating rect: the transform is baked per vertex, so a rotated
        # outline ring has to follow the shape rather than stay axis-aligned.
        with canvas.transform(translate(-230, 0) @ rotate(self.angle)):
            with canvas.style():
                canvas.fill(Color(0xFF, 0xD5, 0x4F))
                canvas.outline(Color.BLACK, thickness=4)
                canvas.rectangle((0, 0), 120, 120)

        with canvas.style():
            canvas.outline(Color(0x6E, 0xD8, 0xE8), thickness=5)
            canvas.line((-340, -140), (340, -260))

        with canvas.style():
            canvas.fill(Color(0x88, 0x5F, 0xE8))
            canvas.outline(Color.WHITE, thickness=3)
            canvas.triangle((-140, -180), (40, -180), (-50, -30))

        # The same image at two sizes: one texture, one upload, and — since
        # the two renders are adjacent — one extra batch for the pair.
        # Text before the sprites: solids and glyphs share the atlas binding
        # and so share one batch, which the sprite texture then breaks.
        with canvas.style():
            canvas.outline_enabled(False)
            canvas.text_color(Color.WHITE)
            canvas.font_size(28)
            canvas.text_align(Align.CENTER)
            canvas.text("centre / middle", (0, 0))

        with canvas.style():
            canvas.outline_enabled(False)
            canvas.text_color(Color(0x9C, 0xE8, 0x6E))
            canvas.font_size(20)
            canvas.text_align(Align.TOP_LEFT)
            canvas.text("left / top", (canvas.left() + 12, canvas.top() - 12))

        with canvas.style():
            canvas.outline_enabled(False)
            canvas.text_color(Color(0xFF, 0xD5, 0x4F, 0xA0))
            canvas.font_size(20)
            canvas.text_align(Align.BOTTOM_RIGHT)
            canvas.text(
                "right / bottom — translucent",
                (canvas.right() - 12, canvas.bottom() + 12),
            )

        canvas.sprite(self.logo, (250, -170), 140, 140)
        canvas.sprite(self.logo, (90, -230), 70, 70)

        with canvas.style():
            canvas.font_size(20)
            canvas.text_color(Color.WHITE)
            canvas.text_align(Align.TOP_RIGHT)
            canvas.text(
                "fps: " + String(self.fps),
                (canvas.right() - 12, canvas.top() - 12),
            )


def main() raises:
    run[App](
        "GL Shapes",
        WindowMode.FULLSCREEN,
        width=1280,
        height=720,
        backend=RenderBackend.GPU,
    )
