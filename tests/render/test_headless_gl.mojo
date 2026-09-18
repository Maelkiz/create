# Coverage the CPU-vs-GPU parity test is structurally blind to: does
# `run_headless(..., backend=RenderBackend.GPU)` itself work — a correct
# `MemorySurface` back out, the letterbox painted, several frames advancing
# state. Skips with no GL context, same as the parity test.

from std.testing import TestSuite, assert_equal

from create import *
from create.core.headless import run_headless
from create.render.render_backend import RenderBackend


@fieldwise_init
struct GPURect(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> GPURect:
        return GPURect(0)

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(10, 20, 30))
        canvas.no_stroke()
        canvas.fill(Color.RED)
        canvas.rectangle(0.0, 0.0, 20.0, 20.0)


def test_the_gpu_backend_paints_a_filled_rectangle() raises -> None:
    var m: MemorySurface
    try:
        m = run_headless[GPURect](32, 32, backend=RenderBackend.GPU)
    except e:
        print("SKIP — no GL context:", e)
        return

    assert_equal(m.pixel(16, 16), Color.RED, "centre")
    assert_equal(m.pixel(1, 1), Color(10, 20, 30), "corner")


@fieldwise_init
struct GPUMover(Program):
    var x: Float64

    @staticmethod
    def create(mut ctx: Context) raises -> GPUMover:
        return GPUMover(-20.0)

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.x += 20.0

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color(10, 20, 30))
        canvas.no_stroke()
        canvas.fill(Color.RED)
        canvas.rectangle(self.x, 0.0, 16.0, 16.0)


def test_the_gpu_backend_returns_only_the_last_of_several_frames() raises -> (
    None
):
    var m: MemorySurface
    try:
        m = run_headless[GPUMover](64, 32, frames=2, backend=RenderBackend.GPU)
    except e:
        print("SKIP — no GL context:", e)
        return

    # Two updates land the rectangle at world x=20 (start -20, +20 each
    # frame); a leftover frame would still show it at -20.
    assert_equal(m.pixel(32 + 20, 16), Color.RED, "final position")
    assert_equal(
        m.pixel(32 - 20, 16), Color(10, 20, 30), "start position cleared"
    )


def test_the_gpu_backend_paints_letterbox_bars() raises -> None:
    var m: MemorySurface
    try:
        m = run_headless[GPURect](
            64, 64, pixel_width=128, pixel_height=64, backend=RenderBackend.GPU
        )
    except e:
        print("SKIP — no GL context:", e)
        return

    # 64x64 design in a 128x64 buffer scales 1:1 and centres, leaving 32px
    # bars either side. Sampled away from the 20x20 rect at the centre, so
    # this reads the background fill, not the shape — the default letterbox
    # colour is distinct from both.
    assert_equal(m.pixel(5, 32), Color(0x22), "left bar")
    assert_equal(m.pixel(40, 32), Color(10, 20, 30), "content")
    assert_equal(m.pixel(122, 32), Color(0x22), "right bar")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
