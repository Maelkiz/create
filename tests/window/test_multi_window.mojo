"""Verifies two `Window`s can be alive at once. `Window` independently
`dlopen`s `libSDL3.so` and calls `SDL_Init`/`SDL_QuitSubSystem`, relying on
SDL's internal per-subsystem ref-count (see `SDL.quit_video`'s docstring)
rather than tracking its own live-window count -- this exercises that
assumption instead of just asserting it in prose.
"""

from std.os import setenv
from std.testing import TestSuite, assert_true, assert_false

from create._window import Window


def test_two_windows_live_at_once() raises -> None:
    var a = Window("a", 64, 64)
    var b = Window("b", 32, 32)
    assert_true(a.is_open())
    assert_true(b.is_open())

    var ticks_a = a.ticks()
    var ticks_b = b.ticks()
    assert_true(ticks_b >= ticks_a)

    var events_a = a.events()
    var events_b = b.events()
    assert_true(len(events_a) == 0)
    assert_true(len(events_b) == 0)

    assert_true(a.width() == 64 and a.height() == 64)
    assert_true(b.width() == 32 and b.height() == 32)


def test_closing_one_window_does_not_affect_the_other() raises -> None:
    var a = Window("a", 64, 64)
    var b = Window("b", 64, 64)
    a.close()
    assert_false(a.is_open())
    assert_true(b.is_open())
    assert_true(len(b.events()) == 0)


def main() raises:
    # Every `Window` here expects SDL's dummy driver: no real window opens on
    # the desktop, and `GLWindow` is refused a context. `pixi run test` picks
    # the driver per display, so pin it before the first SDL call reads it.
    _ = setenv("SDL_VIDEODRIVER", "dummy", True)
    TestSuite.discover_tests[__functions_in_module()]().run()
