# The consumer-side gate — a sketch built from outside the library.
#
# `mojo precompile` checks the library's own bodies but never a caller, so
# this checks what only a program can: that a struct conforms to `Program`,
# that `run[T]` and `run_headless[T]` instantiate with it, and that a call
# a sketch writes (a tuple for a `Point2D`) resolves.
# The pre-commit hook builds this file and the suite runs it. Keep it
# minimal: it is built on every commit.

from std.testing import TestSuite, assert_equal, assert_true

from create import *


@fieldwise_init
struct Smoke(Program):
    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Smoke:
        return Smoke()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.text("Smoke Test", (0, 0))


def _windowed_entry_point() raises:
    """The windowed path — type-checked here, never called.

    `run[T]` opens a window and blocks, so the suite can only compile it. Both
    entry points take the same `Program`, but not the same call path, so
    without this a change to `run[T]` could break every real sketch while the
    headless test stayed green.
    """
    run[Smoke]("Smoke Test", width=320, height=240)


def _gpu_entry_point() raises:
    """The GPU branch of `run`, likewise type-checked and never called.

    It reaches a separate loop and renderer, so the windowed gate above says
    nothing about it.
    """
    run[Smoke]("Smoke Test", width=320, height=240, backend=RenderBackend.GPU)


def test_smoke_renders_through_the_public_api() raises -> None:
    var m = run_headless[Smoke](320, 240)
    var clear = Color(200, 200, 200)
    assert_equal(m.pixel(5, 5), clear)
    var inked = 0
    for y in range(m.height):
        for x in range(m.width):
            if m.pixel(x, y) != clear:
                inked += 1
    assert_true(inked > 0, "the text drew nothing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
