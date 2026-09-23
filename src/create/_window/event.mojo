"""Public `Event` type — window/input events translated from raw SDL3 events."""

from std.utils import Variant

from ._sdl import (
    SDL_EVENT_KEY_DOWN,
    SDL_EVENT_KEY_UP,
    SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_MOUSE_BUTTON_DOWN,
    SDL_EVENT_MOUSE_BUTTON_UP,
    SDL_EVENT_MOUSE_WHEEL,
    key_keycode,
    mouse_x,
    mouse_y,
    button_index,
    button_x,
    button_y,
    wheel_x,
    wheel_y,
)


@fieldwise_init
struct Quit(ImplicitlyCopyable, Movable):
    pass


@fieldwise_init
struct Resized(ImplicitlyCopyable, Movable):
    var width: Int
    var height: Int


@fieldwise_init
struct KeyDown(ImplicitlyCopyable, Movable):
    var keycode: Int


@fieldwise_init
struct KeyUp(ImplicitlyCopyable, Movable):
    var keycode: Int


@fieldwise_init
struct MouseMoved(ImplicitlyCopyable, Movable):
    var x: Int
    var y: Int


@fieldwise_init
struct MouseButtonDown(ImplicitlyCopyable, Movable):
    var button: Int
    var x: Int
    var y: Int


@fieldwise_init
struct MouseButtonUp(ImplicitlyCopyable, Movable):
    var button: Int
    var x: Int
    var y: Int


@fieldwise_init
struct MouseWheel(ImplicitlyCopyable, Movable):
    var x: Int
    var y: Int


comptime Event = Variant[
    Quit,
    Resized,
    KeyDown,
    KeyUp,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
]
"""A window/input event. Check the concrete kind with `.isa[T]()`, then
read fields with `[T]`, e.g. `if e.isa[KeyDown](): print(e[KeyDown].keycode)`.
"""


def translate_event(kind: UInt32, ptr: Pointer[UInt8, _]) -> Optional[Event]:
    """Translates one already-polled raw SDL event buffer into an `Event`.

    Covers every event kind except `SDL_EVENT_QUIT` and
    `SDL_EVENT_WINDOW_RESIZED`, which callers handle themselves (they touch
    caller state -- `_open`, pixel buffer/dimensions -- that this free
    function has no access to). Returns `None` for any other unrecognized
    event kind, same as the inline loop's `continue` used to do.
    """
    if kind == SDL_EVENT_KEY_DOWN:
        return Event(KeyDown(Int(key_keycode(ptr))))
    elif kind == SDL_EVENT_KEY_UP:
        return Event(KeyUp(Int(key_keycode(ptr))))
    elif kind == SDL_EVENT_MOUSE_MOTION:
        return Event(MouseMoved(Int(mouse_x(ptr)), Int(mouse_y(ptr))))
    elif kind == SDL_EVENT_MOUSE_BUTTON_DOWN:
        return Event(
            MouseButtonDown(
                Int(button_index(ptr)), Int(button_x(ptr)), Int(button_y(ptr))
            )
        )
    elif kind == SDL_EVENT_MOUSE_BUTTON_UP:
        return Event(
            MouseButtonUp(
                Int(button_index(ptr)), Int(button_x(ptr)), Int(button_y(ptr))
            )
        )
    elif kind == SDL_EVENT_MOUSE_WHEEL:
        return Event(MouseWheel(Int(wheel_x(ptr)), Int(wheel_y(ptr))))
    else:
        return None
