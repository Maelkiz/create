"""The five solid command kinds, drawn on the GPU backend.

The visual comparison target for the CPU path: run this, then drop the
`backend=RenderBackend.GPU` argument, and the two frames should be indistinguishable
apart from the GPU's multisampled edges. Everything on screen is deliberately
a case the two backends could disagree about — a translucent fill under a
stroke, a stroke wider than its shape, a rotated rect, a diagonal line, a
letterbox bar under `FIT`.

    pixi run create examples/gl_shapes.mojo
    pixi run create examples/gl_shapes.mojo fullscreen
    mojo build -I src examples/gl_shapes.mojo -o build/gl_shapes && ./build/gl_shapes

`fullscreen` covers the display without changing the design resolution, so the
letterbox bars stay in the frame and just get wider — the GPU backend takes the
flag exactly as the CPU one does. Escape quits.
"""

from create import *


@fieldwise_init
struct App(Program):
    var angle: Float64
    var logo: Sprite

    @staticmethod
    def create(mut ctx: Context) raises -> App:
        # FIT with a 4:3 design in a 16:9 window, so the letterbox bars are
        # on screen from the first frame.
        ctx.autoscale = AutoScale.FIT
        ctx.design(800, 600)
        # Twice, below, from one interned image and so one GL upload.
        var logo = Sprite.load(script_dir() + "/sprite/assets/sprite.png")
        return App(0.0, logo^)

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.angle += ctx.time.delta

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(0x20, 0x24, 0x2C))

        # A plain filled rect and a stroked one, side by side.
        with canvas.style():
            canvas.no_stroke()
            canvas.fill(Color(0x3D, 0x8B, 0xFD))
            canvas.rectangle((-260, 180), 160, 100)

        with canvas.style():
            canvas.fill(Color(0xFD, 0xA4, 0x3D))
            canvas.stroke(Color.BLACK)
            canvas.stroke_width(6)
            canvas.rectangle((-60, 180), 160, 100)

        # A stroke wider than the shape: all outline, no interior.
        with canvas.style():
            canvas.fill(Color.RED)
            canvas.stroke(Color.WHITE)
            canvas.stroke_width(30)
            canvas.rectangle((160, 180), 40, 40)

        # Translucent over the blue rect — the case a double-blended fill
        # under its own stroke would get visibly wrong.
        with canvas.style():
            canvas.fill(Color(0x00, 0xFF, 0x88, 0x80))
            canvas.stroke(Color(0xFF, 0xFF, 0xFF, 0x80))
            canvas.stroke_width(8)
            canvas.circle((-260, 180), 70)

        with canvas.style():
            canvas.no_stroke()
            canvas.fill(Color(0xE0, 0x50, 0x90))
            canvas.circle((0, 0), 90)

        with canvas.style():
            canvas.fill(Color(0x30, 0x30, 0x38))
            canvas.stroke(Color(0x9C, 0xE8, 0x6E))
            canvas.stroke_width(10)
            canvas.circle((220, 0), 80)

        # A rotating rect: the transform is baked per vertex, so a rotated
        # stroke ring has to follow the shape rather than stay axis-aligned.
        with canvas.transform(translate(-230, 0) @ rotate(self.angle)):
            with canvas.style():
                canvas.fill(Color(0xFF, 0xD5, 0x4F))
                canvas.stroke(Color.BLACK)
                canvas.stroke_width(4)
                canvas.rectangle((0, 0), 120, 120)

        with canvas.style():
            canvas.stroke(Color(0x6E, 0xD8, 0xE8))
            canvas.stroke_width(5)
            canvas.line((-340, -140), (340, -260))

        with canvas.style():
            canvas.fill(Color(0x88, 0x5F, 0xE8))
            canvas.stroke(Color.WHITE)
            canvas.stroke_width(3)
            canvas.triangle((-140, -180), (40, -180), (-50, -30))

        # The same image at two sizes: one texture, one upload, and — since
        # the two draws are adjacent — one extra batch for the pair.
        # Text before the sprites: solids and glyphs share the atlas binding
        # and so share one batch, which the sprite texture then breaks.
        with canvas.style():
            canvas.no_stroke()
            canvas.fill(Color.WHITE)
            canvas.font_size(28)
            canvas.text_align(Align.CENTER)
            canvas.text("centre / middle", 0, 0)

        with canvas.style():
            canvas.no_stroke()
            canvas.fill(Color(0x9C, 0xE8, 0x6E))
            canvas.font_size(20)
            canvas.text_align(Align.TOP_LEFT)
            canvas.text("left / top", canvas.left() + 12, canvas.top() - 12)

        with canvas.style():
            canvas.no_stroke()
            canvas.fill(Color(0xFF, 0xD5, 0x4F, 0xA0))
            canvas.font_size(20)
            canvas.text_align(Align.BOTTOM_RIGHT)
            canvas.text(
                "right / bottom — translucent",
                canvas.right() - 12,
                canvas.bottom() + 12,
            )

        canvas.sprite(self.logo, 250, -170, 140, 140)
        canvas.sprite(self.logo, 90, -230, 70, 70)


def main() raises:
    run[App]("GL Shapes", 1280, 720, fullscreen=True, backend=RenderBackend.GPU)
