"""Saving the frame, both ways.

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


@fieldwise_init
struct App(Program):
    var angle: Float64
    var saved: String

    @staticmethod
    def create(mut frame: Frame) raises -> App:
        frame.autoscale = AutoScale.FIT
        frame.design(_DESIGN_W, _DESIGN_H)
        return App(0.0, "")

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.angle += 0.6 * frame.time.delta

        # Filed the moment the key is read, and written at `present` — the
        # file holds the whole frame however early in `update` it was asked
        # for, so nothing has to be drawn before asking.
        var dir = script_dir()
        if input.just_pressed("s"):
            frame.save_screenshot(dir + "/../out/screenshot.png")
            self.saved = "screenshot.png — the window, bars included"
        elif input.just_pressed("i"):
            if input.is_key_down("shift"):
                frame.save_image(
                    dir + "/../out/image@2x.png", 2.0, transparent=True
                )
                self.saved = "image@2x.png — 1600x1000, transparent"
            else:
                frame.save_image(dir + "/../out/image.png")
                self.saved = "image.png — 800x500, no bars"

        frame.background(Color(0x14, 0x1C, 0x26))

        with frame.style():
            frame.outline(enabled=False)
            with frame.transform(rotate(self.angle)):
                frame.fill(Color(0xE0, 0x50, 0x50))
                frame.rectangle((0, 0), 220, 220)
                frame.fill(Color(0x50, 0xC0, 0xE0))
                frame.circle((0, 0), 70)

        frame.text_color(Color.WHITE)
        frame.text_align(Align.TOP)
        frame.font_size(26)
        frame.text("S - screenshot     I - image     Shift+I - 2x", 0, 220)
        frame.font_size(20)
        if self.saved:
            frame.text("wrote " + self.saved, 0, -200)


def main() raises:
    run[App]("Saving the frame", _DESIGN_W, _DESIGN_H)
