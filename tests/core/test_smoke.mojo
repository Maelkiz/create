# The consumer-side gate — a program built from outside the library.
#
# Type-checks the trait surface, `run[T]` instantiation, and the
# Context/Input/Canvas signatures, none of which `mojo precompile` sees. The
# pre-commit hook builds this file; the suite also runs it, which the windowed
# version could not do. Keep it minimal: it runs on every commit, and its cost
# must not grow with the example count.

from std.memory import ArcPointer
from std.testing import TestSuite, assert_equal

from create import *
from create.audio import Audio, Sound


@fieldwise_init
struct Smoke(Program):
    var x: Float64
    var audio: Audio

    @staticmethod
    def create(mut ctx: Context) raises -> Smoke:
        ctx.exit_on_escape = True
        return Smoke(0.0, Audio())

    def update(mut self, mut ctx: Context, input: Input) raises:
        self.audio.update()
        if input.is_key_down("right"):
            self.x += 100.0 * ctx.time.delta
        if input.just_pressed("space"):
            _ = self.audio.play(
                ArcPointer(Sound.from_pcm(List[Int16](length=1, fill=0)))
            )

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color.WHITE)
        canvas.fill(Color.RED)
        canvas.circle((self.x, 0.0), 20)


def _windowed_entry_point() raises:
    """The windowed path — type-checked here, never called.

    `run[T]` opens a window and blocks, so the suite can only compile it. Both
    entry points take the same `Program`, but not the same call path, so
    without this a change to `run[T]` could break every real sketch while the
    headless test stayed green.
    """
    run[Smoke]("Smoke Test", 320, 240)


def _gpu_entry_point() raises:
    """The GPU branch of `run`, likewise type-checked and never called.

    It reaches an entirely separate loop and renderer, so the windowed gate
    above says nothing about it. Compiling costs nothing at runtime, which
    matters here: the pre-commit hook builds this file.
    """
    run[Smoke]("Smoke Test", 320, 240, RenderBackend.GPU)


def test_smoke_renders_through_the_public_api() raises -> None:
    var m = run_headless[Smoke](320, 240)
    assert_equal(m.pixel(160, 120), Color.RED)
    assert_equal(m.pixel(5, 5), Color.WHITE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
