from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
    assert_false,
)
from create.math.easing import Easing, ease
from create.math.tween import Tween


# --- ease: endpoints ---------------------------------------------------------
# Every curve must pin 0 to 0 and 1 to 1, whatever it does between.


def _all_curves() -> List[Easing]:
    return [
        Easing.LINEAR,
        Easing.IN_QUAD,
        Easing.OUT_QUAD,
        Easing.IN_OUT_QUAD,
        Easing.IN_CUBIC,
        Easing.OUT_CUBIC,
        Easing.IN_OUT_CUBIC,
        Easing.IN_SINE,
        Easing.OUT_SINE,
        Easing.IN_OUT_SINE,
        Easing.IN_EXPO,
        Easing.OUT_EXPO,
        Easing.IN_OUT_EXPO,
        Easing.IN_BACK,
        Easing.OUT_BACK,
        Easing.IN_OUT_BACK,
        Easing.IN_ELASTIC,
        Easing.OUT_ELASTIC,
        Easing.IN_OUT_ELASTIC,
        Easing.IN_BOUNCE,
        Easing.OUT_BOUNCE,
        Easing.IN_OUT_BOUNCE,
    ]


def test_ease_every_curve_starts_at_zero() raises -> None:
    for curve in _all_curves():
        assert_almost_equal(ease(curve, 0.0), 0.0, atol=1e-9)


def test_ease_every_curve_ends_at_one() raises -> None:
    for curve in _all_curves():
        assert_almost_equal(ease(curve, 1.0), 1.0, atol=1e-9)


def test_ease_every_curve_is_finite_across_the_run() raises -> None:
    for curve in _all_curves():
        for i in range(101):
            var v = ease(curve, Float64(i) / 100.0)
            assert_true(v == v, "curve produced NaN")
            assert_true(v > -10.0 and v < 10.0, "curve left a sane range")


# --- ease: shape -------------------------------------------------------------


def test_ease_linear_is_identity() raises -> None:
    assert_equal(ease(Easing.LINEAR, 0.25), 0.25)
    assert_equal(ease(Easing.LINEAR, 0.75), 0.75)


def test_ease_in_curves_start_slow() raises -> None:
    assert_true(ease(Easing.IN_QUAD, 0.5) < 0.5)
    assert_true(ease(Easing.IN_CUBIC, 0.5) < 0.5)
    assert_true(ease(Easing.IN_SINE, 0.5) < 0.5)
    assert_true(ease(Easing.IN_EXPO, 0.5) < 0.5)


def test_ease_out_curves_start_fast() raises -> None:
    assert_true(ease(Easing.OUT_QUAD, 0.5) > 0.5)
    assert_true(ease(Easing.OUT_CUBIC, 0.5) > 0.5)
    assert_true(ease(Easing.OUT_SINE, 0.5) > 0.5)
    assert_true(ease(Easing.OUT_EXPO, 0.5) > 0.5)


def test_ease_in_out_curves_are_symmetric_about_the_midpoint() raises -> None:
    for curve in [
        Easing.IN_OUT_QUAD,
        Easing.IN_OUT_CUBIC,
        Easing.IN_OUT_SINE,
        Easing.IN_OUT_EXPO,
        Easing.IN_OUT_BACK,
        Easing.IN_OUT_BOUNCE,
    ]:
        assert_almost_equal(ease(curve, 0.5), 0.5, atol=1e-9)
        assert_almost_equal(
            ease(curve, 0.25) + ease(curve, 0.75), 1.0, atol=1e-9
        )


def test_ease_quad_matches_its_formula() raises -> None:
    assert_almost_equal(ease(Easing.IN_QUAD, 0.4), 0.16)
    assert_almost_equal(ease(Easing.OUT_QUAD, 0.4), 0.64)


def test_ease_cubic_matches_its_formula() raises -> None:
    assert_almost_equal(ease(Easing.IN_CUBIC, 0.5), 0.125)
    assert_almost_equal(ease(Easing.OUT_CUBIC, 0.5), 0.875)


def test_ease_back_overshoots_past_the_end() raises -> None:
    """Documented behaviour: BACK leaves 0..1 mid-run and must be clamped by
    anything consuming it as a channel or an index."""
    assert_true(ease(Easing.OUT_BACK, 0.6) > 1.0)
    assert_true(ease(Easing.IN_BACK, 0.4) < 0.0)


