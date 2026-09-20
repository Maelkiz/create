"""The five solid command kinds, drawn on the GPU backend.

The visual comparison target for the CPU path: run this, then drop the
`backend=RenderBackend.GPU` argument, and the two frames should be indistinguishable
apart from the GPU's multisampled edges. Everything on screen is deliberately
a case the two backends could disagree about — a translucent fill under an
outline, an outline wider than its shape, a rotated rect, a diagonal line, a
letterbox bar under `FIT`.

    pixi run create examples/gl_shapes.mojo
    pixi run create examples/gl_shapes.mojo fullscreen
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
    def create(mut frame: Frame) raises -> App:
        # FIT with a 4:3 design in a 16:9 window, so the letterbox bars are
        # on screen from the first frame.
        frame.autoscale = AutoScale.FIT
        frame.design(800, 600)
        # Twice, below, from one interned image and so one GL upload.
        var logo = Sprite.load(script_dir() + "/sprite/assets/sprite.png")
        return App(0.0, logo^, 0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.angle += frame.time.delta
        self.fps = Int(frame.framerate())

    def render(self, mut frame: Frame) raises:
        frame.background(Color(0x20, 0x24, 0x2C))

        # A plain filled rect and an outlined one, side by side.
        with frame.style():
            frame.outline(enabled=False)
            frame.fill(Color(0x3D, 0x8B, 0xFD))
            frame.rectangle((-260, 180), 160, 100)

        with frame.style():
            frame.fill(Color(0xFD, 0xA4, 0x3D))
            frame.outline(Color.BLACK, thickness=6)
            frame.rectangle((-60, 180), 160, 100)

        # An outline wider than the shape: all outline, no interior.
        with frame.style():
            frame.fill(Color.RED)
            frame.outline(Color.WHITE, thickness=30)
            frame.rectangle((160, 180), 40, 40)

        # Translucent over the blue rect — the case a double-blended fill
        # under its own outline would get visibly wrong.
        with frame.style():
            frame.fill(Color(0x00, 0xFF, 0x88, 0x80))
            frame.outline(Color(0xFF, 0xFF, 0xFF, 0x80), thickness=8)
            frame.circle((-260, 180), 70)

        with frame.style():
            frame.outline(enabled=False)
            frame.fill(Color(0xE0, 0x50, 0x90))
            frame.circle((0, 0), 90)

        with frame.style():
            frame.fill(Color(0x30, 0x30, 0x38))
            frame.outline(Color(0x9C, 0xE8, 0x6E), thickness=10)
            frame.circle((220, 0), 80)

        # A rotating rect: the transform is baked per vertex, so a rotated
        # outline ring has to follow the shape rather than stay axis-aligned.
        with frame.transform(translate(-230, 0) @ rotate(self.angle)):
            with frame.style():
                frame.fill(Color(0xFF, 0xD5, 0x4F))
                frame.outline(Color.BLACK, thickness=4)
                frame.rectangle((0, 0), 120, 120)

        with frame.style():
            frame.outline(Color(0x6E, 0xD8, 0xE8), thickness=5)
            frame.line((-340, -140), (340, -260))

        with frame.style():
            frame.fill(Color(0x88, 0x5F, 0xE8))
            frame.outline(Color.WHITE, thickness=3)
            frame.triangle((-140, -180), (40, -180), (-50, -30))

        # The same image at two sizes: one texture, one upload, and — since
        # the two draws are adjacent — one extra batch for the pair.
        # Text before the sprites: solids and glyphs share the atlas binding
        # and so share one batch, which the sprite texture then breaks.
        with frame.style():
            frame.outline(enabled=False)
            frame.text_color(Color.WHITE)
            frame.font_size(28)
            frame.text_align(Align.CENTER)
            frame.text("centre / middle", 0, 0)

        with frame.style():
            frame.outline(enabled=False)
            frame.text_color(Color(0x9C, 0xE8, 0x6E))
            frame.font_size(20)
            frame.text_align(Align.TOP_LEFT)
            frame.text("left / top", frame.left() + 12, frame.top() - 12)

        with frame.style():
            frame.outline(enabled=False)
            frame.text_color(Color(0xFF, 0xD5, 0x4F, 0xA0))
            frame.font_size(20)
            frame.text_align(Align.BOTTOM_RIGHT)
            frame.text(
                "right / bottom — translucent",
                frame.right() - 12,
                frame.bottom() + 12,
            )

        frame.sprite(self.logo, 250, -170, 140, 140)
        frame.sprite(self.logo, 90, -230, 70, 70)

        with frame.style():
            frame.font_size(20)
            frame.text_color(Color.WHITE)
            frame.text_align(Align.TOP_RIGHT)
            frame.text(
                "fps: " + String(self.fps),
                frame.right() - 12,
                frame.top() - 12,
            )


def main() raises:
    run[App]("GL Shapes", 1280, 720, WindowMode.FULLSCREEN, RenderBackend.GPU)
