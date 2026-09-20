"""The per-frame clear: its default, its opt-out, and its coalescing.

`autoclear` records a `CMD_CLEAR` at the head of every frame, so an unstyled
sketch draws onto a light surface rather than onto whatever the framebuffer
happened to hold. Turning it off is what a program that accumulates ink across
frames does, and an opaque `background()` replaces the clear rather than
stacking a second full-framebuffer paint on it.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.render.frame import Frame, PersistentFrameState


@fieldwise_init
struct DrawsNothing(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> DrawsNothing:
        return DrawsNothing(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        pass


@fieldwise_init
struct NoAutoclear(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> NoAutoclear:
        frame.autoclear = False
        return NoAutoclear(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        pass


@fieldwise_init
struct InkOnFirstFrameOnly(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> InkOnFirstFrameOnly:
        frame.autoclear = False
        return InkOnFirstFrameOnly(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        # `_tick` runs before `update`, so the first frame is count 1.
        if frame.time.frame_count > 1:
            return
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle((0, 0), 40, 40)


@fieldwise_init
struct OwnBackground(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> OwnBackground:
        return OwnBackground(0)

    def update(mut self, mut frame: Frame, input: Input) raises:
        frame.background(Color.BLUE)


def test_a_frame_starts_cleared_to_the_default_gray() raises -> None:
    var m = run_headless[DrawsNothing](200, 100)
    assert_equal(m.pixel(100, 50), Color(200))


def test_autoclear_off_leaves_the_buffer_untouched() raises -> None:
    var m = run_headless[NoAutoclear](200, 100)
    assert_equal(m.pixel(100, 50), Color.TRANSPARENT)


def test_autoclear_off_lets_ink_survive_later_frames() raises -> None:
    # Drawn on frame 1 only; with no clear it is still there four frames on.
    var m = run_headless[InkOnFirstFrameOnly](200, 100, frames=5)
    assert_equal(m.pixel(100, 50), Color.RED)


def test_a_program_background_wins_over_the_autoclear() raises -> None:
    var m = run_headless[OwnBackground](200, 100)
    assert_equal(m.pixel(100, 50), Color.BLUE)


def test_an_opaque_background_replaces_the_autoclear() raises -> None:
    var state = PersistentFrameState()
    state._set_viewport(200, 100)
    var frame = Frame(state^)
    frame.background(Color.BLUE)
    var out = frame^._release()
    assert_equal(len(out.backend.commands), 1)


def test_a_translucent_background_keeps_both() raises -> None:
    # It blends with what the clear painted, so the clear has to survive.
    var state = PersistentFrameState()
    state._set_viewport(200, 100)
    var frame = Frame(state^)
    frame.background(Color(0x11, 0x11, 0x11, 24))
    var out = frame^._release()
    assert_equal(len(out.backend.commands), 2)


def test_autoclear_records_nothing_when_off() raises -> None:
    var state = PersistentFrameState()
    state._set_viewport(200, 100)
    state.autoclear = False
    var frame = Frame(state^)
    var out = frame^._release()
    assert_equal(len(out.backend.commands), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
