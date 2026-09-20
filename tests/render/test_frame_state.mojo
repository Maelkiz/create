"""What a `Frame` carries across the frame boundary, and what it must not.

A `Frame` is rebuilt every frame from a `PersistentFrameState` and the
program's `Options`, so each field is either read-only for the program,
written back by `_release`, or dropped. The dials themselves outlive the
frame in `Options`, which the loop reads at frame construction — so a dial
set mid-`update` applies to the *next* frame. These check that split
directly.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
    assert_true,
)

from create import *
from create.render.frame import Frame, PersistentFrameState


def _state(
    options: Options, pixel_w: Int, pixel_h: Int
) raises -> PersistentFrameState:
    var state = PersistentFrameState()
    state._set_viewport(options, pixel_w, pixel_h)
    return state^


def test_framerate_is_zero_before_the_first_tick() raises -> None:
    var options = Options()
    var frame = Frame(_state(options, 800, 600)^, options)
    assert_equal(frame.framerate(), 0.0)


def test_framerate_is_the_inverse_of_delta() raises -> None:
    var options = Options()
    var state = _state(options, 800, 600)
    state.time._start(0)
    state.time._tick(20)
    var frame = Frame(state^, options)
    assert_almost_equal(frame.framerate(), 50.0)


def test_frame_cap_is_recorded_on_the_options() raises -> None:
    var options = Options()
    options.frame_cap(30)
    assert_equal(options._fps_cap, 30)


def test_frame_cap_rejects_non_positive_fps() raises -> None:
    var options = Options()
    with assert_raises(contains="fps must be positive"):
        options.frame_cap(0)
    with assert_raises(contains="fps must be positive"):
        options.frame_cap(-5)


def test_quit_is_recorded_on_the_options() raises -> None:
    var options = Options()
    options.quit()
    assert_true(options._quit)


def test_release_does_not_write_the_viewport_back() raises -> None:
    # The loop owns the mapping — a frame that wrote its copy back would undo
    # a resize the loop handled while the frame was being drawn.
    var options = Options()
    var frame = Frame(_state(options, 800, 600)^, options)
    frame.view.set_size(1600, 1200)
    var state = frame^._release()
    assert_equal(state.view.pixel_w, 800)
    assert_equal(state.view.pixel_h, 600)


def test_design_takes_effect_on_the_next_frame() raises -> None:
    # `design_resolution` writes to the options, so the frame already built
    # keeps reporting the size it was built with; the loop's next
    # `_set_viewport` is what publishes the new mapping.
    var options = Options()
    var state = _state(options, 1600, 1200)
    var frame = Frame(state^, options)
    options.design_resolution(800, 600)
    assert_equal(frame.width, 1600)
    state = frame^._release()
    assert_equal(options.autoscale, AutoScale.FIT)
    state._set_viewport(options, 1600, 1200)
    var next = Frame(state^, options)
    assert_equal(next.width, 800)
    assert_equal(next.height, 600)
    assert_almost_equal(next.scale, 2.0)


def test_design_overrides_an_earlier_design() raises -> None:
    var options = Options()
    var state = _state(options, 2000, 1000)
    options.design_resolution(800, 600)
    options.design_resolution(1000, 500, AutoScale.EXTEND)
    state._set_viewport(options, 2000, 1000)
    var next = Frame(state^, options)
    assert_equal(next.view.autoscale, AutoScale.EXTEND)
    assert_almost_equal(next.scale, 2.0)
    assert_equal(next.width, 1000)
    assert_equal(next.height, 500)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
