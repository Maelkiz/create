from std.testing import TestSuite, assert_equal, assert_false, assert_true
from create.core.input import Input
from create.core.key import Key
from create.core.context import Context
from create.render._viewport import Viewport
from create.core._events import apply_events
from create._window.event import Event, KeyDown, KeyUp, TextInput
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def test_key_prints_as_its_constant() raises -> None:
    assert_equal(String(Key.PAGE_UP), "Key.PAGE_UP")
    assert_equal(String(Key.NUM_0), "Key.NUM_0")
    assert_equal(String(Key(0x0444)), "Key(1092)")


def test_key_from_name() raises -> None:
    assert_equal(Key.from_name("page_up").value(), Key.PAGE_UP)
    assert_equal(Key.from_name("Left_Ctrl").value(), Key.LEFT_CTRL)
    assert_equal(Key.from_name("a").value(), Key.A)
    assert_false(Key.from_name("nonexistent_key"))


def test_initial_mouse_position() raises -> None:
    var input = Input()
    assert_equal(input.mouse_x, 0)
    assert_equal(input.mouse_y, 0)
    assert_equal(input.mouse.x, 0.0)
    assert_equal(input.mouse.y, 0.0)


def test_initial_mouse_not_pressed() raises -> None:
    var input = Input()
    assert_equal(input.mouse_down(), False)


def test_no_keys_down_initially() raises -> None:
    var input = Input()
    assert_equal(input.key_down(Key(65)), False)
    assert_equal(input.key_down("a"), False)


def test_key_down_by_keycode() raises -> None:
    var input = Input()
    input._held_keys.set(Key(65))
    assert_true(input.key_down(Key(65)))
    assert_equal(input.key_down(Key(66)), False)


def test_key_down_by_string() raises -> None:
    var input = Input()
    input._held_keys.set(Key(ord("a")))
    assert_true(input.key_down("a"))
    assert_equal(input.key_down("b"), False)


def test_key_down_case_insensitive() raises -> None:
    var input = Input()
    input._held_keys.set(Key(ord("z")))
    assert_true(input.key_down("Z"))


def test_key_pressed_keycode() raises -> None:
    var input = Input()
    input._pressed_keys.set(Key(65))
    assert_true(input.key_pressed(Key(65)))
    assert_equal(input.key_pressed(Key(66)), False)


def test_key_pressed_string() raises -> None:
    var input = Input()
    input._pressed_keys.set(Key(ord("w")))
    assert_true(input.key_pressed("w"))


def test_key_released_keycode() raises -> None:
    var input = Input()
    input._released_keys.set(Key(65))
    assert_true(input.key_released(Key(65)))
    assert_equal(input.key_released(Key(66)), False)


def test_key_released_string() raises -> None:
    var input = Input()
    input._released_keys.set(Key(ord("s")))
    assert_true(input.key_released("s"))


def test_multiple_keys_held() raises -> None:
    var input = Input()
    input._held_keys.set(Key(ord("a")))
    input._held_keys.set(Key(ord("d")))
    assert_true(input.key_down("a"))
    assert_true(input.key_down("d"))
    assert_equal(input.key_down("w"), False)


def test_named_key_escape() raises -> None:
    var input = Input()
    input._held_keys.set(Key.ESCAPE)
    assert_true(input.key_down("escape"))


def test_named_key_space() raises -> None:
    var input = Input()
    input._held_keys.set(Key.SPACE)
    assert_true(input.key_down("space"))


def test_named_key_enter() raises -> None:
    var input = Input()
    input._held_keys.set(Key.ENTER)
    assert_true(input.key_down("enter"))


def test_named_key_arrow_up() raises -> None:
    var input = Input()
    input._held_keys.set(Key.UP)
    assert_true(input.key_down("up"))


def test_named_key_ctrl_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(Key.LEFT_CTRL)
    assert_true(input.key_down("ctrl"))
    input._held_keys.clear_all()
    input._held_keys.set(Key.RIGHT_CTRL)
    assert_true(input.key_down("ctrl"))


def test_mouse_button_initial() raises -> None:
    var input = Input()
    assert_equal(input.mouse_button, 0)


def test_key_initial() raises -> None:
    var input = Input()
    assert_equal(input.key, Key(0))


def test_key_is_the_most_recent_press_and_outlives_release() raises -> None:
    var context = Context()
    var events = List[Event]()
    events.append(KeyDown(Key.A.value))
    events.append(KeyDown(Key.B.value))
    events.append(KeyUp(Key.B.value))
    _ = apply_events(events, Viewport(), context)
    assert_equal(context.input.key, Key.B)


def test_key_ignores_auto_repeat_of_a_held_key() raises -> None:
    var context = Context()
    var events = List[Event]()
    events.append(KeyDown(Key.A.value))
    events.append(KeyDown(Key.B.value))
    events.append(KeyDown(Key.A.value))
    _ = apply_events(events, Viewport(), context)
    assert_equal(context.input.key, Key.B)


