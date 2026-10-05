"""The offscreen canvas: a `Canvas(width, height)` a program builds, draws
into and reads back, outside any run loop.

A 100 x 60 canvas: screen x in -50..50, y in -30..30, y up.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from create import *
from create.core.headless import run_headless
from create.render.render_backend import RenderBackend

comptime _IMAGE = "/tmp/mojo_create_test_offscreen_image.png"
comptime _SHOT = "/tmp/mojo_create_test_offscreen_shot.png"


def _canvas(scale: Float64 = 1.0) raises -> Canvas:
    return Canvas(100, 60, scale=scale, antialiasing=Antialiasing.OFF)


def _square(mut canvas: Canvas, position: Point2D, color: Color):
    with canvas.style(fill=color, outline_enabled=False):
        canvas.rectangle(position, 20, 20)


def test_a_new_offscreen_canvas_is_transparent() raises -> None:
    var canvas = _canvas()
    assert_equal(canvas.width, 100)
    assert_equal(canvas.height, 60)
    assert_equal(canvas.pixel((0, 0)), Color.TRANSPARENT)
    assert_equal(canvas.pixel((-49, 29)), Color.TRANSPARENT)


def test_it_reads_what_is_drawn() raises -> None:
    var canvas = _canvas()
    _square(canvas, (0, 0), Color.BLUE)
    assert_equal(canvas.pixel((0, 0)), Color.BLUE)
    assert_equal(canvas.pixel((-45, 25)), Color.TRANSPARENT)
    assert_equal(canvas.pixel((0, 31)), Color.TRANSPARENT, "off the canvas")


def test_drawing_after_a_read_lands_on_what_is_there() raises -> None:
    var canvas = _canvas()
    _square(canvas, (-20, 0), Color.BLUE)
    assert_equal(canvas.pixel((-20, 0)), Color.BLUE)
    _square(canvas, (20, 0), Color.RED)
    assert_equal(canvas.pixel((-20, 0)), Color.BLUE, "kept from the read")
    assert_equal(canvas.pixel((20, 0)), Color.RED)


def test_a_read_drops_the_commands_it_replayed() raises -> None:
    var canvas = _canvas()
    for i in range(5):
        _square(canvas, (Float64(i * 10 - 20), 0), Color.BLUE)
        _ = canvas.pixel((0, 0))
        assert_equal(len(canvas._state.backend.commands), 0)
    assert_equal(len(canvas._state.backend.clips), 0)


def test_drawing_after_a_read_inside_a_clip_stays_clipped() raises -> None:
    var canvas = _canvas()
    with canvas.clip(Rectangle(Point2D(-20, 0), 20, 20)):
        _square(canvas, (-20, 0), Color.BLUE)
        assert_equal(canvas.pixel((-20, 0)), Color.BLUE)
        # The clip covers only the left square, so this one draws nothing.
        _square(canvas, (20, 0), Color.RED)
    assert_equal(canvas.pixel((20, 0)), Color.TRANSPARENT)
    _square(canvas, (20, 0), Color.RED)
    assert_equal(canvas.pixel((20, 0)), Color.RED, "the clip has ended")


def test_scale_sets_the_pixel_density() raises -> None:
    var canvas = _canvas(scale=2.0)
    assert_equal(canvas.width, 100, "the size stays in screen units")
    assert_equal(canvas.scale, 2.0)
    ref target = canvas._state.backend.target.value()
    assert_equal(target.width, 200)
    assert_equal(target.height, 120)
    _square(canvas, (0, 0), Color.BLUE)
    assert_equal(canvas.pixel((9, 9)), Color.BLUE)
    assert_equal(canvas.pixel((11, 0)), Color.TRANSPARENT)


def test_it_can_be_kept_and_moved() raises -> None:
    var canvas = _canvas()
    _square(canvas, (0, 0), Color.BLUE)
    var moved = canvas^
    assert_equal(moved.pixel((0, 0)), Color.BLUE)


def test_bad_sizes_and_scales_raise() raises -> None:
    with assert_raises(contains="size"):
        _ = Canvas(0, 60)
    with assert_raises(contains="size"):
        _ = Canvas(100, -1)
    with assert_raises(contains="scale"):
        _ = Canvas(100, 60, scale=0.0)


def test_it_antialiases_by_default() raises -> None:
    var canvas = Canvas(100, 60)
    with canvas.style(fill=Color.BLUE, outline_enabled=False):
        canvas.circle((0, 0), 20.3)
    var edge = canvas.pixel((20, 0))
    assert_true(edge.a > 0 and edge.a < 255, "a partly covered edge pixel")


def test_a_snapshot_is_the_whole_canvas() raises -> None:
    var canvas = _canvas()
    _square(canvas, (-20, 0), Color.BLUE)
    var shot = canvas.snapshot()
    assert_equal(shot.width, 100)
    assert_equal(shot.height, 60)
    # Image coordinates: top-left origin, y down.
    assert_equal(shot.pixel(30, 30), Color.BLUE)
    assert_equal(shot.pixel(70, 30), Color.TRANSPARENT)


def test_a_snapshot_at_its_own_scale_is_its_pixels() raises -> None:
    var canvas = _canvas(scale=2.0)
    _square(canvas, (-20, 0), Color.BLUE)
    var shot = canvas.snapshot(scale=canvas.scale)
    assert_equal(shot.width, 200)
    assert_equal(shot.height, 120)
    ref target = canvas._state.backend.target.value()
    for y in range(shot.height):
        for x in range(shot.width):
            assert_equal(shot.pixel(x, y), target.pixel(x, y))


def test_a_snapshot_at_another_scale_resamples() raises -> None:
    var canvas = _canvas(scale=2.0)
    _square(canvas, (-20, 0), Color.BLUE)
    var shot = canvas.snapshot()
    assert_equal(shot.width, 100)
    assert_equal(shot.pixel(30, 30), Color.BLUE)
    assert_equal(shot.pixel(70, 30), Color.TRANSPARENT)


def test_a_region_snapshot_is_cropped_upright_and_clear_off_it() raises -> None:
    var canvas = _canvas()
    _square(canvas, (40, 20), Color.BLUE)
    # Centred on the square's top-right corner, half past the canvas edge.
    var shot = canvas.snapshot(Rectangle(Point2D(50, 30), 20, 20))
    assert_equal(shot.width, 20)
    assert_equal(shot.pixel(5, 15), Color.BLUE, "bottom-left: the square")
    assert_equal(shot.pixel(15, 5), Color.TRANSPARENT, "off the canvas")


def test_a_snapshot_keeps_drawing_after_it() raises -> None:
    var canvas = _canvas()
    _square(canvas, (-20, 0), Color.BLUE)
    var first = canvas.snapshot()
    _square(canvas, (20, 0), Color.RED)
    var second = canvas.snapshot()
    assert_equal(first.pixel(70, 30), Color.TRANSPARENT)
    assert_equal(second.pixel(30, 30), Color.BLUE)
    assert_equal(second.pixel(70, 30), Color.RED)


def test_save_image_and_save_screenshot_write_at_once() raises -> None:
    var canvas = _canvas(scale=2.0)
    _square(canvas, (-20, 0), Color.BLUE)
    canvas.save_image(_IMAGE, transparent=True)
    canvas.save_screenshot(_SHOT)
    var image = Image.load(_IMAGE)
    assert_equal(image.width, 100, "save_image: screen units times scale")
    assert_equal(image.pixel(30, 30), Color.BLUE)
    assert_equal(image.pixel(70, 30), Color.TRANSPARENT, "alpha kept")
    var shot = Image.load(_SHOT)
    assert_equal(shot.width, 200, "save_screenshot: its own pixels")
    assert_equal(shot.pixel(60, 60), Color.BLUE)
    assert_equal(shot.pixel(140, 60), Color.TRANSPARENT)


def test_autoclear_and_letterbox_have_no_effect() raises -> None:
    var canvas = _canvas()
    canvas.autoclear(True)
    canvas.letterbox_color(Color.RED)
    _square(canvas, (0, 0), Color.BLUE)
    assert_equal(canvas.pixel((0, 0)), Color.BLUE)
    assert_equal(canvas.pixel((-45, 25)), Color.TRANSPARENT)


@fieldwise_init
struct DrawsABadge(Program):
    var badge: Image

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> DrawsABadge:
        var badge = Canvas(40, 40, antialiasing=Antialiasing.OFF)
        _square(badge, (0, 0), Color.BLUE)
        return DrawsABadge(badge.snapshot())

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.RED)
        canvas.image(self.badge, (30, -10))


def _check_badge(m: MemorySurface) raises:
    # 200 x 100 design: (30, -10) is pixel (130, 60).
    assert_equal(m.pixel(130, 60), Color.BLUE)
    assert_equal(m.pixel(145, 60), Color.RED, "the badge's clear corner")


def test_a_snapshot_draws_on_a_frame_canvas() raises -> None:
    _check_badge(run_headless[DrawsABadge](200, 100, frames=2))


def test_a_snapshot_draws_on_the_gpu_too() raises -> None:
    var m: MemorySurface
    try:
        m = run_headless[DrawsABadge](
            200, 100, frames=2, backend=RenderBackend.GPU
        )
    except e:
        print("SKIP — no GL context:", e)
        return
    _check_badge(m)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
