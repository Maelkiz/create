# Regression coverage for post-render clipping and the sized sprite overload
# — kept out of test_frame.mojo, already the package's slowest file, since
# both tests here use larger buffers.

from std.testing import TestSuite, assert_equal

from create import *
from create.core.headless import run_headless
from create.render.surface import MemorySurface
from create.sprite.sprite import Sprite


@fieldwise_init
struct OverflowingRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> OverflowingRect:
        return OverflowingRect(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.outline(enabled=False)
        frame.fill(Color.GREEN)
        # Far larger than the 100x50 design — if the raster loop didn't
        # already clip to the framebuffer, this alone would prove nothing, so
        # the value is entirely in what happens after render.
        frame.rectangle(0.0, 0.0, 1000.0, 1000.0)


def test_letterbox_clips_a_shape_drawn_past_the_design_edge() raises -> None:
    # 100x50 design in a 100x100 buffer: scale 1, 25-row bars top and bottom.
    # The rect covers every framebuffer pixel, so a bar pixel reading the
    # letterbox colour proves _draw_letterbox clips rather than merely fills
    # an otherwise-empty margin.
    var m = run_headless[OverflowingRect](100, 50, 1, 100, 100)
    assert_equal(m.pixel(50, 5), Color(0x22))
    assert_equal(m.pixel(50, 95), Color(0x22))
    assert_equal(m.pixel(50, 50), Color.GREEN)


struct ScaledSprite(Program):
    var sprite: Sprite

    def __init__(out self, var sprite: Sprite):
        self.sprite = sprite^

    @staticmethod
    def create(mut ctx: Context) raises -> ScaledSprite:
        return ScaledSprite(Sprite.load("tests/fixtures/test_2x2.bmp"))

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.sprite(self.sprite, 0.0, 0.0, 8, 8)


def test_sized_sprite_overload_resamples_nearest_neighbour() raises -> None:
    # test_2x2.bmp: top-left red, top-right white, bottom-left blue, bottom-
    # right white (test_sprite_blits_unflipped's fixture, in test_frame.mojo).
    # Blown up 4x to an 8x8 destination, each source pixel becomes a sharp 4x4
    # block — nearest-neighbour, so the boundary between blocks is exact
    # rather than blended.
    var m = run_headless[ScaledSprite](100, 100)
    assert_equal(m.pixel(46, 46), Color.RED)
    assert_equal(m.pixel(49, 49), Color.RED)
    assert_equal(m.pixel(50, 49), Color.WHITE)
    assert_equal(m.pixel(53, 46), Color.WHITE)
    assert_equal(m.pixel(49, 50), Color.BLUE)
    assert_equal(m.pixel(46, 53), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.WHITE)
    assert_equal(m.pixel(53, 53), Color.WHITE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
