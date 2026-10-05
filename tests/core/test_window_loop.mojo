# The windowed loops send the window dials only when the program changes
# them. Driven through a stand-in window, so no display is needed.

from std.testing import TestSuite, assert_equal

from create import *
from create._window import NativeWindow
from create._window.event import Event
from create.core._window_loop import _AppliedWindow, _apply_window_dials


struct CountingWindow(NativeWindow):
    """Counts what it is told, and remembers the last of it."""

    var titles: Int
    var resizes: Int
    var title: String
    var resizable: Bool

    def __init__(out self):
        self.titles = 0
        self.resizes = 0
        self.title = ""
        self.resizable = True

    def is_open(self) -> Bool:
        return True

    def close(mut self):
        pass

    def ticks(self) raises -> Int:
        return 0

    def rumble_gamepad(
        self,
        id: Int,
        low_frequency: Float64,
        high_frequency: Float64,
        seconds: Float64,
    ) raises:
        pass

    def events(mut self) raises -> List[Event]:
        return []

    def set_title(mut self, title: String) raises:
        self.titles += 1
        self.title = title

    def set_resizable(mut self, enabled: Bool) raises:
        self.resizes += 1
        self.resizable = enabled

    def set_mode(
        mut self, fullscreen: Bool, borderless: Bool, maximized: Bool
    ) raises:
        pass


def test_an_unchanged_dial_is_not_sent() raises -> None:
    var context = Context()
    context.title("Game")
    var applied = _AppliedWindow(context)
    var win = CountingWindow()
    for _ in range(3):
        context.title("Game")
        _apply_window_dials(win, applied, context)
    assert_equal(win.titles, 0)
    assert_equal(win.resizes, 0)


def test_a_changed_dial_is_sent_once() raises -> None:
    var context = Context()
    context.title("Game")
    var applied = _AppliedWindow(context)
    var win = CountingWindow()
    context.title("Game — level 2")
    context.resizable(False)
    _apply_window_dials(win, applied, context)
    _apply_window_dials(win, applied, context)
    assert_equal(win.titles, 1)
    assert_equal(win.title, "Game — level 2")
    assert_equal(win.resizes, 1)
    assert_equal(win.resizable, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
