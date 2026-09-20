from std.testing import TestSuite, assert_equal, assert_true
from create.render.input import Input
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def test_initial_mouse_position() raises -> None:
    var input = Input()
    assert_equal(input.mouse_x, 0)
    assert_equal(input.mouse_y, 0)
    assert_equal(input.mouse.x, 0.0)
    assert_equal(input.mouse.y, 0.0)


def test_initial_mouse_not_pressed() raises -> None:
    var input = Input()
    assert_equal(input.mouse_pressed, False)


def test_no_keys_down_initially() raises -> None:
    var input = Input()
    assert_equal(input.is_key_down(65), False)
    assert_equal(input.is_key_down("a"), False)


def test_is_key_down_by_keycode() raises -> None:
    var input = Input()
    input._held_keys.set(65)
    assert_true(input.is_key_down(65))
    assert_equal(input.is_key_down(66), False)


def test_is_key_down_by_string() raises -> None:
    var input = Input()
    input._held_keys.set(ord("a"))
    assert_true(input.is_key_down("a"))
    assert_equal(input.is_key_down("b"), False)


def test_is_key_down_case_insensitive() raises -> None:
    var input = Input()
    input._held_keys.set(ord("z"))
    assert_true(input.is_key_down("Z"))


def test_just_pressed_keycode() raises -> None:
    var input = Input()
    input._just_pressed.set(65)
    assert_true(input.just_pressed(65))
    assert_equal(input.just_pressed(66), False)


def test_just_pressed_string() raises -> None:
    var input = Input()
    input._just_pressed.set(ord("w"))
    assert_true(input.just_pressed("w"))


def test_just_released_keycode() raises -> None:
    var input = Input()
    input._just_released.set(65)
    assert_true(input.just_released(65))
    assert_equal(input.just_released(66), False)


def test_just_released_string() raises -> None:
    var input = Input()
    input._just_released.set(ord("s"))
    assert_true(input.just_released("s"))


def test_multiple_keys_held() raises -> None:
    var input = Input()
    input._held_keys.set(ord("a"))
    input._held_keys.set(ord("d"))
    assert_true(input.is_key_down("a"))
    assert_true(input.is_key_down("d"))
    assert_equal(input.is_key_down("w"), False)


def test_named_key_escape() raises -> None:
    var input = Input()
    input._held_keys.set(27)
    assert_true(input.is_key_down("escape"))


def test_named_key_space() raises -> None:
    var input = Input()
    input._held_keys.set(32)
    assert_true(input.is_key_down("space"))


def test_named_key_enter() raises -> None:
    var input = Input()
    input._held_keys.set(13)
    assert_true(input.is_key_down("enter"))


def test_named_key_arrow_up() raises -> None:
    var input = Input()
    input._held_keys.set(1073741906)
    assert_true(input.is_key_down("up"))


def test_named_key_ctrl_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(1073742048)  # left ctrl
    assert_true(input.is_key_down("ctrl"))
    input._held_keys.clear_all()
    input._held_keys.set(1073742052)  # right ctrl
    assert_true(input.is_key_down("ctrl"))


def test_mouse_button_initial() raises -> None:
    var input = Input()
    assert_equal(input.mouse_button, 0)


def test_named_key_shift_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(1073742049)  # left shift
    assert_true(input.is_key_down("shift"))
    input._held_keys.clear_all()
    input._held_keys.set(1073742053)  # right shift
    assert_true(input.is_key_down("shift"))


def test_named_key_left_shift_specific() raises -> None:
    var input = Input()
    input._held_keys.set(1073742049)
    assert_true(input.is_key_down("left_shift"))
    assert_equal(input.is_key_down("right_shift"), False)


def test_named_key_alt_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(1073742050)  # left alt
    assert_true(input.is_key_down("alt"))
    input._held_keys.clear_all()
    input._held_keys.set(1073742054)  # right alt
    assert_true(input.is_key_down("alt"))


def test_named_key_super_both_sides() raises -> None:
    var input = Input()
    input._held_keys.set(1073742051)  # left super
    assert_true(input.is_key_down("super"))
    input._held_keys.clear_all()
    input._held_keys.set(1073742055)  # right super
    assert_true(input.is_key_down("super"))


def test_named_key_arrow_down() raises -> None:
    var input = Input()
    input._held_keys.set(1073741905)
    assert_true(input.is_key_down("down"))


def test_named_key_arrow_left() raises -> None:
    var input = Input()
    input._held_keys.set(1073741904)
    assert_true(input.is_key_down("left"))


def test_named_key_arrow_right() raises -> None:
    var input = Input()
    input._held_keys.set(1073741903)
    assert_true(input.is_key_down("right"))


def test_named_key_home() raises -> None:
    var input = Input()
    input._held_keys.set(1073741898)
    assert_true(input.is_key_down("home"))


def test_named_key_end() raises -> None:
    var input = Input()
    input._held_keys.set(1073741901)
    assert_true(input.is_key_down("end"))


def test_named_key_page_up() raises -> None:
    var input = Input()
    input._held_keys.set(1073741899)
    assert_true(input.is_key_down("page_up"))


