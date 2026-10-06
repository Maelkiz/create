"""Reading pixels back: `canvas.pixel`, `canvas.snapshot`, and the `Image`
pixels they hand back, edits included.

A 200 x 100 design: screen x in -100..100, y in -50..50, y up. Most tests
drive a `Canvas` directly so they can read in the middle of a frame and
present it after.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from create import *
from create.core.headless import run_headless
from create.render.canvas import PersistentCanvasState
from create.render.render_backend import RenderBackend

comptime _GRAY = Color(200)


def _canvas(
    mut context: Context, pixel_w: Int = 200, pixel_h: Int = 100
) raises -> Canvas:
    var state = PersistentCanvasState()
    context.design_size(200, 100)
    context._set_viewport(state, pixel_w, pixel_h)
    return context._new_canvas(state^)


def _present(
    mut context: Context, var canvas: Canvas, mut mem: MemorySurface
) raises -> Canvas:
    """Finish the frame onto `mem` and start the next one."""
    var state = canvas^._release()
    state.backend.present(mem.surface(), state.view.scale)
    context._set_viewport(state, mem.width, mem.height)
    return context._new_canvas(state^)


def _square(mut canvas: Canvas, position: Point2D, color: Color):
    with canvas.style(fill=color, outline_enabled=False):
        canvas.rectangle(position, 20, 20)


def test_pixel_reads_what_is_drawn_so_far() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    assert_equal(canvas.pixel((0, 0)), _GRAY, "the autoclear")
    canvas.background(Color.RED)
    assert_equal(canvas.pixel((0, 0)), Color.RED)
    _square(canvas, (0, 0), Color.BLUE)
    assert_equal(canvas.pixel((0, 0)), Color.BLUE, "read again after drawing")
    assert_equal(canvas.pixel((50, 0)), Color.RED)


def test_pixel_is_in_screen_space_and_transparent_off_it() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    with canvas.transform(translate(50.0, 20.0)):
        _square(canvas, (0, 0), Color.BLUE)
        # The transform moves what is drawn, not where a read looks.
        assert_equal(canvas.pixel((50, 20)), Color.BLUE)
        assert_equal(canvas.pixel((0, 0)), _GRAY)
    assert_equal(canvas.pixel((150, 0)), Color.TRANSPARENT)
    assert_equal(canvas.pixel((0, -60)), Color.TRANSPARENT)


def test_a_read_is_at_design_size_on_a_bigger_window() raises -> None:
    var context = Context()
    var canvas = _canvas(context, 400, 200)
    canvas.background(Color.RED)
    _square(canvas, (0, 0), Color.BLUE)
    var shot = canvas.snapshot()
    assert_equal(shot.width, 200)
    assert_equal(shot.height, 100)
    assert_equal(shot.pixel(100, 50), Color.BLUE)
    assert_equal(shot.pixel(5, 5), Color.RED)
    var sharp = canvas.snapshot(scale=canvas.scale)
    assert_equal(sharp.width, 400)
    assert_equal(sharp.pixel(200, 100), Color.BLUE)


def test_a_region_snapshot_is_upright_and_clear_off_screen() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    canvas.background(Color.RED)
    _square(canvas, (50, 0), Color.BLUE)
    var tile = canvas.snapshot(Rectangle((50, 0), 40, 40))
    assert_equal(tile.width, 40)
    assert_equal(tile.height, 40)
    assert_equal(tile.pixel(20, 20), Color.BLUE)
    assert_equal(tile.pixel(2, 2), Color.RED)
    # Top-left in image coordinates is the region's top-left on screen.
    _square(canvas, (-70, 30), Color.GREEN)
    var corner = canvas.snapshot(Rectangle((-80, 40), 20, 20))
    assert_equal(corner.pixel(18, 18), Color.GREEN)
    assert_equal(corner.pixel(2, 2), Color.RED)
    var edge = canvas.snapshot(Rectangle((100, 0), 40, 40))
    assert_equal(edge.pixel(5, 20), Color.RED)
    assert_equal(edge.pixel(30, 20), Color.TRANSPARENT)


def test_a_snapshot_keeps_what_it_read() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    canvas.background(Color.RED)
    var before = canvas.snapshot()
    canvas.background(Color.BLUE)
    assert_equal(before.pixel(100, 50), Color.RED)
    assert_equal(canvas.snapshot().pixel(100, 50), Color.BLUE)


def test_bad_snapshot_arguments_raise() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    var raised = False
    try:
        _ = canvas.snapshot(scale=0.0)
    except:
        raised = True
    assert_true(raised, "a zero scale")
    raised = False
    try:
        _ = canvas.snapshot(Rectangle((0, 0), 0, 10))
    except:
        raised = True
    assert_true(raised, "an empty region")


def test_a_snapshot_drawn_back_lines_up_with_the_frame() raises -> None:
    var context = Context()
    var canvas = _canvas(context, 400, 200)
    canvas.background(Color.RED)
    _square(canvas, (30, -10), Color.BLUE)
    var shot = canvas.snapshot()
    canvas.background(Color.GREEN)
    canvas.image(shot, (0, 0), canvas.width, canvas.height)
    var mem = MemorySurface(400, 200)
    _ = _present(context, canvas^, mem)
    # Screen (30, -10) is window pixel (260, 120) at 2x.
    assert_equal(mem.pixel(260, 120), Color.BLUE)
    assert_equal(mem.pixel(10, 10), Color.RED)


def test_with_the_autoclear_off_reads_start_from_the_last_frame() raises -> (
    None
):
    var context = Context()
    var mem = MemorySurface(200, 100)
    var canvas = _canvas(context)
    canvas.autoclear(False)
    canvas.background(Color.RED)
    # The first read switches keeping frames on; it sees only this frame.
    assert_equal(canvas.pixel((0, 0)), Color.RED)
    canvas = _present(context, canvas^, mem)
    # Nothing drawn yet, but the frame starts from the red one, and so does
    # the read.
    assert_equal(canvas.pixel((0, 0)), Color.RED)
    _square(canvas, (0, 0), Color.BLUE)
    assert_equal(canvas.pixel((0, 0)), Color.BLUE)
    assert_equal(canvas.pixel((50, 0)), Color.RED)
    canvas = _present(context, canvas^, mem)
    assert_equal(canvas.snapshot().pixel(100, 50), Color.BLUE)


def test_with_the_autoclear_on_reads_start_clear() raises -> None:
    var context = Context()
    var mem = MemorySurface(200, 100)
    var canvas = _canvas(context)
    canvas.background(Color.RED)
    _ = canvas.pixel((0, 0))
    canvas = _present(context, canvas^, mem)
    assert_equal(canvas.pixel((0, 0)), _GRAY)


def test_clear_starts_the_frame_over() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    canvas.background(Color.RED)
    _square(canvas, (0, 0), Color.BLUE)
    canvas.clear()
    assert_equal(canvas.pixel((0, 0)), _GRAY, "the autoclear again")
    _square(canvas, (50, 0), Color.BLUE)
    assert_equal(canvas.pixel((50, 0)), Color.BLUE)


def test_with_the_autoclear_off_clear_returns_to_the_last_frame() raises -> (
    None
):
    var context = Context()
    var mem = MemorySurface(200, 100)
    var canvas = _canvas(context)
    canvas.autoclear(False)
    canvas.background(Color.RED)
    canvas = _present(context, canvas^, mem)
    _square(canvas, (0, 0), Color.BLUE)
    canvas.clear()
    canvas = _present(context, canvas^, mem)
    assert_equal(mem.pixel(100, 50), Color.RED)


def test_image_pixels_read_in_image_coordinates() raises -> None:
    var buffer = PixelBuffer(3, 2)
    buffer.set(2, 1, Color.RED)
    var s = Image(buffer^)
    assert_equal(s.pixel(2, 1), Color.RED)
    assert_equal(s.pixel(0, 0), Color.TRANSPARENT)
    # Outside the image reads are transparent.
    assert_equal(s.pixel(3, 0), Color.TRANSPARENT)
    assert_equal(s.pixel(-1, 0), Color.TRANSPARENT)


def test_images_built_from_buffers_draw_their_own_pixels() raises -> None:
    var context = Context()
    var canvas = _canvas(context)
    var red = PixelBuffer(10, 10)
    var blue = PixelBuffer(10, 10)
    for y in range(10):
        for x in range(10):
            red.set(x, y, Color.RED)
            blue.set(x, y, Color.BLUE)
    canvas.image(Image(red^), (-30, 0))
    canvas.image(Image(blue^), (30, 0))
    assert_equal(canvas.pixel((-30, 0)), Color.RED)
    assert_equal(canvas.pixel((30, 0)), Color.BLUE)


def test_an_image_drawn_every_frame_is_interned_once() raises -> None:
    var context = Context()
    var mem = MemorySurface(200, 100)
    var canvas = _canvas(context)
    var image = Image.solid(10, 10, 255, 0, 0)
    for _ in range(3):
        canvas.image(image, (0, 0))
        canvas = _present(context, canvas^, mem)
    assert_equal(len(canvas._state.backend.images), 1)


@fieldwise_init
struct DrawsASnapshotBack(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> DrawsASnapshotBack:
        return DrawsASnapshotBack(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.RED)
        _square(canvas, (30, -10), Color.BLUE)
        var shot = canvas.snapshot()
        canvas.background(Color.GREEN)
        canvas.image(shot, (0, 0), canvas.width, canvas.height)


def test_the_gpu_backend_reads_and_draws_back_the_same() raises -> None:
    var m: MemorySurface
    try:
        m = run_headless[DrawsASnapshotBack](
            200, 100, frames=3, backend=RenderBackend.GPU
        )
    except e:
        print("SKIP — no GL context:", e)
        return
    assert_equal(m.pixel(130, 60), Color.BLUE)
    assert_equal(m.pixel(5, 5), Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
