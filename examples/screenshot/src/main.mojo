"""Saving the canvas, both ways.

    S          screenshot — what the window shows, at its own pixel size,
               letterbox bars and all
    I          image — what the program drew, at the 800x500 design
               resolution, no bars, identical on every machine
    Shift+I    the same image at 2x, with a transparent background

Resize the window and press both keys to see the difference: the screenshot
follows the window, the image never does. Under `RenderBackend.GPU` the image
comes out byte-identical, because it is rasterised on the CPU from the frame's
recorded commands rather than read back off the driver.
"""

from create import *

comptime _DESIGN_W = 800
comptime _DESIGN_H = 500

comptime _NONE = 0
comptime _SCREENSHOT = 1
comptime _IMAGE = 2
comptime _IMAGE_2X = 3


@fieldwise_init
struct App(Program):
    var angle: Float64
    var request: Int
    """What `update` asked for this frame, for `render` to file.

    The save calls live on `Canvas`, which only `render` has — and `render`
    cannot see `Input`. So the keypress is read here and acted on there, and
    this is cleared at the top of every `update` so one press saves one file.
    """
    var saved: String

    @staticmethod
    def create(mut ctx: Context) raises -> App:
        ctx.autoscale = AutoScale.FIT
        ctx.design(_DESIGN_W, _DESIGN_H)
        return App(0.0, _NONE, "")

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.request = _NONE
        self.angle += 0.6 * ctx.time.delta

        if input.just_pressed("s"):
            self.request = _SCREENSHOT
            self.saved = "screenshot.png — the window, bars included"
        elif input.just_pressed("i"):
            if input.is_key_down("shift"):
                self.request = _IMAGE_2X
                self.saved = "image@2x.png — 1600x1000, transparent"
            else:
                self.request = _IMAGE
                self.saved = "image.png — 800x500, no bars"

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(0x14, 0x1C, 0x26))

        with canvas.style():
            canvas.no_stroke()
            with canvas.transform(rotate(self.angle)):
                canvas.fill(Color(0xE0, 0x50, 0x50))
                canvas.rectangle((0, 0), 220, 220)
                canvas.fill(Color(0x50, 0xC0, 0xE0))
                canvas.circle((0, 0), 70)

        canvas.fill(Color.WHITE)
        canvas.text_align(HorizontalAlignment.CENTER)
        canvas.font_size(26)
        canvas.text("S - screenshot     I - image     Shift+I - 2x", 0, 220)
        canvas.font_size(20)
        if self.saved:
            canvas.text("wrote " + self.saved, 0, -200)

        # Filed here, written at `present` — the file holds the whole frame
        # no matter how early in `render` the call is made.
        var dir = script_dir()
        if self.request == _SCREENSHOT:
            canvas.save_screenshot(dir + "/../out/screenshot.png")
        elif self.request == _IMAGE:
            canvas.save_image(dir + "/../out/image.png")
        elif self.request == _IMAGE_2X:
            canvas.save_image(
                dir + "/../out/image@2x.png", 2.0, transparent=True
            )


def main() raises:
    run[App]("Saving the canvas", _DESIGN_W, _DESIGN_H)
