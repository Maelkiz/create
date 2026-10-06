from std.testing import TestSuite, assert_equal

from create.core.context import Context
from create.core.editable_text import EditableText
from create.core.key import Key
from create.core._events import apply_events
from create.render._viewport import Viewport
from create._window.event import Event, KeyDown, KeyUp, TextInput


def _type(mut field: EditableText, var events: List[Event]) raises:
    """Fold `events` as one frame and feed it to `field`."""
    var context = Context()
    _ = apply_events(events, Viewport(), context)
    field.update(context.input)


def test_starts_with_the_caret_after_its_text() raises -> None:
    var field = EditableText("abc")
    assert_equal(field.before_caret(), "abc")
    assert_equal(field.after_caret(), "")
    assert_equal(EditableText().text, "")


def test_update_appends_typed_text() raises -> None:
    var field = EditableText()
    _type(field, [TextInput("h"), TextInput("é")])
    assert_equal(field.text, "hé")
    assert_equal(field.before_caret(), "hé")


def test_typing_mid_string_inserts_at_the_caret() raises -> None:
    var field = EditableText("ac")
    _type(field, [KeyDown(Key.LEFT.value)])
    _type(field, [TextInput("b")])
    assert_equal(field.text, "abc")
    assert_equal(field.before_caret(), "ab")


def test_backspace_removes_a_whole_character() raises -> None:
    var field = EditableText("Zoë")
    _type(field, [KeyDown(Key.BACKSPACE.value)])
    assert_equal(field.text, "Zo")
    field.delete_backward()
    field.delete_backward()
    field.delete_backward()
    assert_equal(field.text, "")


def test_delete_removes_the_character_after_the_caret() raises -> None:
    var field = EditableText("éa")
    _type(field, [KeyDown(Key.HOME.value)])
    _type(field, [KeyDown(Key.DELETE.value)])
    assert_equal(field.text, "a")
    assert_equal(field.before_caret(), "")
    _type(field, [KeyDown(Key.END.value)])
    field.delete_forward()
    assert_equal(field.text, "a")


def test_caret_moves_by_characters_and_stops_at_the_ends() raises -> None:
    var field = EditableText("aé")
    field.move_left()
    assert_equal(field.before_caret(), "a")
    field.move_left()
    field.move_left()
    assert_equal(field.before_caret(), "")
    field.move_right()
    field.move_right()
    field.move_right()
    assert_equal(field.before_caret(), "aé")


def test_held_backspace_keeps_deleting() raises -> None:
    # A second KeyDown while held is an auto-repeat, which key_typed counts.
    var field = EditableText("abc")
    var context = Context()
    for _ in range(2):
        var events: List[Event] = [KeyDown(Key.BACKSPACE.value)]
        _ = apply_events(events, Viewport(), context)
        field.update(context.input)
    assert_equal(field.text, "a")


def test_reassigning_text_keeps_the_caret_inside_it() raises -> None:
    var field = EditableText("hello")
    field.text = "é"
    assert_equal(field.before_caret(), "é")
    field.text = ""
    assert_equal(field.before_caret(), "")
    _type(field, [TextInput("x")])
    assert_equal(field.text, "x")


def test_prints_as_source() raises -> None:
    assert_equal(String(EditableText("hi")), 'EditableText(text="hi")')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