def test_key_typed_counts_a_press_and_each_auto_repeat() raises -> None:
    var context = Context()
    var events = List[Event]()
    events.append(KeyDown(Key.BACKSPACE.value))
    _ = apply_events(events, Viewport(), context)
    assert_true(context.input.key_typed(Key.BACKSPACE))
    assert_true(context.input.key_pressed(Key.BACKSPACE))

    # Held, then auto-repeated: typed again, but not a new press.
    events.clear()
    _ = apply_events(events, Viewport(), context)
    assert_false(context.input.key_typed("backspace"))
    events.append(KeyDown(Key.BACKSPACE.value))
    _ = apply_events(events, Viewport(), context)
    assert_true(context.input.key_typed("backspace"))
    assert_false(context.input.key_pressed(Key.BACKSPACE))


def test_text_joins_a_frames_input_and_clears_the_next() raises -> None:
    var context = Context()
    var events = List[Event]()
    events.append(TextInput("h"))
    events.append(TextInput("é"))
    _ = apply_events(events, Viewport(), context)
    assert_equal(context.input.text, "hé")

    events.clear()
    _ = apply_events(events, Viewport(), context)
    assert_equal(context.input.text, "")


def test_keycodes_outside_ascii_and_named_keys() raises -> None:
    # AltGr's `MODE` (scancode 257 | 1 << 30), a Cyrillic letter's codepoint
    # and an extended key (1 << 29): all valid SDL keycodes a fixed-width
    # bitmask would index out of range.
    var context = Context()
    var events = List[Event]()
    for keycode in [(1 << 30) | 257, 0x0444, (1 << 29) | 1]:
        events.append(KeyDown(keycode))
    _ = apply_events(events, Viewport(), context)
    for keycode in [(1 << 30) | 257, 0x0444, (1 << 29) | 1]:
        assert_true(context.input.key_down(Key(keycode)))
        assert_true(context.input.key_pressed(Key(keycode)))

    events.clear()
    events.append(KeyUp((1 << 30) | 257))
    _ = apply_events(events, Viewport(), context)
    assert_false(context.input.key_down(Key((1 << 30) | 257)))
    assert_true(context.input.key_released(Key((1 << 30) | 257)))
    assert_true(context.input.key_down(Key(0x0444)))


def test_named_key_shift_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073742049))  # left shift
    assert_true(input.key_down("shift"))
    input._held_keys.clear_all()
    input._held_keys.set(Key(1073742053))  # right shift
    assert_true(input.key_down("shift"))


def test_named_key_left_shift_specific() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073742049))
    assert_true(input.key_down("left_shift"))
    assert_equal(input.key_down("right_shift"), False)


def test_named_key_alt_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073742050))  # left alt
    assert_true(input.key_down("alt"))
    input._held_keys.clear_all()
    input._held_keys.set(Key(1073742054))  # right alt
    assert_true(input.key_down("alt"))


def test_named_key_super_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073742051))  # left super
    assert_true(input.key_down("super"))
    input._held_keys.clear_all()
    input._held_keys.set(Key(1073742055))  # right super
    assert_true(input.key_down("super"))


def test_named_key_arrow_down() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741905))
    assert_true(input.key_down("down"))


def test_named_key_arrow_left() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741904))
    assert_true(input.key_down("left"))


def test_named_key_arrow_right() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741903))
    assert_true(input.key_down("right"))


def test_named_key_home() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741898))
    assert_true(input.key_down("home"))


def test_named_key_end() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741901))
    assert_true(input.key_down("end"))


def test_named_key_page_up() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741899))
    assert_true(input.key_down("page_up"))


def test_named_key_page_down() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741902))
    assert_true(input.key_down("page_down"))


def test_named_key_insert() raises -> None:
    var input = Input()
    input._held_keys.set(Key(1073741897))
    assert_true(input.key_down("insert"))


def test_named_key_backspace() raises -> None:
    var input = Input()
    input._held_keys.set(Key(8))
    assert_true(input.key_down("backspace"))


def test_named_key_tab() raises -> None:
    var input = Input()
    input._held_keys.set(Key(9))
    assert_true(input.key_down("tab"))


def test_named_key_delete() raises -> None:
    var input = Input()
    input._held_keys.set(Key(127))
    assert_true(input.key_down("delete"))


def test_named_key_caps_lock() raises -> None:
    var input = Input()
    input._held_keys.set(Key.CAPS_LOCK)
    assert_true(input.key_down("caps_lock"))


def test_named_key_f1() raises -> None:
    var input = Input()
    input._held_keys.set(Key.F1)
    assert_true(input.key_down("f1"))


def test_named_key_f12() raises -> None:
    var input = Input()
    input._held_keys.set(Key.F12)
    assert_true(input.key_down("f12"))


def test_key_pressed_named_key() raises -> None:
    var input = Input()
    input._pressed_keys.set(Key.ESCAPE)
    assert_true(input.key_pressed("escape"))
    assert_equal(input.key_pressed("space"), False)


