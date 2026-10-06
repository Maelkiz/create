"""`PixelBuffer`: pixels built one at a time, then taken over by an
`Image`."""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless


def test_a_new_buffer_is_transparent() raises -> None:
    var buffer = PixelBuffer(3, 2)
    assert_equal(buffer.width, 3)
    assert_equal(buffer.height, 2)
    for y in range(2):
        for x in range(3):
            assert_equal(buffer.pixel(x, y), Color.TRANSPARENT)


def test_set_then_pixel_round_trips() raises -> None:
    var buffer = PixelBuffer(3, 2)
    buffer.set(2, 1, Color.RED)
    buffer.set(0, 0, Color(1, 2, 3, 4))
    assert_equal(buffer.pixel(2, 1), Color.RED)
    assert_equal(buffer.pixel(0, 0), Color(1, 2, 3, 4))
    assert_equal(buffer.pixel(1, 1), Color.TRANSPARENT)


def test_off_the_buffer_reads_are_transparent_and_writes_do_nothing() raises -> (
    None
):
    var buffer = PixelBuffer(3, 2)
    buffer.set(-1, 0, Color.RED)
    buffer.set(3, 0, Color.RED)
    buffer.set(0, 2, Color.RED)
    assert_equal(buffer.pixel(-1, 0), Color.TRANSPARENT)
    assert_equal(buffer.pixel(0, 2), Color.TRANSPARENT)
    for y in range(2):
        for x in range(3):
            assert_equal(buffer.pixel(x, y), Color.TRANSPARENT)


def test_an_image_takes_the_buffer_over() raises -> None:
    var buffer = PixelBuffer(3, 2)
    buffer.set(2, 1, Color.RED)
    var image = Image(buffer^)
    assert_equal(image.width, 3)
    assert_equal(image.height, 2)
    assert_equal(image.pixel(2, 1), Color.RED)
    assert_equal(image.pixel(0, 0), Color.TRANSPARENT)


def test_each_image_has_its_own_identity() raises -> None:
    var a = Image(PixelBuffer(1, 1))
    var b = Image(PixelBuffer(1, 1))
    assert_true(a._id != b._id)


@fieldwise_init
struct DrawsABuiltImage(Program):
    var image: Image

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> DrawsABuiltImage:
        var buffer = PixelBuffer(20, 20)
        for y in range(20):
            for x in range(10):
                buffer.set(x, y, Color.BLUE)
        return DrawsABuiltImage(Image(buffer^))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.RED)
        canvas.image(self.image, (0, 0))


def test_a_built_image_draws() raises -> None:
    # 200 x 100 design: the image spans pixels 90..110 across, 40..60 down,
    # its left half blue and its right half clear.
    var m = run_headless[DrawsABuiltImage](200, 100, frames=1)
    assert_equal(m.pixel(95, 50), Color.BLUE)
    assert_equal(m.pixel(105, 50), Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
