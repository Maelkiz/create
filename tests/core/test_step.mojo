# The one shared frame step, and the split it depends on.
#
# `Frame` takes its geometry from the `Viewport` and its extent from the
# `Surface`. The windowed loop relies on exactly that: the viewport is measured
# before events, but `Window._resize` reallocates the pixel buffer during them,
# so the two can disagree for a frame. Only the surface knows how big the
# memory actually is — hence the extent must never be read off the viewport.

from std.testing import TestSuite, assert_equal

from create import *
from create.core._step import step


@fieldwise_init
struct Painter(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> Painter:
        return Painter(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLUE)
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 10.0, 10.0)


def _mismatched() raises -> MemorySurface:
    """One frame where the surface is larger than the viewport was measured for.

    64x64 viewport, 200x200 buffer — the shape a grown window produces between
    the measurement and the resize.
    """
    var ctx = Context()
    ctx.view.set_design(64, 64)
    ctx.autoscale = AutoScale.FIT
    ctx._set_viewport(64, 64)
    var program = Painter(0)
    var input = Input()
    var mem = MemorySurface(200, 200)
    var state = step(program, ctx, input, PersistentFrameState())
    state.backend.present(mem.surface(), ctx.view.scale)
    _ = state^
    return mem^


def test_extent_comes_from_the_surface() raises -> None:
    # The far corner is outside what the viewport describes but inside the
    # buffer, so it must still be painted. Reading the extent off the viewport
    # would leave it at the zero fill.
    var m = _mismatched()
    assert_equal(m.pixel(199, 199), Color.BLUE)
    assert_equal(m.pixel(0, 0), Color.BLUE)


def test_geometry_comes_from_the_viewport() raises -> None:
    # Geometry does not follow the surface: the origin stays at the centre of
    # the 64x64 viewport, pixel (32, 32), not at the centre of the buffer. This
    # is the one-frame lag between mapping and framebuffer, and it is why the
    # windowed loop must still pass an honest extent — a wrong extent is
    # memory corruption, a lagging mapping is one crooked frame.
    var m = _mismatched()
    assert_equal(m.pixel(32, 32), Color.RED)
    assert_equal(m.pixel(100, 100), Color.BLUE)


@fieldwise_init
struct ClickPainter(Program):
    """Paints red the frame the mouse is pressed, blue otherwise.

    Nothing here is fed by SDL — `Input` is a plain struct a test can fill in
    and hand straight to `step`, unlike the removed per-event callbacks,
    which only the run loop could ever fire. This is what makes click-driven
    behaviour assertable the same way the pixel tests already assert on
    drawing.
    """

    var clicked: Bool

    @staticmethod
    def create(mut ctx: Context) raises -> ClickPainter:
        return ClickPainter(False)

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.clicked = input.mouse_just_pressed()

    def render(self, mut frame: Frame) raises:
        frame.background(Color.RED if self.clicked else Color.BLUE)


def test_scripted_click_drives_render() raises -> None:
    var ctx = Context()
    ctx.view.set_design(32, 32)
    ctx.autoscale = AutoScale.FIT
    ctx._set_viewport(32, 32)
    var mem = MemorySurface(32, 32)

    var idle_program = ClickPainter(False)
    var idle_state = step(idle_program, ctx, Input(), PersistentFrameState())
    idle_state.backend.present(mem.surface(), ctx.view.scale)
    assert_equal(mem.pixel(16, 16), Color.BLUE)
    _ = idle_state^

    var clicked_program = ClickPainter(False)
    var clicked_input = Input()
    clicked_input._pressed_buttons |= 1 << 1
    var clicked_state = step(
        clicked_program, ctx, clicked_input, PersistentFrameState()
    )
    clicked_state.backend.present(mem.surface(), ctx.view.scale)
    assert_equal(mem.pixel(16, 16), Color.RED)
    _ = clicked_state^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
