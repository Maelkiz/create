"""Failure-path tests for `GLWindow`. Requires `SDL_VIDEODRIVER=dummy` (no
real display) -- forced by this file's `main`.

The dummy driver has no GPU backend, so `SDL_CreateWindow` itself refuses
the `SDL_WINDOW_OPENGL` flag under it (verified empirically, not assumed)
-- `SDL_GL_CreateContext` is never even reached. `GLWindow` construction
therefore always fails cleanly here, which is exactly the teardown path this
file exercises. The success path -- construction, `get_proc_address()`,
`swap_buffers()` -- runs under the offscreen driver in the GL tests in
`tests/render/`, which build a real context through `GLWindow`. The shared
event-translation logic `GLWindow.events()` relies on is covered in
`test_translate_event.mojo`, since that part needs no live window at all.
"""

from std.os import setenv
from std.testing import TestSuite, assert_raises
from create._window import GLWindow


def test_construction_fails_cleanly_under_dummy_driver() raises -> None:
    with assert_raises(contains="SDL_CreateWindow failed"):
        var w = GLWindow("t", 64, 64)


def test_fullscreen_construction_fails_cleanly_under_dummy_driver() raises -> (
    None
):
    """Same refusal, with the fullscreen flag set.

    There is no headless success path (see the module docstring), so this is
    what the argument can be tested against: it reaches `SDL_CreateWindow`
    and the failure teardown is the same one. A real fullscreen GL window is
    a manual check.
    """
    with assert_raises(contains="SDL_CreateWindow failed"):
        var w = GLWindow("t", 64, 64, fullscreen=True)


def test_maximized_construction_fails_cleanly_under_dummy_driver() raises -> (
    None
):
    """Same refusal, with the maximized flag set -- see the fullscreen case
    above for why that is all this can assert headlessly."""
    with assert_raises(contains="SDL_CreateWindow failed"):
        var w = GLWindow("t", 64, 64, maximized=True)


def test_sequential_failed_construction_does_not_crash() raises -> None:
    for _ in range(3):
        with assert_raises(contains="SDL_CreateWindow failed"):
            var w = GLWindow("t", 64, 64)


def main() raises:
    # Every `Window` here expects SDL's dummy driver: no real window opens on
    # the desktop, and `GLWindow` is refused a context. `pixi run test` picks
    # the driver per display, so pin it before the first SDL call reads it.
    _ = setenv("SDL_VIDEODRIVER", "dummy", True)
    TestSuite.discover_tests[__functions_in_module()]().run()
