# Regression coverage for post-render clipping and the sized image overload
# — kept out of test_canvas.mojo, already the package's slowest file, since
# both tests here use larger buffers.

from std.testing import TestSuite, assert_equal

from create import *
from create.core.headless import run_headless
from create.render.surface import MemorySurface
from create.image.image import Image


@fieldwise_init
struct OverflowingRect(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> OverflowingRect:
        return OverflowingRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.GREEN)
        # Far larger than the 100x50 design — if the raster loop didn't
        # already clip to the framebuffer, this alone would prove nothing, so
        # the value is entirely in what happens after render.
        canvas.rectangle((0.0, 0.0), 1000.0, 1000.0)


def test_letterbox_clips_a_shape_rendered_past_the_design_edge() raises -> None:
    # 100x50 design in a 100x100 buffer: scale 1, 25-row bars top and bottom.
    # The rect covers every framebuffer pixel, so a bar pixel reading the
    # letterbox colour proves _render_letterbox clips rather than merely fills
    # an otherwise-empty margin.
    var m = run_headless[OverflowingRect](100, 50, 1, 100, 100)
    assert_equal(m.pixel(50, 5), Color.BLACK)
    assert_equal(m.pixel(50, 95), Color.BLACK)
    assert_equal(m.pixel(50, 50), Color.GREEN)


@fieldwise_init
struct RedBarsFromCreate(Program):
    """Sets red bars once in `create`; never touches them again."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> RedBarsFromCreate:
        canvas.letterbox_color(Color.RED)
        canvas.background(Color.GREEN)
        return RedBarsFromCreate(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.GREEN)


def test_a_letterbox_colour_set_in_create_lasts() raises -> None:
    # 100x50 design in a 100x100 buffer: 25-row bars top and bottom.
    var first = run_headless[RedBarsFromCreate](100, 50, 0, 100, 100)
    assert_equal(first.pixel(50, 5), Color.RED)
    assert_equal(first.pixel(50, 50), Color.GREEN)
    var later = run_headless[RedBarsFromCreate](100, 50, 3, 100, 100)
    assert_equal(later.pixel(50, 5), Color.RED)
    assert_equal(later.pixel(50, 95), Color.RED)


@fieldwise_init
struct BarsChangedLate(Program):
    """Turns the bars blue at the end of `update`, after drawing."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> BarsChangedLate:
        return BarsChangedLate(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.GREEN)
        assert_equal(canvas.letterbox_color(), Color.BLACK)
        canvas.letterbox_color(Color.BLUE)


def test_a_letterbox_colour_set_mid_frame_paints_that_frame() raises -> None:
    var m = run_headless[BarsChangedLate](100, 50, 1, 100, 100)
    assert_equal(m.pixel(50, 5), Color.BLUE)


struct ScaledImage(Program):
    var image: Image

    def __init__(out self, var image: Image):
        self.image = image^

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> ScaledImage:
        return ScaledImage(Image.load("tests/fixtures/test_2x2.bmp"))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.image(self.image, (0.0, 0.0), 8, 8)


def test_sized_image_overload_resamples_nearest_neighbour() raises -> None:
    # test_2x2.bmp: top-left red, top-right white, bottom-left blue, bottom-
    # right white (test_image_blits_unflipped's fixture, in test_canvas.mojo).
    # Blown up 4x to an 8x8 destination, each source pixel becomes a sharp 4x4
    # block — nearest-neighbour, so the boundary between blocks is exact
    # rather than blended.
    var m = run_headless[ScaledImage](100, 100)
    assert_equal(m.pixel(46, 46), Color.RED)
    assert_equal(m.pixel(49, 49), Color.RED)
    assert_equal(m.pixel(50, 49), Color.WHITE)
    assert_equal(m.pixel(53, 46), Color.WHITE)
    assert_equal(m.pixel(49, 50), Color.BLUE)
    assert_equal(m.pixel(46, 53), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.WHITE)
    assert_equal(m.pixel(53, 53), Color.WHITE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
