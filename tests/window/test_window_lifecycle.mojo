"""Headless lifecycle tests for `Window`. Requires `SDL_VIDEODRIVER=dummy`
(no real display) -- forced by this file's `main`.
"""

from std.os import setenv
from std.testing import TestSuite, assert_true, assert_false
from create._window import Window


def test_open_then_close() raises -> None:
    var w = Window("t", 100, 100)
    assert_true(w.is_open())
    w.close()
    assert_false(w.is_open())


def test_sequential_create_destroy() raises -> None:
    for _ in range(3):
        var w = Window("t", 64, 64)
        assert_true(w.is_open())


def test_maximized_opens_and_reports_a_size() raises -> None:
    """The dummy driver has no work area to maximize into, so the size it
    reports back is not pinned to anything -- what matters is that the flag
    reaches `SDL_CreateWindow`, the window opens, and the queried size is
    used in place of the request without tripping the teardown path."""
    var w = Window("t", 64, 64, maximized=True)
    assert_true(w.is_open())
    assert_true(w.width() > 0)
    assert_true(w.height() > 0)


def test_ticks_monotonic() raises -> None:
    var w = Window("t", 64, 64)
    var a = w.ticks()
    var b = w.ticks()
    assert_true(b >= a)


def test_events_empty_when_none_pending() raises -> None:
    var w = Window("t", 64, 64)
    var events = w.events()
    assert_true(len(events) == 0)


def main() raises:
    # Every `Window` here expects SDL's dummy driver: no real window opens on
    # the desktop, and `GLWindow` is refused a context. `pixi run test` picks
    # the driver per display, so pin it before the first SDL call reads it.
    _ = setenv("SDL_VIDEODRIVER", "dummy", True)
    TestSuite.discover_tests[__functions_in_module()]().run()
