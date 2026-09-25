"""The one translation from SDL events to `Input`.

Both run loops pump events and both have to fold them into the same place,
so the arms live here rather than once per loop — a keycode handled in
one and not the other would be a silent divergence between the CPU and GPU
paths.

The window itself is deliberately absent: the arms only ever need to say
*whether* the window should close, never to close it, so this is shared by
`Window` and `GLWindow` without being generic over either.
"""

from create._window.event import (
    Event,
    KeyDown,
    KeyUp,
    MouseButtonDown,
    MouseButtonUp,
    MouseMoved,
    MouseWheel,
    Quit,
    Resized,
)

from create.math.point2d import Point2D
from create.math.vector2d import Vector2D

from create.render.context import Context
from create.render.viewport import Viewport


def apply_events(
    events: List[Event],
    view: Viewport,
    mut context: Context,
    px_per_point: Float64 = 1.0,
) -> Bool:
    """Fold a frame's events into `context.input`; True means quit.

    Takes the viewport and the dials rather than a frame because this runs
    *before* the frame is built — pointer positions have to be mapped with
    this frame's mapping, which the loop has just re-derived.

    `px_per_point` converts a pointer position from SDL's logical window
    coordinates into the framebuffer pixels the viewport was built from. It is
    1 whenever the two agree — every pixel-buffer `Window` — and the drawable
    over logical ratio on a scaled display, where the GL loop sizes its
    viewport from `drawable_size()`.
    """
    ref input = context.input
    input._new_frame()
    var quit = False
    for event in events:
        if event.isa[Quit]():
            quit = True
        elif event.isa[KeyDown]():
            var keycode = event[KeyDown].keycode
            if keycode == 27 and context.quit_on_escape:
                quit = True
            if not input.is_key_down(keycode):
                input._held_keys.set(keycode)
                input._just_pressed.set(keycode)
        elif event.isa[KeyUp]():
            var keycode = event[KeyUp].keycode
            input._held_keys.clear(keycode)
            input._just_released.set(keycode)
        elif event.isa[MouseMoved]():
            var e = event[MouseMoved]
            # Pointer positions reach the program in screen space — the same
            # camera-independent space `canvas.left`/`right`/`bottom`/`top` use.
            var p = view.to_screen(
                Float64(e.x) * px_per_point, Float64(e.y) * px_per_point
            )
            input._set_mouse(p[0], p[1])
        elif event.isa[MouseButtonDown]():
            var e = event[MouseButtonDown]
            var p = view.to_screen(
                Float64(e.x) * px_per_point, Float64(e.y) * px_per_point
            )
            input.mouse_pressed = True
            input.mouse_button = e.button
            input._set_mouse(p[0], p[1])
            input.mouse_press_pos = Point2D(p[0], p[1])
            input._held_buttons |= 1 << e.button
            input._pressed_buttons |= 1 << e.button
        elif event.isa[MouseButtonUp]():
            var e = event[MouseButtonUp]
            var p = view.to_screen(
                Float64(e.x) * px_per_point, Float64(e.y) * px_per_point
            )
            input.mouse_pressed = False
            input._set_mouse(p[0], p[1])
            input._held_buttons &= ~(1 << e.button)
            input._released_buttons |= 1 << e.button
        elif event.isa[MouseWheel]():
            var e = event[MouseWheel]
            input.wheel = Vector2D(Float64(e.x), Float64(e.y))
        elif event.isa[Resized]():
            pass  # The viewport is re-derived every frame regardless.
    return quit
