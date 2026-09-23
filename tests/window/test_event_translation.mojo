"""End-to-end test of `Window.events()`: pushes real `SDL_Event` buffers via
`SDL_PushEvent` and checks the returned `Event`s have the right variant and
fields. Complements `test_sdl_readers.mojo`, which only checks the
byte-offset decoders in isolation -- this exercises the real SDL round trip.
"""

from std.os import setenv
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from create._window import (
    Window,
    Quit,
    Resized,
    KeyDown,
    KeyUp,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
)
from create._window._sdl import (
    SDL,
    SDL_EVENT_QUIT,
    SDL_EVENT_WINDOW_RESIZED,
    SDL_EVENT_KEY_DOWN,
    SDL_EVENT_KEY_UP,
    SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_MOUSE_BUTTON_DOWN,
    SDL_EVENT_MOUSE_BUTTON_UP,
    SDL_EVENT_MOUSE_WHEEL,
    _OFF_WINDOW_DATA1,
    _OFF_WINDOW_DATA2,
    _OFF_KEY_KEYCODE,
    _OFF_MOTION_X,
    _OFF_MOTION_Y,
    _OFF_BUTTON_INDEX,
    _OFF_BUTTON_X,
    _OFF_BUTTON_Y,
    _OFF_WHEEL_X,
    _OFF_WHEEL_Y,
)
from _raw_event import (
    new_event_buffer,
    write_u8,
    write_u32,
    write_i32,
    write_f32,
)


def test_quit_delivers_and_closes_window() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_QUIT)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[Quit]())
    assert_false(w.is_open())


def test_resized_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_WINDOW_RESIZED)
    write_i32(buf, _OFF_WINDOW_DATA1, 1024)
    write_i32(buf, _OFF_WINDOW_DATA2, 768)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[Resized]())
    assert_equal(events[0][Resized].width, 1024)
    assert_equal(events[0][Resized].height, 768)


def test_keydown_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_KEY_DOWN)
    write_u32(buf, _OFF_KEY_KEYCODE, 97)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[KeyDown]())
    assert_equal(events[0][KeyDown].keycode, 97)


def test_keyup_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_KEY_UP)
    write_u32(buf, _OFF_KEY_KEYCODE, 42)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[KeyUp]())
    assert_equal(events[0][KeyUp].keycode, 42)


def test_mouse_motion_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_MOUSE_MOTION)
    write_f32(buf, _OFF_MOTION_X, 12.0)
    write_f32(buf, _OFF_MOTION_Y, 34.0)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[MouseMoved]())
    assert_equal(events[0][MouseMoved].x, 12)
    assert_equal(events[0][MouseMoved].y, 34)


def test_mouse_button_down_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_MOUSE_BUTTON_DOWN)
    write_u8(buf, _OFF_BUTTON_INDEX, 1)
    write_f32(buf, _OFF_BUTTON_X, 5.0)
    write_f32(buf, _OFF_BUTTON_Y, 6.0)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[MouseButtonDown]())
    assert_equal(events[0][MouseButtonDown].button, 1)
    assert_equal(events[0][MouseButtonDown].x, 5)
    assert_equal(events[0][MouseButtonDown].y, 6)


def test_mouse_button_up_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_MOUSE_BUTTON_UP)
    write_u8(buf, _OFF_BUTTON_INDEX, 2)
    write_f32(buf, _OFF_BUTTON_X, 9.0)
    write_f32(buf, _OFF_BUTTON_Y, 10.0)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[MouseButtonUp]())
    assert_equal(events[0][MouseButtonUp].button, 2)
    assert_equal(events[0][MouseButtonUp].x, 9)
    assert_equal(events[0][MouseButtonUp].y, 10)


def test_mouse_wheel_delivers() raises -> None:
    var w = Window("t", 64, 64)
    var buf = new_event_buffer(SDL_EVENT_MOUSE_WHEEL)
    write_f32(buf, _OFF_WHEEL_X, 0.0)
    write_f32(buf, _OFF_WHEEL_Y, -1.0)
    var sdl = SDL()
    assert_true(sdl.push_event(buf.unsafe_ptr()))

    var events = w.events()
    assert_equal(len(events), 1)
    assert_true(events[0].isa[MouseWheel]())
    assert_equal(events[0][MouseWheel].x, 0)
    assert_equal(events[0][MouseWheel].y, -1)


def main() raises:
    # Every `Window` here expects SDL's dummy driver: no real window opens on
    # the desktop, and `GLWindow` is refused a context. `pixi run test` picks
    # the driver per display, so pin it before the first SDL call reads it.
    _ = setenv("SDL_VIDEODRIVER", "dummy", True)
    TestSuite.discover_tests[__functions_in_module()]().run()
