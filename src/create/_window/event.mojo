"""Public `Event` type — window/input events translated from raw SDL3 events."""

from std.utils import Variant

from ._sdl import (
    SDL,
    SDL_EVENT_GAMEPAD_ADDED,
    SDL_EVENT_GAMEPAD_AXIS_MOTION,
    SDL_EVENT_GAMEPAD_BUTTON_DOWN,
    SDL_EVENT_GAMEPAD_BUTTON_UP,
    SDL_EVENT_GAMEPAD_REMOVED,
    SDL_JOYSTICK_AXIS_MAX,
    SDL_EVENT_KEY_DOWN,
    SDL_EVENT_KEY_UP,
    SDL_EVENT_TEXT_INPUT,
    SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_MOUSE_BUTTON_DOWN,
    SDL_EVENT_MOUSE_BUTTON_UP,
    SDL_EVENT_MOUSE_WHEEL,
    key_keycode,
    text_input_text,
    mouse_x,
    mouse_y,
    button_index,
    button_x,
    button_y,
    wheel_x,
    wheel_y,
    gamepad_id,
    gamepad_axis,
    gamepad_axis_value,
    gamepad_button,
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
struct TextInput(ImplicitlyCopyable, Movable):
    """Text the user typed, UTF-8: usually one character, but an IME can
    commit several at once. Arrives beside, not instead of, the `KeyDown`
    events of the keys that produced it."""

    var text: String


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


@fieldwise_init
struct GamepadAdded(ImplicitlyCopyable, Movable):
    """A gamepad was connected, or was already when the window opened. `id`
    names it in every later gamepad event until `GamepadRemoved`."""

    var id: Int


@fieldwise_init
struct GamepadRemoved(ImplicitlyCopyable, Movable):
    var id: Int


@fieldwise_init
struct GamepadAxisMoved(ImplicitlyCopyable, Movable):
    """`axis` in SDL's numbering (left x, left y, right x, right y, left
    trigger, right trigger). `value` is -1..1 for a stick, positive right
    and *down* as SDL reports it, and 0..1 for a trigger."""

    var id: Int
    var axis: Int
    var value: Float64


@fieldwise_init
struct GamepadButtonDown(ImplicitlyCopyable, Movable):
    var id: Int
    var button: Int


@fieldwise_init
struct GamepadButtonUp(ImplicitlyCopyable, Movable):
    var id: Int
    var button: Int


comptime Event = Variant[
    Quit,
    Resized,
    KeyDown,
    KeyUp,
    TextInput,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
    GamepadAdded,
    GamepadRemoved,
    GamepadAxisMoved,
    GamepadButtonDown,
    GamepadButtonUp,
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
    elif kind == SDL_EVENT_TEXT_INPUT:
        return Event(TextInput(text_input_text(ptr)))
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
    elif kind == SDL_EVENT_GAMEPAD_ADDED:
        return Event(GamepadAdded(Int(gamepad_id(ptr))))
    elif kind == SDL_EVENT_GAMEPAD_REMOVED:
        return Event(GamepadRemoved(Int(gamepad_id(ptr))))
    elif kind == SDL_EVENT_GAMEPAD_AXIS_MOTION:
        var value = Float64(gamepad_axis_value(ptr)) / Float64(
            SDL_JOYSTICK_AXIS_MAX
        )
        return Event(
            GamepadAxisMoved(
                Int(gamepad_id(ptr)),
                Int(gamepad_axis(ptr)),
                max(value, -1.0),
            )
        )
    elif kind == SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        return Event(
            GamepadButtonDown(Int(gamepad_id(ptr)), Int(gamepad_button(ptr)))
        )
    elif kind == SDL_EVENT_GAMEPAD_BUTTON_UP:
        return Event(
            GamepadButtonUp(Int(gamepad_id(ptr)), Int(gamepad_button(ptr)))
        )
    else:
        return None


def track_gamepad(sdl: SDL, kind: UInt32, ptr: Pointer[UInt8, _]) raises:
    """Opens a gamepad as SDL announces it and closes it on removal.

    The one side effect of a gamepad event, kept out of `translate_event`
    (which has no SDL to call) and shared by `Window` and `GLWindow`, which
    call it on every event before translating it.
    """
    if kind == SDL_EVENT_GAMEPAD_ADDED:
        sdl.open_gamepad(gamepad_id(ptr))
    elif kind == SDL_EVENT_GAMEPAD_REMOVED:
        sdl.close_gamepad(gamepad_id(ptr))
