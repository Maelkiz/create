"""The per-frame clear: its default, its opt-out, and its coalescing.

`autoclear` records a `CMD_CLEAR` at the head of every frame, so an unstyled
sketch renders onto a light surface rather than onto whatever the framebuffer
happened to hold. Turning it off is what a program that accumulates ink across
frames does, and an opaque `background()` replaces the clear rather than
stacking a second full-framebuffer paint on it.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.render.canvas import Canvas, PersistentCanvasState


@fieldwise_init
struct RendersNothing(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RendersNothing:
        return RendersNothing(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


@fieldwise_init
struct NoAutoclear(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> NoAutoclear:
        context.autoclear = False
        return NoAutoclear(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


@fieldwise_init
struct InkOnFirstFrameOnly(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> InkOnFirstFrameOnly:
        context.autoclear = False
        return InkOnFirstFrameOnly(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # `_tick` runs before `update`, so the first frame is count 1.
        if context.time.frame_count > 1:
            return
        canvas.outline(enabled=False)
        canvas.fill(Color.RED)
        canvas.rectangle((0, 0), 40, 40)


@fieldwise_init
struct OwnBackground(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> OwnBackground:
        return OwnBackground(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)


def test_a_frame_starts_cleared_to_the_default_gray() raises -> None:
    var m = run_headless[RendersNothing](200, 100)
    assert_equal(m.pixel(100, 50), Color(200))


def test_autoclear_off_leaves_the_buffer_untouched() raises -> None:
    var m = run_headless[NoAutoclear](200, 100)
    assert_equal(m.pixel(100, 50), Color.TRANSPARENT)


def test_autoclear_off_lets_ink_survive_later_frames() raises -> None:
    # Rendered on frame 1 only; with no clear it is still there four frames on.
    var m = run_headless[InkOnFirstFrameOnly](200, 100, frames=5)
    assert_equal(m.pixel(100, 50), Color.RED)


def test_a_program_background_wins_over_the_autoclear() raises -> None:
    var m = run_headless[OwnBackground](200, 100)
    assert_equal(m.pixel(100, 50), Color.BLUE)


def test_an_opaque_background_replaces_the_autoclear() raises -> None:
    var context = Context()
    var state = PersistentCanvasState()
    state._set_viewport(context, 200, 100)
    var canvas = Canvas(state^, context, Input())
    canvas.background(Color.BLUE)
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 1)


def test_a_translucent_background_keeps_both() raises -> None:
    # It blends with what the clear painted, so the clear has to survive.
    var context = Context()
    var state = PersistentCanvasState()
    state._set_viewport(context, 200, 100)
    var canvas = Canvas(state^, context, Input())
    canvas.background(Color(0x11, 0x11, 0x11, 24))
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 2)


def test_autoclear_records_nothing_when_off() raises -> None:
    var context = Context()
    context.autoclear = False
    var state = PersistentCanvasState()
    state._set_viewport(context, 200, 100)
    var canvas = Canvas(state^, context, Input())
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
