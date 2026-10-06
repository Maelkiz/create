# `run_headless` re-derives the mapping every frame, as the windowed loops do,
# so a dial turned in one frame reaches the next one.

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.text.font import fallback_font_path


@fieldwise_init
struct ExtendAfterFirst(Program):
    """Fills the design area blue, and switches to `EXTEND` during frame 1,
    which `create` draws."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> ExtendAfterFirst:
        canvas.background(Color.BLUE)
        context.autoscale(AutoScale.EXTEND)
        return ExtendAfterFirst(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)


def test_autoscale_set_in_create_applies_from_the_next_frame() raises -> None:
    # A 100x50 design in a 100x100 buffer: FIT leaves 25 rows of bar top and
    # bottom, EXTEND grows the world into them.
    var first = run_headless[ExtendAfterFirst](
        100, 50, 0, 100, 100, antialiasing=Antialiasing.OFF
    )
    assert_equal(first.pixel(50, 5), Color.BLACK)
    var second = run_headless[ExtendAfterFirst](
        100, 50, 1, 100, 100, antialiasing=Antialiasing.OFF
    )
    assert_equal(second.pixel(50, 5), Color.BLUE)
    assert_equal(second.pixel(50, 95), Color.BLUE)


@fieldwise_init
struct DrawsInCreate(Program):
    """Draws a red square in `create` and nothing in `update`."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> DrawsInCreate:
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.rectangle((0, 0), 20, 20)
        return DrawsInCreate(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


def test_create_draws_the_first_frame() raises -> None:
    var m = run_headless[DrawsInCreate](
        100, 100, 0, antialiasing=Antialiasing.OFF
    )
    assert_equal(m.pixel(50, 50), Color.RED)
    # Frame 2 opens with the clear, like any other frame.
    var next = run_headless[DrawsInCreate](
        100, 100, 1, antialiasing=Antialiasing.OFF
    )
    assert_equal(next.pixel(50, 50), Color(200, 200, 200))


@fieldwise_init
struct CountsFrames(Program):
    """Green if `create` saw frame 1 and the first `update` frame 2."""

    var created_on: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> CountsFrames:
        return CountsFrames(context.frame_count())

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        if self.created_on == 1 and context.frame_count() == 2:
            canvas.background(Color.GREEN)
        else:
            canvas.background(Color.RED)


def test_create_is_frame_one_and_the_first_update_frame_two() raises -> None:
    var m = run_headless[CountsFrames](10, 10, 1)
    assert_equal(m.pixel(5, 5), Color.GREEN)


@fieldwise_init
struct Labelled[set_font: Bool](Program):
    """Writes a label each `update`; sets a font in `create` if asked."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Self:
        comptime if Self.set_font:
            # The symbols face has no Latin glyphs, so the label renders
            # differently under it — or not at all.
            canvas.font(Font(fallback_font_path(), 24))
        return Self(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.WHITE)
        canvas.text("Hello", (0, 0))


def test_a_font_set_in_create_lasts_into_update() raises -> None:
    var default_face = run_headless[Labelled[False]](100, 40, 1)
    var set_face = run_headless[Labelled[True]](100, 40, 1)
    var differing = 0
    for y in range(40):
        for x in range(100):
            if default_face.pixel(x, y) != set_face.pixel(x, y):
                differing += 1
    assert_true(differing > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
