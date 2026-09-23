"""Unit tests for the SDL_Event field readers in `create._window._sdl`.

Builds synthetic byte buffers at the documented offsets and checks each
reader decodes the value written there -- guards the offset comments in
`_sdl.mojo` against silent bitrot. No live SDL events involved.
"""

from std.testing import TestSuite, assert_equal, assert_true
from create._window._sdl import (
    SDL,
    SDL_EVENT_QUIT,
    SDL_EVENT_WINDOW_RESIZED,
    SDL_EVENT_KEY_DOWN,
    SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_MOUSE_BUTTON_DOWN,
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
    event_type,
    window_data1,
    window_data2,
    key_keycode,
    mouse_x,
    mouse_y,
    button_index,
    button_x,
    button_y,
    wheel_x,
    wheel_y,
)
from _raw_event import (
    new_event_buffer,
    write_u8,
    write_u32,
    write_i32,
    write_f32,
)


def test_event_type() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_QUIT)
    assert_equal(event_type(buf.unsafe_ptr()), SDL_EVENT_QUIT)


def test_window_data() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_WINDOW_RESIZED)
    write_i32(buf, _OFF_WINDOW_DATA1, 1024)
    write_i32(buf, _OFF_WINDOW_DATA2, 768)
    var ptr = buf.unsafe_ptr()
    assert_equal(window_data1(ptr), Int32(1024))
    assert_equal(window_data2(ptr), Int32(768))


def test_key_keycode() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_KEY_DOWN)
    write_u32(buf, _OFF_KEY_KEYCODE, 97)
    assert_equal(key_keycode(buf.unsafe_ptr()), UInt32(97))


def test_motion_xy() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_MOTION)
    write_f32(buf, _OFF_MOTION_X, 12.5)
    write_f32(buf, _OFF_MOTION_Y, -3.25)
    var ptr = buf.unsafe_ptr()
    assert_equal(mouse_x(ptr), Float32(12.5))
    assert_equal(mouse_y(ptr), Float32(-3.25))


def test_button_fields() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_BUTTON_DOWN)
    write_u8(buf, _OFF_BUTTON_INDEX, 1)
    write_f32(buf, _OFF_BUTTON_X, 5.0)
    write_f32(buf, _OFF_BUTTON_Y, 6.0)
    var ptr = buf.unsafe_ptr()
    assert_equal(button_index(ptr), UInt8(1))
    assert_equal(button_x(ptr), Float32(5.0))
    assert_equal(button_y(ptr), Float32(6.0))


def test_wheel_xy() raises -> None:
    var buf = new_event_buffer(SDL_EVENT_MOUSE_WHEEL)
    write_f32(buf, _OFF_WHEEL_X, 0.0)
    write_f32(buf, _OFF_WHEEL_Y, -1.0)
    var ptr = buf.unsafe_ptr()
    assert_equal(wheel_x(ptr), Float32(0.0))
    assert_equal(wheel_y(ptr), Float32(-1.0))


def test_linked_sdl3_is_major_version_3() raises -> None:
    """Guards the ABI check in `SDL.__init__` -- if this ever fails, the
    offsets above need re-verifying against whatever SDL3 build is linked.
    """
    var sdl = SDL()
    var major = sdl.get_version() // 1000000
    assert_true(major == 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
