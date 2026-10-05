"""The offscreen canvas: a `Canvas(width, height)` a program builds, draws
into and reads back, outside any run loop.

A 100 x 60 canvas: screen x in -50..50, y in -30..30, y up.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from create import *


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
