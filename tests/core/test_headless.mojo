# `run_headless` re-derives the mapping every frame, as the windowed loops do,
# so a dial turned in one frame reaches the next one.

from std.testing import TestSuite, assert_equal

from create import *


@fieldwise_init
struct ExtendAfterFirst(Program):
    """Fills the design area blue, and switches to `EXTEND` during frame 1."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ExtendAfterFirst:
        return ExtendAfterFirst(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)
        if context.frame_count() == 1:
            context.autoscale(AutoScale.EXTEND)


def test_autoscale_set_in_update_applies_from_the_next_frame() raises -> None:
    # A 100x50 design in a 100x100 buffer: FIT leaves 25 rows of bar top and
    # bottom, EXTEND grows the world into them.
    var first = run_headless[ExtendAfterFirst](
        100, 50, 1, 100, 100, antialiasing=Antialiasing.OFF
    )
    assert_equal(first.pixel(50, 5), Color.BLACK)
    var second = run_headless[ExtendAfterFirst](
        100, 50, 2, 100, 100, antialiasing=Antialiasing.OFF
    )
    assert_equal(second.pixel(50, 5), Color.BLUE)
    assert_equal(second.pixel(50, 95), Color.BLUE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
