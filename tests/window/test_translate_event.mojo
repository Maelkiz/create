"""Unit tests for `window.event.translate_event` -- the pure event-kind ->
`Event` translation shared by `Window.events()` and `GLWindow.events()`.
Builds synthetic buffers directly (same technique as
`test_sdl_readers.mojo`), no live SDL window involved.
"""

from std.testing import TestSuite, assert_equal, assert_true, assert_false
from create._window import (
    Event,
    KeyDown,
    KeyUp,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
)
from create._window._sdl import (
    SDL_EVENT_QUIT,
    SDL_EVENT_KEY_DOWN,
    SDL_EVENT_KEY_UP,
    SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_MOUSE_BUTTON_DOWN,
    SDL_EVENT_MOUSE_BUTTON_UP,
    SDL_EVENT_MOUSE_WHEEL,
    _OFF_KEY_KEYCODE,
    _OFF_MOTION_X,
    _OFF_MOTION_Y,
    _OFF_BUTTON_INDEX,
    _OFF_BUTTON_X,
    _OFF_BUTTON_Y,
    _OFF_WHEEL_X,
    _OFF_WHEEL_Y,
)
from create._window.event import translate_event
from _raw_event import new_event_buffer, write_u8, write_u32, write_f32


def test_unhandled_kind_returns_none() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_QUIT)
    var translated = translate_event(SDL_EVENT_QUIT, buf.unsafe_ptr())
    assert_false(Bool(translated))


def test_keydown_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_KEY_DOWN)
    write_u32(buf, _OFF_KEY_KEYCODE, 97)
    var translated = translate_event(SDL_EVENT_KEY_DOWN, buf.unsafe_ptr())
    assert_true(Bool(translated))
    var e = translated.value()
    assert_true(e.isa[KeyDown]())
    assert_equal(e[KeyDown].keycode, 97)


def test_keyup_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_KEY_UP)
    write_u32(buf, _OFF_KEY_KEYCODE, 42)
    var translated = translate_event(SDL_EVENT_KEY_UP, buf.unsafe_ptr())
    assert_true(Bool(translated))
    assert_equal(translated.value()[KeyUp].keycode, 42)


def test_mouse_motion_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_MOTION)
    write_f32(buf, _OFF_MOTION_X, 12.0)
    write_f32(buf, _OFF_MOTION_Y, 34.0)
    var translated = translate_event(SDL_EVENT_MOUSE_MOTION, buf.unsafe_ptr())
    assert_true(Bool(translated))
    var e = translated.value()
    assert_equal(e[MouseMoved].x, 12)
    assert_equal(e[MouseMoved].y, 34)


def test_mouse_button_down_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_BUTTON_DOWN)
    write_u8(buf, _OFF_BUTTON_INDEX, 1)
    write_f32(buf, _OFF_BUTTON_X, 5.0)
    write_f32(buf, _OFF_BUTTON_Y, 6.0)
    var translated = translate_event(
        SDL_EVENT_MOUSE_BUTTON_DOWN, buf.unsafe_ptr()
    )
    assert_true(Bool(translated))
    var e = translated.value()
    assert_equal(e[MouseButtonDown].button, 1)
    assert_equal(e[MouseButtonDown].x, 5)
    assert_equal(e[MouseButtonDown].y, 6)


def test_mouse_button_up_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_BUTTON_UP)
    write_u8(buf, _OFF_BUTTON_INDEX, 2)
    write_f32(buf, _OFF_BUTTON_X, 9.0)
    write_f32(buf, _OFF_BUTTON_Y, 10.0)
    var translated = translate_event(
        SDL_EVENT_MOUSE_BUTTON_UP, buf.unsafe_ptr()
    )
    assert_true(Bool(translated))
    var e = translated.value()
    assert_equal(e[MouseButtonUp].button, 2)
    assert_equal(e[MouseButtonUp].x, 9)
    assert_equal(e[MouseButtonUp].y, 10)


def test_mouse_wheel_translates() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_WHEEL)
    write_f32(buf, _OFF_WHEEL_X, 0.0)
    write_f32(buf, _OFF_WHEEL_Y, -1.0)
    var translated = translate_event(SDL_EVENT_MOUSE_WHEEL, buf.unsafe_ptr())
    assert_true(Bool(translated))
    var e = translated.value()
    assert_equal(e[MouseWheel].x, 0)
    assert_equal(e[MouseWheel].y, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
