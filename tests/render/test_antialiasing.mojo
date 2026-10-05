"""CPU antialiasing: a shape's edge pixels take the share of their samples
the shape covers, its fill and outline meet without a seam, and an edge on
the pixel grid comes out as it would without antialiasing.

A 100 x 100 design maps 1:1, its origin at device pixel (50, 50).
"""

from std.math import sqrt
from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless


@fieldwise_init
struct OffGrid[gradient: Bool](Program):
    """A red square whose left edge lies at device x 40.25: a quarter into
    column 40."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> OffGrid[Self.gradient]:
        return OffGrid[Self.gradient](0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        comptime if Self.gradient:
            canvas.fill(Gradient.linear(Color.RED, Color.RED))
        else:
            canvas.fill(Color.RED)
        canvas.rectangle((0.25, 0.0), 20.0, 20.0)


def test_an_edge_off_the_pixel_grid_is_partly_covered() raises -> None:
    # MEDIUM samples 4 x 4 per pixel: three of column 40's four sample
    # columns lie right of 40.25.
    var m = run_headless[OffGrid[False]](100, 100)
    assert_equal(m.pixel(40, 50), Color(191, 0, 0, 255))
    assert_equal(m.pixel(41, 50), Color.RED)
    assert_equal(m.pixel(39, 50), Color.BLACK)
    # Without antialiasing the pixel centre (40.5) decides: all or nothing.
    var hard = run_headless[OffGrid[False]](
        100, 100, antialiasing=Antialiasing.OFF
    )
    assert_equal(hard.pixel(40, 50), Color.RED)


def test_a_gradient_edge_is_partly_covered() raises -> None:
    var m = run_headless[OffGrid[True]](100, 100)
    assert_equal(m.pixel(40, 50), Color(191, 0, 0, 255))
    assert_equal(m.pixel(45, 50), Color.RED)


@fieldwise_init
struct OnGrid(Program):
    """Shapes whose every edge lies on a pixel boundary."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> OnGrid:
        return OnGrid(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.RED)
        canvas.outline(Color.WHITE, 3)
        canvas.rectangle((0.0, 0.0), 40.0, 20.0)
        canvas.rectangle((-30.0, 30.0), 10.0, 10.0)


def test_an_edge_on_the_pixel_grid_is_unchanged() raises -> None:
    var soft = run_headless[OnGrid](100, 100)
    var hard = run_headless[OnGrid](100, 100, antialiasing=Antialiasing.OFF)
    for y in range(100):
        for x in range(100):
            assert_equal(soft.pixel(x, y), hard.pixel(x, y), String(x, ", ", y))


@fieldwise_init
struct SameColorRing(Program):
    """An opaque red disc whose outline is red too, at a radius off the
    pixel grid: inside its outer edge it must be solid red throughout."""

    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> SameColorRing:
        return SameColorRing(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.RED)
        canvas.outline(Color.RED, 3)
        canvas.circle((0.0, 0.0), 30.3)


def test_fill_and_outline_meet_without_a_seam() raises -> None:
    # The outline's inner edge, near radius 27.3, crosses pixels the fill
    # shares with it: each must be fill and outline together, whole.
    var m = run_headless[SameColorRing](100, 100)
    var checked = 0
    for y in range(100):
        for x in range(100):
            var dx = Float64(x) + 0.5 - 50.0
            var dy = Float64(y) + 0.5 - 50.0
            if sqrt(dx * dx + dy * dy) < 29.0:
                assert_equal(m.pixel(x, y), Color.RED, String(x, ", ", y))
                checked += 1
    assert_true(checked > 2000)
    # The outer edge itself is soft: something between black and red.
    var soft = 0
    for x in range(50, 100):
        var r = m.pixel(x, 50).r
        if r > 0 and r < 255:
            soft += 1
    assert_true(soft >= 1, "the outer edge came out hard")


def test_antialiasing_writes_its_constant_name() raises -> None:
    assert_equal(String(Antialiasing.OFF), "Antialiasing.OFF")
    assert_equal(String(Antialiasing.HIGH), "Antialiasing.HIGH")
    assert_equal(String(Antialiasing(9)), "Antialiasing(9)")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