def test_ease_elastic_overshoots_both_ways() raises -> None:
    """Elastic oscillates, so it leaves 0..1 repeatedly rather than at one
    known point -- scan the run instead of naming a sample."""
    var out_above = False
    var in_below = False
    for i in range(101):
        var x = Float64(i) / 100.0
        if ease(Easing.OUT_ELASTIC, x) > 1.0:
            out_above = True
        if ease(Easing.IN_ELASTIC, x) < 0.0:
            in_below = True
    assert_true(out_above)
    assert_true(in_below)


def test_ease_bounce_stays_inside_zero_to_one() raises -> None:
    for i in range(101):
        var v = ease(Easing.OUT_BOUNCE, Float64(i) / 100.0)
        assert_true(v >= 0.0 and v <= 1.0)


# --- ease: clamping ----------------------------------------------------------


def test_ease_clamps_below_zero() raises -> None:
    assert_equal(ease(Easing.IN_QUAD, -1.0), 0.0)
    assert_almost_equal(ease(Easing.OUT_EXPO, -3.0), 0.0, atol=1e-9)


def test_ease_clamps_above_one() raises -> None:
    """`IN_EXPO` at t = 2 would be 1024 unclamped."""
    assert_almost_equal(ease(Easing.IN_EXPO, 2.0), 1.0, atol=1e-9)
    assert_equal(ease(Easing.IN_QUAD, 5.0), 1.0)


def test_ease_unknown_curve_passes_the_fraction_through() raises -> None:
    assert_equal(ease(Easing(999), 0.3), 0.3)


def test_easing_equality() raises -> None:
    assert_true(Easing.OUT_CUBIC == Easing.OUT_CUBIC)
    assert_true(Easing.OUT_CUBIC != Easing.IN_CUBIC)


# --- Tween: construction -----------------------------------------------------


def test_tween_starts_stopped_at_start() raises -> None:
    var t = Tween(10.0, 20.0, 1.0)
    assert_equal(t.value, 10.0)
    assert_equal(t.progress, 0.0)
    assert_false(t.is_playing())
    assert_false(t.is_finished())


def test_tween_does_not_move_until_played() raises -> None:
    var t = Tween(10.0, 20.0, 1.0)
    t.update(0.5)
    assert_equal(t.value, 10.0)


def test_tween_duration_only_runs_zero_to_one() raises -> None:
    var t = Tween(1.0)
    assert_equal(t.start, 0.0)
    assert_equal(t.end, 1.0)
    t.play()
    t.update(0.25)
    assert_almost_equal(t.value, 0.25)


def test_tween_defaults_to_linear() raises -> None:
    var t = Tween(1.0)
    assert_true(t.curve == Easing.LINEAR)


# --- Tween: play -------------------------------------------------------------


def test_tween_advances_linearly() raises -> None:
    var t = Tween(0.0, 100.0, 2.0)
    t.play()
    t.update(0.5)
    assert_almost_equal(t.progress, 0.25)
    assert_almost_equal(t.value, 25.0)


def test_tween_applies_its_curve() raises -> None:
    var t = Tween(0.0, 100.0, 1.0, Easing.IN_QUAD)
    t.play()
    t.update(0.5)
    assert_almost_equal(t.progress, 0.5)
    assert_almost_equal(t.value, 25.0)


def test_tween_lands_exactly_on_end() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(0.7)
    t.update(0.7)
    assert_equal(t.progress, 1.0)
    assert_equal(t.value, 100.0)


def test_tween_finishes_and_stops() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(2.0)
    assert_true(t.is_finished())
    assert_false(t.is_playing())


def test_tween_holds_its_end_after_finishing() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(2.0)
    t.update(2.0)
    assert_equal(t.value, 100.0)


def test_tween_play_restarts_from_the_beginning() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(0.6)
    t.play()
    assert_equal(t.progress, 0.0)
    assert_equal(t.value, 0.0)
    assert_true(t.is_playing())


def test_tween_play_clears_finished() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(2.0)
    t.play()
    assert_false(t.is_finished())


