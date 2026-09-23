"""Verifies `Window.__init__` propagates SDL init failures with the
underlying `SDL_GetError()` message. Forces the failure via an invalid
`SDL_VIDEODRIVER` and restores the original value afterward -- kept in its
own file (its own `mojo run` process) so mutating this env var can't affect
any other test.
"""

from std.os import setenv, getenv
from std.testing import TestSuite, assert_raises
from create._window import Window


def test_init_video_failure_reports_sdl_error() raises -> None:
    var original = getenv("SDL_VIDEODRIVER")
    _ = setenv("SDL_VIDEODRIVER", "bogus_driver_xyz", True)
    try:
        with assert_raises(contains="SDL_Init(SDL_INIT_VIDEO) failed"):
            var w = Window("t", 100, 100)
    finally:
        _ = setenv("SDL_VIDEODRIVER", original, True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
