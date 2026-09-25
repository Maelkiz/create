from std.testing import TestSuite, assert_equal, assert_almost_equal
from create.render.time import Time


def _started(now: Int) raises -> Time:
    var t = Time()
    t._start(now)
    return t^


def test_fresh_time_is_zeroed() raises -> None:
    var t = Time()
    assert_equal(t.frame_count, 0)
    assert_equal(t.delta, 0.0)
    assert_equal(t.delta_millis, 0)
    assert_equal(t.elapsed, 0.0)


def test_first_tick_measures_from_the_seed_not_the_epoch() raises -> None:
    # The regression this struct exists to prevent: the window clock counts
    # from process start, so an unseeded Time would report 900_016ms here.
    var t = _started(900_000)
    t._tick(900_016)
    assert_equal(t.delta_millis, 16)
    assert_almost_equal(t.delta, 0.016)


def test_first_tick_counts_as_frame_one() raises -> None:
    var t = _started(900_000)
    t._tick(900_016)
    assert_equal(t.frame_count, 1)


def test_delta_is_millis_in_seconds() raises -> None:
    var t = _started(0)
    t._tick(250)
    assert_almost_equal(t.delta, 0.25)
    assert_equal(t.delta_millis, 250)


def test_delta_spans_only_the_last_frame() raises -> None:
    var t = _started(1_000)
    t._tick(1_016)
    t._tick(1_048)
    assert_equal(t.delta_millis, 32)
    assert_almost_equal(t.delta, 0.032)


def test_elapsed_accumulates_across_frames() raises -> None:
    var t = _started(1_000)
    t._tick(1_016)
    t._tick(1_048)
    t._tick(1_064)
    assert_almost_equal(t.elapsed, 0.064)
    assert_equal(t.frame_count, 3)


def test_elapsed_tracks_total_span_since_the_seed() raises -> None:
    # Summing deltas and differencing the endpoints must agree, so a sketch
    # can use `elapsed` in place of its own accumulator without drifting.
    var t = _started(5_000)
    t._tick(5_010)
    t._tick(5_037)
    t._tick(5_100)
    assert_almost_equal(t.elapsed, 0.100)


def test_zero_length_frame_is_harmless() raises -> None:
    # Two ticks inside the same millisecond: the clock has 1ms resolution, so
    # a fast frame legitimately reports no elapsed time.
    var t = _started(2_000)
    t._tick(2_000)
    assert_equal(t.delta_millis, 0)
    assert_equal(t.delta, 0.0)
    assert_equal(t.frame_count, 1)
    assert_equal(t.elapsed, 0.0)


def test_restart_rebases_without_disturbing_totals() raises -> None:
    var t = _started(0)
    t._tick(16)
    t._start(10_000)
    t._tick(10_016)
    assert_equal(t.delta_millis, 16)
    assert_almost_equal(t.elapsed, 0.032)
    assert_equal(t.frame_count, 2)


def test_time_writes_its_public_fields() raises -> None:
    var t = Time()
    t._start(1000)
    t._tick(1250)
    assert_equal(
        String(t),
        (
            "Time(frame_count=1, delta=0.25, delta_millis=250, elapsed=0.25,"
            " elapsed_millis=250)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
