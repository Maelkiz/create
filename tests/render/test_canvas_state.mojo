"""What a `Canvas` carries across the frame boundary, and what it must not.

A `Canvas` is rebuilt every frame from a `PersistentCanvasState` and the
program's `Context`, so each field is either read-only for the program,
written back by `_release`, or dropped. The dials themselves outlive the
frame in `Context`, which the loop reads at frame construction — so a dial
set mid-`update` applies to the *next* frame. These check that split
directly.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)

from create import *
from create.render.canvas import Canvas, PersistentCanvasState


def _state(
    context: Context, pixel_w: Int, pixel_h: Int
) raises -> PersistentCanvasState:
    var state = PersistentCanvasState()
    context._set_viewport(state, pixel_w, pixel_h)
    return state^


def test_release_does_not_write_the_viewport_back() raises -> None:
    # The loop owns the mapping — a frame that wrote its copy back would undo
    # a resize the loop handled while the frame was being rendered.
    var context = Context()
    var canvas = context._new_canvas(_state(context, 800, 600))
    canvas.view.set_size(1600, 1200)
    var state = canvas^._release()
    assert_equal(state.view.pixel_w, 800)
    assert_equal(state.view.pixel_h, 600)


def test_design_takes_effect_on_the_next_frame() raises -> None:
    # `design_resolution` writes to the context, so the frame already built
    # keeps reporting the size it was built with; the loop's next
    # `_set_viewport` is what publishes the new mapping.
    var context = Context()
    var state = _state(context, 1600, 1200)
    var canvas = context._new_canvas(state^)
    context.design_resolution(800, 600)
    assert_equal(canvas.width, 1600)
    state = canvas^._release()
    assert_true(context.autoscale() == AutoScale.FIT)
    context._set_viewport(state, 1600, 1200)
    var next = context._new_canvas(state^)
    assert_equal(next.width, 800)
    assert_equal(next.height, 600)
    assert_almost_equal(next.scale, 2.0)


def test_design_overrides_an_earlier_design() raises -> None:
    var context = Context()
    var state = _state(context, 2000, 1000)
    context.design_resolution(800, 600)
    context.design_resolution(1000, 500)
    context.autoscale(AutoScale.EXTEND)
    context._set_viewport(state, 2000, 1000)
    var next = context._new_canvas(state^)
    assert_true(next.view.autoscale == AutoScale.EXTEND)
    assert_almost_equal(next.scale, 2.0)
    assert_equal(next.width, 1000)
    assert_equal(next.height, 500)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