def test_key_released_named_key() raises -> None:
    var input = Input()
    input._released_keys.set(Key.SPACE)
    assert_true(input.key_released("space"))
    assert_equal(input.key_released("escape"), False)


def test_unknown_named_key_returns_false() raises -> None:
    var input = Input()
    input._held_keys.set(Key(65))
    assert_equal(input.key_down("nonexistent_key"), False)


def test_initial_wheel_and_press_pos_zero() raises -> None:
    var input = Input()
    assert_equal(input.mouse_wheel.x, 0.0)
    assert_equal(input.mouse_wheel.y, 0.0)
    assert_equal(input.mouse_press_position.x, 0.0)
    assert_equal(input.mouse_press_position.y, 0.0)


def test_no_mouse_buttons_down_initially() raises -> None:
    var input = Input()
    assert_equal(input.mouse_down(), False)
    assert_equal(input.mouse_down(2), False)
    assert_equal(input.mouse_pressed(), False)
    assert_equal(input.mouse_released(), False)


def test_mouse_down_default_button() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 1
    assert_true(input.mouse_down())
    assert_equal(input.mouse_down(2), False)


def test_mouse_down_specific_button() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 3
    assert_true(input.mouse_down(3))
    assert_equal(input.mouse_down(1), False)


def test_multiple_mouse_buttons_held_independently() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 1
    input._held_buttons |= 1 << 2
    assert_true(input.mouse_down(1))
    assert_true(input.mouse_down(2))
    assert_equal(input.mouse_down(3), False)


def test_mouse_pressed_button() raises -> None:
    var input = Input()
    input._pressed_buttons |= 1 << 2
    assert_true(input.mouse_pressed(2))
    assert_equal(input.mouse_pressed(1), False)


def test_mouse_released_button() raises -> None:
    var input = Input()
    input._released_buttons |= 1 << 1
    assert_true(input.mouse_released())
    assert_equal(input.mouse_released(2), False)


def test_new_frame_clears_pressed_and_released() raises -> None:
    var input = Input()
    input._pressed_keys.set(Key(65))
    input._released_keys.set(Key(66))
    input._new_frame()
    assert_equal(input.key_pressed(Key(65)), False)
    assert_equal(input.key_released(Key(66)), False)


def test_new_frame_clears_wheel_and_edge_buttons() raises -> None:
    var input = Input()
    input.mouse_wheel = Vector2D(3.0, -2.0)
    input._pressed_buttons |= 1 << 1
    input._released_buttons |= 1 << 2
    input._new_frame()
    assert_equal(input.mouse_wheel.x, 0.0)
    assert_equal(input.mouse_wheel.y, 0.0)
    assert_equal(input.mouse_pressed(1), False)
    assert_equal(input.mouse_released(2), False)


def test_new_frame_leaves_held_state_alone() raises -> None:
    # A key or button held across the frame boundary is not an edge — only
    # the pressed/released bits and the per-frame wheel delta reset.
    var input = Input()
    input._held_keys.set(Key(65))
    input._held_buttons |= 1 << 1
    input._new_frame()
    assert_true(input.key_down(Key(65)))
    assert_true(input.mouse_down(1))


def test_set_mouse_writes_all_three_fields() raises -> None:
    var input = Input()
    input._set_mouse(12.5, -30.25)
    assert_equal(input.mouse.x, 12.5)
    assert_equal(input.mouse.y, -30.25)
    assert_equal(input.mouse_x, 12)
    assert_equal(input.mouse_y, -31)


def test_set_mouse_floors_negative_coordinates() raises -> None:
    # World space is centred, so half the screen is negative. Flooring and
    # truncating disagree there: Int(-0.5) is 0, floor(-0.5) is -1.
    var input = Input()
    input._set_mouse(-0.5, -1.5)
    assert_equal(input.mouse_x, -1)
    assert_equal(input.mouse_y, -2)


def test_set_mouse_int_fields_track_the_position() raises -> None:
    # The regression this method exists to prevent: a code path that updated
    # mouse_x/mouse_y while leaving `mouse` at its previous value.
    var input = Input()
    input._set_mouse(5.0, 5.0)
    input._set_mouse(-40.75, 60.25)
    assert_equal(input.mouse.x, -40.75)
    assert_equal(input.mouse.y, 60.25)
    assert_equal(input.mouse_x, -41)
    assert_equal(input.mouse_y, 60)


def test_mouse_is_a_position_and_the_wheel_a_displacement() raises -> None:
    # The split this type distinction exists for: a drag is the difference
    # between two locations, which is a Vector2D, while the wheel already is
    # one.
    var input = Input()
    input.mouse_press_position = Point2D(10.0, 20.0)
    input._set_mouse(13.0, 24.0)
    var drag: Vector2D = input.mouse - input.mouse_press_position
    assert_equal(drag, Vector2D(3.0, 4.0))
    assert_equal(input.mouse_press_position + drag, input.mouse)
    input.mouse_wheel = Vector2D(0.0, -1.0)
    assert_equal(input.mouse_wheel.mag(), 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
