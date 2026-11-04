"""Saving the frame, three ways: a screenshot, an image and a recording.

    S          screenshot: what the window shows, at its own pixel size,
               letterbox bars and all
    I          image: what the program drew, at the 800x500 design
               resolution, no bars, identical on every machine
    Shift+I    the same image at 2x, with a transparent background
    R          start or stop recording an animated GIF of what the program
               draws, as the image is drawn, for up to ten seconds

Resize the window and press S and I to see the difference: the screenshot
follows the window, the image never does. Under `RenderBackend.GPU` the
image and the recording come out byte-identical, because they are
rasterised on the CPU from the frame's recorded commands rather than read
back off the driver. Everything is written to the `out` folder beside this
file.
"""

from std.os import makedirs

from create import *

comptime _DESIGN_W = 800
comptime _DESIGN_H = 500
comptime _RECORD_SECONDS = 10.0


@fieldwise_init
struct Capture(Program):
    var angle: Float64
    var saved: String

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Capture:
        # Saving into a folder that isn't there fails, so make it first.
        makedirs(source_path("out"), exist_ok=True)
        return Capture(0.0, "")

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.angle += 0.6 * context.time.delta
        ref input = context.input

        # Filed the moment the key is read, and written at `present` — the
        # file holds the whole frame however early in `update` it was asked
        # for, so nothing has to be rendered before asking.
        if input.key_pressed(Key.S):
            canvas.save_screenshot(source_path("out/screenshot.png"))
            self.saved = "screenshot.png: the window, bars included"
        elif input.key_pressed(Key.I):
            if input.key_down(Key.SHIFT):
                canvas.save_image(
                    source_path("out/image@2x.png"), 2.0, transparent=True
                )
                self.saved = "image@2x.png: 1600x1000, transparent"
            else:
                canvas.save_image(source_path("out/image.png"))
                self.saved = "image.png: 800x500, no bars"
        elif input.key_pressed(Key.R):
            # Recording runs on by itself, frame after frame, until its
            # limit or a stop; the file is complete once it ends.
            if canvas.recording():
                canvas.stop_recording()
                self.saved = "recording.gif"
            else:
                canvas.record(
                    source_path("out/recording.gif"), seconds=_RECORD_SECONDS
                )
                self.saved = ""

        canvas.background(Color(0x14, 0x1C, 0x26))

        with canvas.style(outline_enabled=False):
            with canvas.transform(rotate(self.angle)):
                canvas.fill(Color(0x3A, 0x86, 0xFF))
                canvas.rectangle((0, 0), 220, 220)
                canvas.fill(Color(0x78, 0xD2, 0x8C))
                canvas.circle((0, 0), 70)

        with canvas.style(
            text_color=Color.WHITE, font_size=24, text_align=Align.TOP
        ):
            canvas.text(
                "S: screenshot   I: image   Shift+I: image at 2x   R: record",
                (0, 220),
            )
        with canvas.style(text_color=Color.WHITE, font_size=20):
            if canvas.recording():
                var label = String("Recording; R to stop")
                # Drawn like everything else, so it is in the recording too.
                var dot = -canvas.text_width(label) / 2.0 - 16.0
                with canvas.style(fill=Color.RED, outline_enabled=False):
                    canvas.circle((dot, -200), 8)
                canvas.text(label, (0, -200))
            elif self.saved:
                canvas.text("Wrote " + self.saved, (0, -200))


def main() raises:
    run[Capture]("Capture", width=_DESIGN_W, height=_DESIGN_H)