def test_named_key_page_down() raises -> None:
    var input = Input()
    input._held_keys.set(1073741902)
    assert_true(input.is_key_down("page_down"))


def test_named_key_insert() raises -> None:
    var input = Input()
    input._held_keys.set(1073741897)
    assert_true(input.is_key_down("insert"))


def test_named_key_backspace() raises -> None:
    var input = Input()
    input._held_keys.set(8)
    assert_true(input.is_key_down("backspace"))


def test_named_key_tab() raises -> None:
    var input = Input()
    input._held_keys.set(9)
    assert_true(input.is_key_down("tab"))


def test_named_key_delete() raises -> None:
    var input = Input()
    input._held_keys.set(127)
    assert_true(input.is_key_down("delete"))


def test_named_key_caps_lock() raises -> None:
    var input = Input()
    input._held_keys.set(1073741881)
    assert_true(input.is_key_down("caps_lock"))


def test_named_key_f1() raises -> None:
    var input = Input()
    input._held_keys.set(1073741882)
    assert_true(input.is_key_down("f1"))


def test_named_key_f12() raises -> None:
    var input = Input()
    input._held_keys.set(1073741893)
    assert_true(input.is_key_down("f12"))


def test_just_pressed_named_key() raises -> None:
    var input = Input()
    input._just_pressed.set(27)
    assert_true(input.just_pressed("escape"))
    assert_equal(input.just_pressed("space"), False)


def test_just_released_named_key() raises -> None:
    var input = Input()
    input._just_released.set(32)
    assert_true(input.just_released("space"))
    assert_equal(input.just_released("escape"), False)


def test_unknown_named_key_returns_false() raises -> None:
    var input = Input()
    input._held_keys.set(65)
    assert_equal(input.is_key_down("nonexistent_key"), False)


def test_initial_wheel_and_press_pos_zero() raises -> None:
    var input = Input()
    assert_equal(input.wheel.x, 0.0)
    assert_equal(input.wheel.y, 0.0)
    assert_equal(input.mouse_press_pos.x, 0.0)
    assert_equal(input.mouse_press_pos.y, 0.0)


def test_no_mouse_buttons_down_initially() raises -> None:
    var input = Input()
    assert_equal(input.is_mouse_down(), False)
    assert_equal(input.is_mouse_down(2), False)
    assert_equal(input.mouse_just_pressed(), False)
    assert_equal(input.mouse_just_released(), False)


def test_is_mouse_down_default_button() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 1
    assert_true(input.is_mouse_down())
    assert_equal(input.is_mouse_down(2), False)


def test_is_mouse_down_specific_button() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 3
    assert_true(input.is_mouse_down(3))
    assert_equal(input.is_mouse_down(1), False)


def test_multiple_mouse_buttons_held_independently() raises -> None:
    var input = Input()
    input._held_buttons |= 1 << 1
    input._held_buttons |= 1 << 2
    assert_true(input.is_mouse_down(1))
    assert_true(input.is_mouse_down(2))
    assert_equal(input.is_mouse_down(3), False)


def test_mouse_just_pressed_button() raises -> None:
    var input = Input()
    input._pressed_buttons |= 1 << 2
    assert_true(input.mouse_just_pressed(2))
    assert_equal(input.mouse_just_pressed(1), False)


def test_mouse_just_released_button() raises -> None:
    var input = Input()
    input._released_buttons |= 1 << 1
    assert_true(input.mouse_just_released())
    assert_equal(input.mouse_just_released(2), False)


def test_new_frame_clears_just_pressed_and_released() raises -> None:
    var input = Input()
    input._just_pressed.set(65)
    input._just_released.set(66)
    input._new_frame()
    assert_equal(input.just_pressed(65), False)
    assert_equal(input.just_released(66), False)


def test_new_frame_clears_wheel_and_edge_buttons() raises -> None:
    var input = Input()
    input.wheel = Vector2D(3.0, -2.0)
    input._pressed_buttons |= 1 << 1
    input._released_buttons |= 1 << 2
    input._new_frame()
    assert_equal(input.wheel.x, 0.0)
    assert_equal(input.wheel.y, 0.0)
    assert_equal(input.mouse_just_pressed(1), False)
    assert_equal(input.mouse_just_released(2), False)


def test_new_frame_leaves_held_state_alone() raises -> None:
    # A key or button held across the frame boundary is not an edge — only
    # the "just" bits and the per-frame wheel delta reset.
    var input = Input()
    input._held_keys.set(65)
    input._held_buttons |= 1 << 1
    input._new_frame()
    assert_true(input.is_key_down(65))
    assert_true(input.is_mouse_down(1))


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
    input.mouse_press_pos = Point2D(10.0, 20.0)
    input._set_mouse(13.0, 24.0)
    var drag: Vector2D = input.mouse - input.mouse_press_pos
    assert_equal(drag, Vector2D(3.0, 4.0))
    assert_equal(input.mouse_press_pos + drag, input.mouse)
    input.wheel = Vector2D(0.0, -1.0)
    assert_equal(input.wheel.mag(), 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
