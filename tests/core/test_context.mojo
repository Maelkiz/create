"""`Context`'s own bookkeeping: the frame count, the frame rate derived from
the clock, and the dials the loop reads after `update` returns."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
    assert_true,
)

from create.core.context import Context


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
    assert_equal(context._max_frame_rate, 30)


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
