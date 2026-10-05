"""`Context`'s own bookkeeping: the frame count, the frame rate derived from
the clock, the dials the loop reads after `update` returns, and reading every
dial back."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
    assert_true,
)

from create.color import Color
from create.core.context import Context
from create.render import AutoScale


def test_frame_count_is_zero_before_the_first_frame() raises -> None:
    assert_equal(Context().frame_count(), 0)


def test_advancing_a_frame_counts_it_and_ticks_the_clock() raises -> None:
    var context = Context()
    context.time._start(1_000)
    context._advance_frame(1_016)
    assert_equal(context.frame_count(), 1)
    assert_equal(context.time.delta_millis, 16)
    context._advance_frame(1_048)
    assert_equal(context.frame_count(), 2)


def test_frame_rate_is_zero_before_the_first_tick() raises -> None:
    assert_equal(Context().frame_rate(), 0.0)


def test_frame_rate_is_the_inverse_of_delta() raises -> None:
    var context = Context()
    context.time._start(0)
    context.time._tick(20)
    assert_almost_equal(context.frame_rate(), 50.0)


def test_max_frame_rate_is_recorded_on_the_context() raises -> None:
    var context = Context()
    context.max_frame_rate(30)
    assert_equal(context.max_frame_rate(), 30)


def test_max_frame_rate_rejects_non_positive_fps() raises -> None:
    var context = Context()
    with assert_raises(contains="fps must be positive"):
        context.max_frame_rate(0)
    with assert_raises(contains="fps must be positive"):
        context.max_frame_rate(-5)


def test_quit_is_recorded_on_the_context() raises -> None:
    var context = Context()
    context.quit()
    assert_true(context._quit)


def test_dials_read_back_their_defaults() raises -> None:
    var context = Context()
    assert_true(context.autoscale() == AutoScale.FIT)
    assert_true(context.quit_on_escape())
    assert_equal(context.max_frame_rate(), 0)


def test_dials_read_back_what_was_set() raises -> None:
    var context = Context()
    context.design_size(800, 600)
    context.autoscale(AutoScale.EXTEND)
    context.quit_on_escape(False)
    var size = context.design_size()
    assert_equal(size[0], 800)
    assert_equal(size[1], 600)
    assert_true(context.autoscale() == AutoScale.EXTEND)
    assert_true(not context.quit_on_escape())


def test_window_dials_read_back_what_was_set() raises -> None:
    var context = Context()
    assert_equal(context.title(), "")
    assert_true(context.resizable())
    context.title("Score: 3")
    context.resizable(False)
    assert_equal(context.title(), "Score: 3")
    assert_true(not context.resizable())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
