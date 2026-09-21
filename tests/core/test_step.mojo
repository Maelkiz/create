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
    def create(mut options: Options) raises -> Painter:
        return Painter(0)

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        frame.background(Color.BLUE)
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 10.0, 10.0)


def _mismatched() raises -> MemorySurface:
    """One frame where the surface is larger than the viewport was measured for.

    64x64 viewport, 200x200 buffer — the shape a grown window produces between
    the measurement and the resize.
    """
    var start = PersistentFrameState()
    var options = Options()
    options.design_resolution(64, 64)
    start._set_viewport(options, 64, 64)
    var program = Painter(0)
    var input = Input()
    var mem = MemorySurface(200, 200)
    var state = step(program, options, input, start^)
    state.backend.present(mem.surface(), state.view.scale)
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
    rendering.
    """

    var clicked: Bool

    @staticmethod
    def create(mut options: Options) raises -> ClickPainter:
        return ClickPainter(False)

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        self.clicked = frame.input.mouse_just_pressed()

        frame.background(Color.RED if self.clicked else Color.BLUE)


def test_scripted_click_drives_rendering() raises -> None:
    var mem = MemorySurface(32, 32)

    var idle_options = Options()
    idle_options.design_resolution(32, 32)
    var idle_start = PersistentFrameState()
    idle_start._set_viewport(idle_options, 32, 32)
    var idle_program = ClickPainter(False)
    var idle_state = step(idle_program, idle_options, Input(), idle_start^)
    idle_state.backend.present(mem.surface(), idle_state.view.scale)
    assert_equal(mem.pixel(16, 16), Color.BLUE)
    _ = idle_state^

    var clicked_options = Options()
    clicked_options.design_resolution(32, 32)
    var clicked_start = PersistentFrameState()
    clicked_start._set_viewport(clicked_options, 32, 32)
    var clicked_program = ClickPainter(False)
    var clicked_input = Input()
    clicked_input._pressed_buttons |= 1 << 1
    var clicked_state = step(
        clicked_program, clicked_options, clicked_input, clicked_start^
    )
    clicked_state.backend.present(mem.surface(), clicked_state.view.scale)
    assert_equal(mem.pixel(16, 16), Color.RED)
    _ = clicked_state^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
