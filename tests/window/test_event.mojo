"""Unit tests for `window.event` — Variant construction and field access."""

from std.testing import TestSuite, assert_equal, assert_true, assert_false
from create._window import (
    Event,
    Quit,
    Resized,
    KeyDown,
    KeyUp,
    MouseMoved,
    MouseButtonDown,
    MouseButtonUp,
    MouseWheel,
)


def test_quit_isa() raises -> None:
    var e: Event = Quit()
    assert_true(e.isa[Quit]())
    assert_false(e.isa[Resized]())


def test_resized_fields() raises -> None:
    var e: Event = Resized(800, 600)
    assert_true(e.isa[Resized]())
    assert_equal(e[Resized].width, 800)
    assert_equal(e[Resized].height, 600)


def test_keydown_fields() raises -> None:
    var e: Event = KeyDown(42)
    assert_true(e.isa[KeyDown]())
    assert_equal(e[KeyDown].keycode, 42)


def test_keyup_fields() raises -> None:
    var e: Event = KeyUp(7)
    assert_true(e.isa[KeyUp]())
    assert_equal(e[KeyUp].keycode, 7)


def test_mousemoved_fields() raises -> None:
    var e: Event = MouseMoved(12, 34)
    assert_true(e.isa[MouseMoved]())
    assert_equal(e[MouseMoved].x, 12)
    assert_equal(e[MouseMoved].y, 34)


def test_mousebuttondown_fields() raises -> None:
    var e: Event = MouseButtonDown(1, 5, 6)
    assert_true(e.isa[MouseButtonDown]())
    assert_equal(e[MouseButtonDown].button, 1)
    assert_equal(e[MouseButtonDown].x, 5)
    assert_equal(e[MouseButtonDown].y, 6)


def test_mousebuttonup_fields() raises -> None:
    var e: Event = MouseButtonUp(2, 9, 10)
    assert_true(e.isa[MouseButtonUp]())
    assert_equal(e[MouseButtonUp].button, 2)
    assert_equal(e[MouseButtonUp].x, 9)
    assert_equal(e[MouseButtonUp].y, 10)


def test_mousewheel_fields() raises -> None:
    var e: Event = MouseWheel(0, -1)
    assert_true(e.isa[MouseWheel]())
    assert_equal(e[MouseWheel].x, 0)
    assert_equal(e[MouseWheel].y, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
