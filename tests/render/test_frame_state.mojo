"""What a `Frame` carries across the frame boundary, and what it must not.

A `Frame` is rebuilt every frame from a `PersistentFrameState`, so each field
is either read-only for the program, written back by `_release`, or dropped.
These check that split directly, plus the one thing the frame handed to
`create` must not do: leak its recording into frame 1.
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


def _state(pixel_w: Int, pixel_h: Int) raises -> PersistentFrameState:
    var state = PersistentFrameState()
    state._set_viewport(pixel_w, pixel_h)
    return state^


def test_framerate_is_zero_before_the_first_tick() raises -> None:
    var frame = Frame(_state(800, 600)^)
    assert_equal(frame.framerate(), 0.0)


def test_framerate_is_the_inverse_of_delta() raises -> None:
    var state = _state(800, 600)
    state.time._start(0)
    state.time._tick(20)
    var frame = Frame(state^)
    assert_almost_equal(frame.framerate(), 50.0)


def test_frame_cap_is_written_back_to_the_state() raises -> None:
    var frame = Frame(_state(800, 600)^)
    frame.frame_cap(30)
    var state = frame^._release()
    assert_equal(state._fps_cap, 30)


def test_frame_cap_rejects_non_positive_fps() raises -> None:
    var frame = Frame(_state(800, 600)^)
    with assert_raises(contains="fps must be positive"):
        frame.frame_cap(0)
    with assert_raises(contains="fps must be positive"):
        frame.frame_cap(-5)


def test_quit_is_written_back_to_the_state() raises -> None:
    var frame = Frame(_state(800, 600)^)
    frame.quit()
    var state = frame^._release()
    assert_true(state._quit)


def test_release_does_not_write_the_viewport_back() raises -> None:
    # The loop owns the mapping — a frame that wrote its copy back would undo
    # a resize the loop handled while the frame was being drawn.
    var frame = Frame(_state(800, 600)^)
    frame.view.set_size(1600, 1200)
    var state = frame^._release()
    assert_equal(state.view.pixel_w, 800)
    assert_equal(state.view.pixel_h, 600)


def test_design_takes_effect_on_the_next_frame() raises -> None:
    # `design` writes through to the state, so the frame that called it keeps
    # reporting the size it was built with; the loop's next `_set_viewport`
    # is what publishes the new mapping.
    var frame = Frame(_state(1600, 1200)^)
    frame.design(800, 600)
    assert_equal(frame.width, 1600)
    var state = frame^._release()
    assert_equal(state.autoscale, AutoScale.FIT)
    state._set_viewport(1600, 1200)
    var next = Frame(state^)
    assert_equal(next.width, 800)
    assert_equal(next.height, 600)
    assert_almost_equal(next.scale, 2.0)


def test_design_overrides_an_earlier_design() raises -> None:
    var frame = Frame(_state(2000, 1000)^)
    frame.design(800, 600)
    frame.design(1000, 500, AutoScale.EXTEND)
    var state = frame^._release()
    state._set_viewport(2000, 1000)
    var next = Frame(state^)
    assert_equal(next.autoscale, AutoScale.EXTEND)
    assert_almost_equal(next.scale, 2.0)
    assert_equal(next.width, 1000)
    assert_equal(next.height, 500)


# --- the frame handed to `create` is never presented ------------------------

comptime _CREATE_IMG = "/tmp/mojo_create_test_create_never_presents.png"


@fieldwise_init
struct DrawsInCreate(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> DrawsInCreate:
        # None of this is ever presented: the frame `create` draws into is
        # discarded, so neither the fill nor the capture may reach frame 1.
        frame.background(Color.RED)
        frame.save_image(_CREATE_IMG)
        return DrawsInCreate(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        pass


def test_create_draws_do_not_reach_the_first_frame() raises -> None:
    var m = run_headless[DrawsInCreate](200, 100)
    assert_equal(m.pixel(100, 50), Color.TRANSPARENT)


def test_a_capture_filed_in_create_writes_no_file() raises -> None:
    _ = run_headless[DrawsInCreate](200, 100)
    with assert_raises():
        _ = Sprite.load(_CREATE_IMG)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