def test_tween_runs_backwards_when_end_is_below_start() raises -> None:
    var t = Tween(100.0, 0.0, 1.0)
    t.play()
    t.update(0.25)
    assert_almost_equal(t.value, 75.0)


# --- Tween: pause, resume, stop ----------------------------------------------


def test_tween_pause_freezes_the_value() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(0.3)
    t.pause()
    t.update(0.5)
    assert_almost_equal(t.value, 30.0)
    assert_false(t.is_playing())


def test_tween_resume_continues_without_rewinding() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(0.3)
    t.pause()
    t.resume()
    t.update(0.2)
    assert_almost_equal(t.value, 50.0)


def test_tween_resume_does_not_restart_a_finished_tween() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.play()
    t.update(2.0)
    t.resume()
    assert_false(t.is_playing())


def test_tween_stop_rewinds_to_start() raises -> None:
    var t = Tween(10.0, 20.0, 1.0)
    t.play()
    t.update(0.5)
    t.stop()
    assert_equal(t.progress, 0.0)
    assert_equal(t.value, 10.0)
    assert_false(t.is_playing())


# --- Tween: loop -------------------------------------------------------------


def test_tween_loop_wraps_instead_of_finishing() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.loop()
    t.update(1.25)
    assert_almost_equal(t.progress, 0.25)
    assert_almost_equal(t.value, 25.0)
    assert_true(t.is_playing())
    assert_false(t.is_finished())


def test_tween_loop_keeps_running_over_many_cycles() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.loop()
    for _ in range(100):
        t.update(0.1)
    assert_true(t.is_playing())
    assert_true(t.progress >= 0.0 and t.progress <= 1.0)


# --- Tween: ping_pong --------------------------------------------------------


def test_tween_ping_pong_reverses_at_the_end() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.ping_pong()
    t.update(0.8)
    assert_almost_equal(t.value, 80.0)
    t.update(0.4)
    # 0.2 into the return leg, so back down to 0.8.
    assert_almost_equal(t.progress, 0.8)
    assert_almost_equal(t.value, 80.0)


def test_tween_ping_pong_reverses_again_at_the_start() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.ping_pong()
    t.update(1.5)  # to 1.0, reflected back to 0.5
    t.update(0.7)  # down past 0 to -0.2, reflected up to 0.2
    assert_almost_equal(t.progress, 0.2)
    assert_true(t.is_playing())


def test_tween_ping_pong_never_finishes() raises -> None:
    var t = Tween(0.0, 100.0, 1.0)
    t.ping_pong()
    for _ in range(100):
        t.update(0.13)
        assert_false(t.is_finished())
        assert_true(t.progress >= 0.0 and t.progress <= 1.0)


def test_tween_ping_pong_survives_a_frame_longer_than_its_duration() raises -> (
    None
):
    """A dt past the far end must clamp rather than leave progress outside
    0..1 -- the value would otherwise stop tracking the curve."""
    var t = Tween(0.0, 100.0, 0.1)
    t.ping_pong()
    t.update(5.0)
    assert_true(t.progress >= 0.0 and t.progress <= 1.0)
    assert_true(t.value >= 0.0 and t.value <= 100.0)


# --- write_to -----------------------------------------------------------------


def test_easing_writes_its_constant_name() raises -> None:
    assert_equal(String(Easing.LINEAR), "Easing.LINEAR")
    assert_equal(String(Easing.OUT_BOUNCE), "Easing.OUT_BOUNCE")
    assert_equal(String(Easing.IN_OUT_BOUNCE), "Easing.IN_OUT_BOUNCE")


def test_easing_out_of_range_writes_its_value() raises -> None:
    assert_equal(String(Easing(99)), "Easing(99)")


def test_every_curve_writes_a_name() raises -> None:
    for curve in _all_curves():
        assert_true(String(curve).startswith("Easing."))


def test_tween_writes_its_public_state() raises -> None:
    var t = Tween(0.0, 10.0, 2.0, Easing.OUT_CUBIC)
    t.play()
    assert_equal(
        String(t),
        (
            "Tween(value=0.0, progress=0.0, start=0.0, end=10.0, duration=2.0,"
            " curve=Easing.OUT_CUBIC, playing=True, finished=False)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
