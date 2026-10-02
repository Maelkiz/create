from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from create.core.context import Context
from create.core.gamepad import Gamepad
from create.core.gamepad_button import GamepadButton
from create.core._events import apply_events
from create.render._viewport import Viewport
from create._window.event import (
    Event,
    GamepadAdded,
    GamepadAxisMoved,
    GamepadButtonDown,
    GamepadButtonUp,
    GamepadRemoved,
)
from create.math.vector2d import Vector2D


def _frame(mut context: Context, var events: List[Event]):
    _ = apply_events(events, Viewport(), context)


def test_no_gamepad_reads_disconnected_and_idle() raises -> None:
    var context = Context()
    var pad = context.input.gamepad()
    assert_false(pad.connected)
    assert_false(pad.button_down(GamepadButton.SOUTH))
    assert_equal(pad.left_stick, Vector2D.ZERO)
    assert_equal(pad.button, -1)
    assert_false(context.input.gamepad(3).connected)
    assert_false(context.input.gamepad(-1).connected)


def test_added_gamepad_takes_slot_zero() raises -> None:
    var context = Context()
    _frame(context, [Event(GamepadAdded(42))])
    assert_true(context.input.gamepad().connected)
    assert_false(context.input.gamepad(1).connected)


def test_button_down_pressed_released_lifecycle() raises -> None:
    var context = Context()
    _frame(
        context,
        [
            Event(GamepadAdded(1)),
            Event(GamepadButtonDown(1, GamepadButton.START)),
        ],
    )
    var pad = context.input.gamepad()
    assert_true(pad.button_down(GamepadButton.START))
    assert_true(pad.button_pressed(GamepadButton.START))
    assert_equal(pad.button, GamepadButton.START)

    _frame(context, [])
    pad = context.input.gamepad()
    assert_true(pad.button_down(GamepadButton.START))
    assert_false(pad.button_pressed(GamepadButton.START))

    _frame(context, [Event(GamepadButtonUp(1, GamepadButton.START))])
    pad = context.input.gamepad()
    assert_false(pad.button_down(GamepadButton.START))
    assert_true(pad.button_released(GamepadButton.START))
    assert_equal(pad.button, GamepadButton.START)

    _frame(context, [])
    assert_false(context.input.gamepad().button_released(GamepadButton.START))


def test_events_reach_the_pad_they_name() raises -> None:
    var context = Context()
    _frame(
        context,
        [
            Event(GamepadAdded(10)),
            Event(GamepadAdded(20)),
            Event(GamepadButtonDown(20, GamepadButton.SOUTH)),
            Event(GamepadButtonDown(99, GamepadButton.EAST)),
        ],
    )
    assert_false(context.input.gamepad(0).button_down(GamepadButton.SOUTH))
    assert_true(context.input.gamepad(1).button_down(GamepadButton.SOUTH))
    assert_false(context.input.gamepad(0).button_down(GamepadButton.EAST))
    assert_false(context.input.gamepad(1).button_down(GamepadButton.EAST))


def test_stick_is_y_up() raises -> None:
    var context = Context()
    # SDL reports pushing up as negative y.
    _frame(
        context,
        [Event(GamepadAdded(1)), Event(GamepadAxisMoved(1, 1, -1.0))],
    )
    var stick = context.input.gamepad().left_stick
    assert_almost_equal(stick.x, 0.0)
    assert_almost_equal(stick.y, 1.0)


def test_stick_inside_dead_zone_reads_zero() raises -> None:
    var context = Context()
    _frame(
        context,
        [
            Event(GamepadAdded(1)),
            Event(GamepadAxisMoved(1, 2, 0.15)),
            Event(GamepadAxisMoved(1, 3, 0.1)),
        ],
    )
    assert_equal(context.input.gamepad().right_stick, Vector2D.ZERO)


def test_stick_rescales_past_dead_zone() raises -> None:
    var context = Context()
    var half = Gamepad.STICK_DEAD_ZONE + (1.0 - Gamepad.STICK_DEAD_ZONE) / 2
    _frame(
        context,
        [Event(GamepadAdded(1)), Event(GamepadAxisMoved(1, 0, half))],
    )
    assert_almost_equal(context.input.gamepad().left_stick.x, 0.5)


def test_diagonal_stick_capped_at_unit_length() raises -> None:
    var context = Context()
    _frame(
        context,
        [
            Event(GamepadAdded(1)),
            Event(GamepadAxisMoved(1, 0, 1.0)),
            Event(GamepadAxisMoved(1, 1, 1.0)),
        ],
    )
    var stick = context.input.gamepad().left_stick
    assert_almost_equal(stick.mag(), 1.0)
    assert_true(stick.x > 0 and stick.y < 0)


def test_triggers() raises -> None:
    var context = Context()
    _frame(
        context,
        [
            Event(GamepadAdded(1)),
            Event(GamepadAxisMoved(1, 4, 0.25)),
            Event(GamepadAxisMoved(1, 5, 1.0)),
        ],
    )
    assert_equal(context.input.gamepad().left_trigger, 0.25)
    assert_equal(context.input.gamepad().right_trigger, 1.0)


def test_removed_pad_frees_its_slot_and_others_stay() raises -> None:
    var context = Context()
    _frame(context, [Event(GamepadAdded(1)), Event(GamepadAdded(2))])
    _frame(
        context,
        [Event(GamepadButtonDown(1, 0)), Event(GamepadRemoved(1))],
    )
    assert_false(context.input.gamepad(0).connected)
    assert_false(context.input.gamepad(0).button_down(0))
    assert_true(context.input.gamepad(1).connected)

    _frame(context, [Event(GamepadAdded(3)), Event(GamepadButtonDown(3, 1))])
    assert_true(context.input.gamepad(0).connected)
    assert_true(context.input.gamepad(0).button_down(1))
    assert_false(context.input.gamepad(2).connected)


def test_duplicate_add_keeps_one_slot() raises -> None:
    var context = Context()
    _frame(context, [Event(GamepadAdded(5)), Event(GamepadAdded(5))])
    assert_false(context.input.gamepad(1).connected)


def test_prints_keyword_form() raises -> None:
    assert_equal(
        String(Gamepad()),
        (
            "Gamepad(connected=False, left_stick=Vector2D(0.0, 0.0),"
            " right_stick=Vector2D(0.0, 0.0), left_trigger=0.0,"
            " right_trigger=0.0, button=-1)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
