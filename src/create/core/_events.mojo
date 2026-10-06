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
    GamepadAdded,
    GamepadAxisMoved,
    GamepadButtonDown,
    GamepadButtonUp,
    GamepadRemoved,
    KeyDown,
    KeyUp,
    MouseButtonDown,
    MouseButtonUp,
    MouseMoved,
    MouseWheel,
    Quit,
    Resized,
    TextInput,
)

from create.math.point2d import Point2D
from create.math.vector2d import Vector2D

from create.core.context import Context
from create.input.input import Input
from create.input.key import Key
from create.render._viewport import Viewport


def apply_events(
    events: List[Event],
    view: Viewport,
    mut context: Context,
    px_per_point: Float64 = 1.0,
) -> Bool:
    """Fold a frame's events into `context.input`; True means quit.

    Takes the viewport and the context rather than a `Canvas` because this
    runs *before* the canvas is built — pointer positions have to be mapped with
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
            var key = Key(event[KeyDown].keycode)
            if key == Key.ESCAPE and context._quit_on_escape:
                quit = True
            input._key_down(key)
        elif event.isa[KeyUp]():
            input._key_up(Key(event[KeyUp].keycode))
        elif event.isa[TextInput]():
            input._type_text(event[TextInput].text)
        elif event.isa[MouseMoved]():
            var e = event[MouseMoved]
            # Pointer positions reach the program in screen space — the same
            # camera-independent space `canvas.left`/`right`/`bottom`/`top` use.
            var p = _to_screen(view, e.x, e.y, px_per_point)
            input._set_mouse(p.x, p.y)
        elif event.isa[MouseButtonDown]():
            var e = event[MouseButtonDown]
            input._mouse_button_down(
                e.button, _to_screen(view, e.x, e.y, px_per_point)
            )
        elif event.isa[MouseButtonUp]():
            var e = event[MouseButtonUp]
            input._mouse_button_up(
                e.button, _to_screen(view, e.x, e.y, px_per_point)
            )
        elif event.isa[MouseWheel]():
            var e = event[MouseWheel]
            input._scroll(Vector2D(Float64(e.x), Float64(e.y)))
        elif event.isa[GamepadAdded]():
            ref added = event[GamepadAdded]
            input._connect_gamepad(added.id, added.name)
        elif event.isa[GamepadRemoved]():
            input._disconnect_gamepad(event[GamepadRemoved].id)
        elif event.isa[GamepadAxisMoved]():
            var e = event[GamepadAxisMoved]
            input._gamepad_axis_moved(e.id, e.axis, e.value)
        elif event.isa[GamepadButtonDown]():
            var e = event[GamepadButtonDown]
            input._gamepad_button_down(e.id, e.button)
        elif event.isa[GamepadButtonUp]():
            var e = event[GamepadButtonUp]
            input._gamepad_button_up(e.id, e.button)
        elif event.isa[Resized]():
            pass  # The viewport is re-derived every frame regardless.
    return quit


def _to_screen(
    view: Viewport, x: Int, y: Int, px_per_point: Float64
) -> Point2D:
    """A pointer position from SDL's window coordinates into screen space."""
    return view.to_screen(
        Point2D(Float64(x) * px_per_point, Float64(y) * px_per_point)
    )
