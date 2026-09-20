# GPU-only coverage the CPU-vs-GPU parity test cannot reach, because it draws
# one shape kind per frame by design: a batch breaks on an opaque clear, on a
# second distinct sprite texture, and at the end of the frame, and none of
# those three are exercised by a single shape. Every case runs through the
# GL backend into an offscreen target and skips with no GL context, same as
# the parity test — and shares its one `GLWindow`, built once per file
# rather than once per case.

from std.collections import Optional

from window import GLWindow

from create import *
from create.core._step import create_program, step
from create.core.input import Input
from create.render._gl import GL
from create.render._gl_target import _GLTarget
from create.render.autoscale import AutoScale
from create.render.frame import PersistentFrameState
from create.render.render_backend import RenderBackend
from create.sprite.sprite import Sprite
from std.testing import TestSuite, assert_equal, assert_true

comptime _GRID = 20
comptime _CELL: Float64 = 10.0


def _has_ink(
    m: MemorySurface, bg: Color, x0: Int, y0: Int, x1: Int, y1: Int
) -> Bool:
    """Whether any pixel in `[x0, x1] x [y0, y1]` differs from `bg`."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if m.pixel(x, y) != bg:
                return True
    return False


@fieldwise_init
struct ClearMidFrame(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> ClearMidFrame:
        return ClearMidFrame(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.outline(enabled=False)
        frame.fill(Color.BLUE)
        frame.rectangle(0.0, 0.0, 40.0, 40.0)
        # An opaque clear must flush the blue rect to the framebuffer before
        # wiping it, not queue it behind the clear where it would survive.
        frame.background(Color.RED)
        frame.fill(Color.GREEN)
        frame.rectangle(10.0, 10.0, 16.0, 16.0)


@fieldwise_init
struct TwoSprites(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> TwoSprites:
        return TwoSprites(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        var a = Sprite.solid(2, 2, 255, 0, 255)
        var b = Sprite.solid(2, 2, 0, 255, 255)
        frame.sprite(a, -20, 0, 16, 16)
        frame.sprite(b, 20, 0, 16, 16)


@fieldwise_init
struct TextAndSprite(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> TextAndSprite:
        return TextAndSprite(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        var img = Sprite.solid(2, 2, 255, 0, 0)
        frame.sprite(img, -30, 0, 16, 16)
        frame.text_color(Color.WHITE)
        frame.font_size(24)
        frame.text_align(Align.TOP_LEFT)
        frame.text("Hi", 0.0, 20.0)


@fieldwise_init
struct ManyShapes(Program):
    var _unused: Int

    @staticmethod
    def create(mut frame: Frame) raises -> ManyShapes:
        return ManyShapes(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.outline(enabled=False)
        for gy in range(_GRID):
            for gx in range(_GRID):
                var idx = gy * _GRID + gx
                frame.fill(Color.RED if idx % 2 == 0 else Color.BLUE)
                var wx = (
                    Float64(gx) - Float64(_GRID) / 2.0
                ) * _CELL + _CELL / 2.0
                var wy = (
                    Float64(gy) - Float64(_GRID) / 2.0
                ) * _CELL + _CELL / 2.0
                frame.rectangle(wx, wy, _CELL - 2.0, _CELL - 2.0)


def _gpu_frame[
    P: Program
](
    mut win: GLWindow, width: Int, height: Int, frames: Int = 1
) raises -> MemorySurface:
    """One program's frames through the GL backend, into an offscreen
    target sized exactly `width` x `height`, read back top-down.

    Shares the caller's `GLWindow` rather than opening its own, so a whole
    file of GPU cases pays for one GL context — otherwise identical to
    `_run_headless_gl`.
    """
    var target = _GLTarget(GL(), width, height)

    var state = PersistentFrameState(RenderBackend.GPU)
    state.view.set_design(width, height)
    state.autoscale = AutoScale.FIT
    state._set_viewport(width, height)
    var created = Optional[P]()
    state = create_program[P](state^, created)
    var program = created.take()
    state._set_viewport(width, height)
    var input = Input()
    var now = 0
    state.time._start(now)
    for _ in range(frames):
        now += 16
        state.time._tick(now)
        state = step(program, input, state^)
        state.backend.present_gpu(width, height, state.view.scale)

    var pixels = state.backend.gl.value().read_frame(width, height)
    var mem = MemorySurface(width, height)
    mem.data = pixels^

    # Rule 3 from `_gl.mojo`: the context owner (`win`, in the caller) must
    # outlive the last GL call, which tearing down `state` and `target` make.
    _ = state^
    _ = target^
    return mem^


def test_gl_batching_behaviours() raises -> None:
    var win: GLWindow
    try:
        # Tiny and never drawn into: every frame lands in an FBO, and this
        # exists only because a GL context needs a window to belong to.
        win = GLWindow("gl_batching", 64, 64)
    except e:
        print("SKIP — no GL context:", e)
        return

    # Case 1: an opaque clear mid-frame must flush the batch queued before
    # it, not let it survive alongside — or behind — what follows the clear.
    var clear_mid_frame = _gpu_frame[ClearMidFrame](win, 64, 64)
    assert_equal(
        clear_mid_frame.pixel(32, 32),
        Color.RED,
        "clear mid-frame: earlier draw leaked through",
    )
    assert_equal(
        clear_mid_frame.pixel(42, 22),
        Color.GREEN,
        "clear mid-frame: later draw missing",
    )

    # Case 2: a second distinct sprite texture in one frame forces a batch
    # break on the bind — both sprites must still blit correctly.
    var two_sprites = _gpu_frame[TwoSprites](win, 64, 64)
    assert_equal(
        two_sprites.pixel(12, 32), Color(255, 0, 255), "two sprites: first"
    )
    assert_equal(
        two_sprites.pixel(52, 32), Color(0, 255, 255), "two sprites: second"
    )

    # Case 3: text (glyph atlas, unit 0) and a sprite (unit 1) in one frame
    # must not displace each other.
    var text_and_sprite = _gpu_frame[TextAndSprite](win, 100, 100)
    assert_equal(
        text_and_sprite.pixel(20, 50),
        Color.RED,
        "text and sprite: sprite missing or wrong colour",
    )
    assert_true(
        _has_ink(text_and_sprite, Color.BLACK, 50, 30, 80, 50),
        "text and sprite: text missing",
    )

    # Case 4: several hundred shapes over two frames — the vertex buffer
    # reaches its capacity in frame 1 and must not corrupt anything when
    # it's reused, not reallocated, in frame 2.
    var many_shapes = _gpu_frame[ManyShapes](win, 200, 200, frames=2)
    assert_equal(many_shapes.pixel(5, 195), Color.RED, "many shapes: (0, 0)")
    assert_equal(many_shapes.pixel(15, 195), Color.BLUE, "many shapes: (1, 0)")
    assert_equal(many_shapes.pixel(195, 5), Color.BLUE, "many shapes: (19, 19)")

    _ = win^


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
