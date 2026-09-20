# Coverage the CPU-vs-GPU parity test and the GL batching tests are both
# blind to: `_flush_screenshot_gpu` is a real driver readback, not the CPU
# path's memcpy, and `save_image`'s CPU-replay-under-both-backends contract
# — documented but never checked — is what lets a GPU frame be captured at a
# resolution the window never had. Skips with no GL context, same as the
# other GL tests.

from std.os import remove

from create import *
from create.core.headless import run_headless
from create.render.render_backend import RenderBackend
from create.sprite.sprite import Sprite
from std.testing import TestSuite, assert_equal

comptime _SHOT = "/tmp/mojo_create_test_gl_capture_shot.png"
comptime _IMG_CPU = "/tmp/mojo_create_test_gl_capture_image_cpu.png"
comptime _IMG_GPU = "/tmp/mojo_create_test_gl_capture_image_gpu.png"


def _saved(path: String) raises -> Sprite:
    """Read back a file one of these programs wrote, then delete it."""
    var back = Sprite.load(path)
    remove(path)
    return back^


def _px(s: Sprite, x: Int, y: Int) -> Color:
    var off = (y * s.width + x) * 4
    return Color(
        s.pixels[off], s.pixels[off + 1], s.pixels[off + 2], s.pixels[off + 3]
    )


def _scene(mut frame: Frame):
    """A black ground with a 20x20 red square on the origin — the same
    layout `test_frame.mojo`'s capture tests use, so the sample points
    below are proven-safe coordinates rather than newly guessed ones."""
    frame.background(Color.BLACK)
    frame.outline(enabled=False)
    frame.fill(Color.RED)
    frame.rectangle(0.0, 0.0, 20.0, 20.0)


@fieldwise_init
struct GPUScreenshot(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> GPUScreenshot:
        return GPUScreenshot(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        _scene(frame)
        frame.save_screenshot(_SHOT)


def test_gpu_screenshot_has_the_framebuffer_resolution_and_is_opaque() raises -> (
    None
):
    try:
        _ = run_headless[GPUScreenshot](
            200, 100, 1, 640, 480, backend=RenderBackend.GPU
        )
    except e:
        print("SKIP — no GL context:", e)
        return

    var shot = _saved(_SHOT)
    assert_equal(shot.width, 640)
    assert_equal(shot.height, 480)
    # The design area, scaled 3.2x and centred, with the bars either side —
    # same layout `test_frame.mojo`'s CPU screenshot test checks.
    assert_equal(_px(shot, 320, 240), Color.RED)
    assert_equal(_px(shot, 320, 5), Color(0x22))
    # _force_opaque runs on this path only: every alpha byte must read 255,
    # including under the red square, where the live frame is already
    # opaque, and under the bars, which the CPU screenshot leaves alone.
    assert_equal(_px(shot, 320, 240).a, 255)
    assert_equal(_px(shot, 320, 5).a, 255)


@fieldwise_init
struct CaptureImageCPU(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> CaptureImageCPU:
        return CaptureImageCPU(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        _scene(frame)
        frame.save_image(_IMG_CPU)


@fieldwise_init
struct CaptureImageGPU(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> CaptureImageGPU:
        return CaptureImageGPU(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        _scene(frame)
        frame.save_image(_IMG_GPU)


def test_gpu_save_image_matches_cpu_save_image_byte_for_byte() raises -> None:
    var gpu_m: MemorySurface
    try:
        gpu_m = run_headless[CaptureImageGPU](
            200,
            100,
            1,
            640,
            480,
            backend=RenderBackend.GPU,
        )
    except e:
        print("SKIP — no GL context:", e)
        return
    _ = gpu_m^

    # The CPU backend runs unconditionally: it needs no GL context, and the
    # comparison is meaningless without both files present.
    var cpu_m = run_headless[CaptureImageCPU](200, 100, 1, 640, 480)
    _ = cpu_m^

    var cpu = _saved(_IMG_CPU)
    var gpu = _saved(_IMG_GPU)
    assert_equal(cpu.width, gpu.width)
    assert_equal(cpu.height, gpu.height)
    var a = cpu.pixels.unsafe_ptr()
    var b = gpu.pixels.unsafe_ptr()
    for i in range(cpu.width * cpu.height * 4):
        assert_equal(Int(a[unsafe_offset=i]), Int(b[unsafe_offset=i]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
