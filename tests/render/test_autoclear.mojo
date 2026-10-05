"""The per-frame clear: its default, its opt-out, and its coalescing.

`autoclear` records a `CMD_CLEAR` at the head of every frame, so an unstyled
sketch renders onto a light surface rather than onto whatever the framebuffer
happened to hold. Turning it off is what a program that accumulates ink across
frames does, and an opaque `background()` replaces the clear rather than
stacking a second full-framebuffer paint on it.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.render._command import CMD_CLEAR
from create.render.canvas import Canvas, PersistentCanvasState


@fieldwise_init
struct RendersNothing(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> RendersNothing:
        return RendersNothing(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


@fieldwise_init
struct NoAutoclear(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> NoAutoclear:
        canvas.autoclear(False)
        return NoAutoclear(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


@fieldwise_init
struct InkOnFirstFrameOnly(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> InkOnFirstFrameOnly:
        canvas.autoclear(False)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.rectangle((0, 0), 40, 40)
        return InkOnFirstFrameOnly(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        pass


@fieldwise_init
struct OwnBackground(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> OwnBackground:
        return OwnBackground(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)


def test_a_frame_starts_cleared_to_the_default_gray() raises -> None:
    var m = run_headless[RendersNothing](200, 100)
    assert_equal(m.pixel(100, 50), Color(200))


def test_autoclear_off_leaves_the_buffer_untouched() raises -> None:
    # Off from `create` on, so not even frame 1 clears.
    var m = run_headless[NoAutoclear](200, 100)
    assert_equal(m.pixel(100, 50), Color.TRANSPARENT)


def test_autoclear_off_lets_ink_survive_later_frames() raises -> None:
    # Rendered by `create` only; with no clear it is still there five frames
    # on.
    var m = run_headless[InkOnFirstFrameOnly](200, 100, frames=5)
    assert_equal(m.pixel(100, 50), Color.RED)


def test_a_program_background_wins_over_the_autoclear() raises -> None:
    var m = run_headless[OwnBackground](200, 100)
    assert_equal(m.pixel(100, 50), Color.BLUE)


def test_an_opaque_background_replaces_the_autoclear() raises -> None:
    var context = Context()
    var state = PersistentCanvasState()
    context._set_viewport(state, 200, 100)
    var canvas = context._new_canvas(state^)
    canvas.background(Color.BLUE)
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 1)


def test_a_translucent_background_keeps_both() raises -> None:
    # It blends with what the clear painted, so the clear has to survive.
    var context = Context()
    var state = PersistentCanvasState()
    context._set_viewport(state, 200, 100)
    var canvas = context._new_canvas(state^)
    canvas.background(Color(0x11, 0x11, 0x11, 24))
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 2)


def test_autoclear_records_nothing_when_off() raises -> None:
    var context = Context()
    var state = PersistentCanvasState()
    state.autoclear = False
    context._set_viewport(state, 200, 100)
    var canvas = context._new_canvas(state^)
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 0)


def _frame(mut context: Context) raises -> Canvas:
    var state = PersistentCanvasState()
    context._set_viewport(state, 200, 100)
    return context._new_canvas(state^)


def test_switching_off_mid_frame_takes_the_opening_clear_out() raises -> None:
    var context = Context()
    var canvas = _frame(context)
    _ = canvas.pixel((0, 0))
    canvas.autoclear(False)
    assert_true(not canvas.autoclear())
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 0)
    assert_true(not out.autoclear, "lasts into later frames")


def test_switching_off_keeps_an_opaque_background() raises -> None:
    var context = Context()
    var canvas = _frame(context)
    canvas.background(Color.BLUE)
    canvas.autoclear(False)
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 1)
    assert_equal(out.backend.commands[0].kind, CMD_CLEAR)


def test_switching_off_then_on_again_clears_once() raises -> None:
    var context = Context()
    var canvas = _frame(context)
    canvas.autoclear(False)
    canvas.autoclear(True)
    canvas.autoclear(True)
    var out = canvas^._release()
    assert_equal(len(out.backend.commands), 1)
    assert_equal(out.backend.commands[0].kind, CMD_CLEAR)


def test_switching_on_mid_frame_clears_under_what_is_drawn() raises -> None:
    var context = Context()
    var state = PersistentCanvasState()
    state.autoclear = False
    context._set_viewport(state, 200, 100)
    var canvas = context._new_canvas(state^)
    with canvas.style(fill=Color.RED, outline_enabled=False):
        canvas.rectangle((0, 0), 20, 20)
    canvas.autoclear(True)
    assert_equal(canvas.pixel((0, 0)), Color.RED)
    assert_equal(canvas.pixel((50, 0)), Color(200))


def _commands_after_background(gradient: Gradient) raises -> Int:
    var context = Context()
    var state = PersistentCanvasState()
    context._set_viewport(state, 200, 100)
    var canvas = context._new_canvas(state^)
    canvas.background(gradient)
    var out = canvas^._release()
    return len(out.backend.commands)


def test_an_opaque_gradient_background_replaces_the_autoclear() raises -> None:
    assert_equal(
        _commands_after_background(Gradient.linear(Color.RED, Color.BLUE)), 1
    )


def test_a_translucent_gradient_background_keeps_both() raises -> None:
    # One translucent stop is enough: somewhere, the clear shows through.
    assert_equal(
        _commands_after_background(
            Gradient.linear(Color.RED, Color.BLUE.with_alpha(254))
        ),
        2,
    )


@fieldwise_init
struct Dots(Program):
    """Autoclear off from `create`; one dot per `update`, each further right."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Dots:
        canvas.autoclear(False)
        canvas.background(Color.BLACK)
        return Dots(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        with canvas.style(fill=Color.RED, outline_enabled=False):
            canvas.rectangle((context.frame_count() * 20 - 60, 0), 10, 10)


def test_ink_from_every_frame_accumulates() raises -> None:
    # Frames 2, 3 and 4 put dots at x = -20, 0 and 20 (pixels 80, 100, 120).
    var m = run_headless[Dots](200, 100, 3, antialiasing=Antialiasing.OFF)
    assert_equal(m.pixel(80, 50), Color.RED)
    assert_equal(m.pixel(100, 50), Color.RED)
    assert_equal(m.pixel(120, 50), Color.RED)
    assert_equal(m.pixel(150, 50), Color.BLACK)


@fieldwise_init
struct OffPartway(Program):
    """Red in `create`; `update` switches the clear off after reading."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> OffPartway:
        canvas.background(Color.RED)
        return OffPartway(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        assert_equal(canvas.pixel((0, 0)), Color(200), "cleared so far")
        canvas.autoclear(False)
        # The read is replayed, not cached: this frame no longer clears.
        assert_true(canvas.pixel((0, 0)) != Color(200), "read again")


def test_switching_off_partway_through_keeps_the_last_frame() raises -> None:
    var m = run_headless[OffPartway](200, 100, 1)
    assert_equal(m.pixel(100, 50), Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
