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
    def create(mut frame: Frame) raises -> GPURect:
        return GPURect(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        frame.background(Color(10, 20, 30))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 20.0, 20.0)


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
    def create(mut frame: Frame) raises -> GPUMover:
        return GPUMover(-20.0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.x += 20.0

        frame.background(Color(10, 20, 30))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(self.x, 0.0, 16.0, 16.0)


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


@fieldwise_init
struct GPURoundedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> GPURoundedRect:
        return GPURoundedRect(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        frame.background(Color(10, 20, 30))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.corner_radius(8)
        frame.rectangle(0.0, 0.0, 40.0, 40.0)


def test_the_gpu_backend_rounds_rectangle_corners() raises -> None:
    """Parity alone would not catch a GPU path that skipped rounding
    entirely — a corner fillet is too small a fraction of the shape's area
    to move the structural tolerances. This checks the corner directly."""
    var m: MemorySurface
    try:
        m = run_headless[GPURoundedRect](100, 100, backend=RenderBackend.GPU)
    except e:
        print("SKIP — no GL context:", e)
        return

    # The untouched corner (world (-20, -20), device (30, 70)) sits outside
    # the radius-8 fillet disc centred at world (-12, -12) — background if
    # rounding actually happened, fill if it did not.
    assert_equal(m.pixel(30, 70), Color(10, 20, 30), "naive sharp corner")
    # Well inside that same fillet's disc: still fill.
    assert_equal(m.pixel(35, 65), Color.RED, "inside the fillet arc")
    # Deep interior, unaffected by rounding either way.
    assert_equal(m.pixel(50, 50), Color.RED, "interior")


@fieldwise_init
struct GPURoundedTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> GPURoundedTriangle:
        return GPURoundedTriangle(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        frame.background(Color(10, 20, 30))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.corner_radius(8)
        frame.triangle((-20, -20), (20, -20), (-20, 20))


def test_the_gpu_backend_rounds_triangle_corners() raises -> None:
    """Parity alone would not catch a GPU path that skipped rounding
    entirely — a corner fillet is too small a fraction of the shape's area
    to move the structural tolerances. This checks the corner directly."""
    var m: MemorySurface
    try:
        m = run_headless[GPURoundedTriangle](
            100, 100, backend=RenderBackend.GPU
        )
    except e:
        print("SKIP — no GL context:", e)
        return

    # The right-angle vertex sits at world (-20, -20), device (30, 70).
    # A radius-8 fillet erodes it back along both edges, so the naive
    # sharp corner is background if rounding actually happened.
    assert_equal(m.pixel(30, 70), Color(10, 20, 30), "naive sharp corner")
    # Just inside the fillet arc, close to the vertex.
    assert_equal(m.pixel(33, 67), Color.RED, "inside the fillet arc")
    # Deep interior, unaffected by rounding either way.
    assert_equal(m.pixel(45, 55), Color.RED, "interior")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
