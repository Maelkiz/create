"""The same heavy frame on both backends, timed.

    pixi run example gl_bench        # GPU, vsync off
    pixi run example gl_bench cpu    # CPU replay, for comparison

The sketch is deliberately more than a display is worth: a few thousand
animated shapes, two sprites and a block of text, all of it re-recorded every
frame so the measurement covers recording, tessellation and rasterisation
rather than a static buffer being re-shown. Frame times are printed as a
rolling mean over `_WINDOW` frames, so a single hitch does not read as a
regression.

Vsync is off on the GPU path — pinned to the refresh rate every frame would
measure the monitor. The CPU path has no equivalent switch: it blits through
SDL and is nowhere near the refresh rate on this sketch anyway.

`run_gl` is internal while the GPU backend is being built, so this example
names it by path rather than through the preamble.
"""

from std.sys import argv

from create import *
from create.core._run_gl import run_gl

comptime _SHAPES = 2000
"""Shapes per frame. Chosen so the GPU path is still comfortable and the CPU
path is visibly not — the point of the sketch is the gap between them."""
comptime _WINDOW = 120
"""Frames per printed line."""


def _round(v: Float64) -> String:
    """Two decimals. A frame time printed to fifteen is noise, not precision."""
    return String(Float64(Int(v * 100.0 + 0.5)) / 100.0)


@fieldwise_init
struct Bench(Program):
    var t: Float64
    var logo: Sprite
    var frames: Int
    var elapsed: Float64
    var worst: Float64

    @staticmethod
    def create(mut options: Options) raises -> Bench:
        options.autoscale = AutoScale.OFF
        return Bench(
            0.0,
            Sprite.load(script_dir() + "/../assets/logo/logo-cutout.png"),
            0,
            0.0,
            0.0,
        )

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        self.t += frame.time.delta
        self.frames += 1
        self.elapsed += frame.time.delta
        self.worst = max(self.worst, frame.time.delta)
        if self.frames == _WINDOW:
            var mean_ms = self.elapsed / Float64(_WINDOW) * 1000.0
            print(
                _round(mean_ms)
                + " ms mean, "
                + _round(self.worst * 1000.0)
                + " ms worst, "
                + _round(1000.0 / mean_ms)
                + " fps, "
                + String(frame.width)
                + "x"
                + String(frame.height)
            )
            self.frames = 0
            self.elapsed = 0.0
            self.worst = 0.0

        frame.background(Color.WHITE)

        # One generator re-seeded every frame, so the layout is identical from
        # frame to frame and the two backends draw the same sketch — only the
        # phase of the animation moves.
        var rng = Random(1234)
        var w = frame.right()
        var h = frame.top()
        with frame.style():
            frame.outline(enabled=False)
            for i in range(_SHAPES):
                var x = rng.float(-w, w)
                var y = rng.float(-h, h)
                var size = rng.float(8.0, 34.0)
                var phase = self.t + rng.float(0.0, 6.283)
                var hue = Color.hsv(rng.float(0.0, 360.0), 0.7, 1.0)
                frame.fill(Color(hue.r, hue.g, hue.b, 0xC0))
                var kind = i % 3
                if kind == 0:
                    frame.rectangle(
                        (x + 20.0 * cos(phase), y), size, size * 0.7
                    )
                elif kind == 1:
                    frame.circle((x, y + 20.0 * sin(phase)), size * 0.5)
                else:
                    frame.triangle(
                        (x, y + size),
                        (x - size, y - size),
                        (x + size, y - size),
                    )

        # Two sprites: one texture, so one extra batch for the pair rather
        # than one each.
        frame.sprite(self.logo, -w + 90, h - 90, 140, 140)
        frame.sprite(self.logo, -w + 220, h - 90, 100, 100)

        with frame.style():
            frame.outline(enabled=False)
            frame.font_size(48)
            frame.font_weight(FontWeight.MEDIUM)
            frame.text_align(Align.CENTER)
            frame.text(
                String(_SHAPES) + " shapes, two sprites, this text", 0, 0
            )


def main() raises:
    var cpu = False
    for i in range(1, len(argv())):
        if argv()[i] == "cpu":
            cpu = True
    if cpu:
        run[Bench]("Bench (CPU)", width=1920, height=1080)
    else:
        run_gl[Bench]("Bench (GPU)", width=1920, height=1080, vsync=False)
