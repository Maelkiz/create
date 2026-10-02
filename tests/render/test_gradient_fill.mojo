# Gradient fills through the real Canvas and the CPU replay: every region
# kind paints its gradient over its own box, the gradient turns with the
# shape, and everything a gradient isn't part of — outline, shadow — keeps
# its colour.

from std.math import pi
from std.os import remove
from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless
from create.math.matrix import rotate


comptime _RED_TO_BLUE = Gradient.linear(Color.RED, Color.BLUE)

comptime RECT_DOWN = 0
comptime RECT_RIGHT = 1
comptime RADIAL_CIRCLE = 2
comptime ROTATED_RECT = 3
comptime ZERO_DIRECTION = 4
comptime OUTLINED = 5
comptime TRANSLUCENT_STOP = 6
comptime TRIANGLE = 7
comptime SECTOR = 8
comptime POLYGON = 9
comptime ADDED = 10
comptime SHADOWED = 11
comptime HALF_OPACITY = 12
comptime ROUNDED_RECT = 13
comptime BACKGROUND = 14
comptime TRANSLUCENT_BACKGROUND = 15
comptime CAMERA_BACKGROUND = 16


@fieldwise_init
struct Scene[n: Int](Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> Self:
        return Self(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(_RED_TO_BLUE)
        comptime if Self.n == RECT_DOWN:
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == RECT_RIGHT:
            canvas.fill(
                Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.RIGHT)
            )
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == RADIAL_CIRCLE:
            canvas.fill(Gradient.radial(Color.WHITE, Color.BLACK))
            canvas.circle((0, 0), 40)
        elif Self.n == ROTATED_RECT:
            # A quarter turn counter-clockwise takes "down" to "right".
            with canvas.transform(rotate(pi / 2.0)):
                canvas.rectangle((0, 0), 80, 80)
        elif Self.n == ZERO_DIRECTION:
            canvas.fill(
                Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.ZERO)
            )
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == OUTLINED:
            canvas.outline(Color.GREEN, thickness=4)
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == TRANSLUCENT_STOP:
            canvas.fill(Gradient.linear(Color.RED.with_alpha(128), Color.RED))
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == TRIANGLE:
            canvas.triangle((-40, 40), (40, 40), (0, -40))
        elif Self.n == SECTOR:
            # A half disc below the centre: its box is the whole circle, so
            # it shows the circle's lower half of the gradient.
            canvas.sector((0, 0), 40.0, pi, pi)
        elif Self.n == POLYGON:
            canvas.polygon((-40, -40), (40, -40), (40, 40), (-40, 40))
        elif Self.n == ADDED:
            canvas.background(Color(0, 0, 100))
            canvas.blend_mode(BlendMode.ADD)
            canvas.fill(Gradient.linear(Color(100, 0, 0), Color(100, 0, 0)))
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == SHADOWED:
            canvas.shadow(Color.GREEN, offset=Vector2D(10, -10), blur=0)
            canvas.rectangle((0, 0), 60, 60)
        elif Self.n == HALF_OPACITY:
            canvas.opacity(0.5)
            canvas.fill(Gradient.linear(Color.RED, Color.RED))
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == ROUNDED_RECT:
            canvas.corner_radius(10)
            canvas.rectangle((0, 0), 80, 80)
        elif Self.n == BACKGROUND:
            canvas.background(_RED_TO_BLUE)
        elif Self.n == TRANSLUCENT_BACKGROUND:
            var half = Color.RED.with_alpha(128)
            canvas.background(Gradient.linear(half, half))
        elif Self.n == CAMERA_BACKGROUND:
            # The camera moves and zooms the world; the background stays put.
            canvas.camera(Camera((50, 20), zoom=3.0))
            canvas.background(_RED_TO_BLUE)


@fieldwise_init
struct LaidOut[extend: Bool](Program):
    """A gradient background on a window twice as wide as the design."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> Self:
        comptime if Self.extend:
            context.autoscale(AutoScale.EXTEND)
        return Self(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(
            Gradient.linear(Color.RED, Color.BLUE, direction=Vector2D.RIGHT)
        )


comptime _IMG_TRANSPARENT = "/tmp/mojo_create_test_gradient_fill_alpha.png"


@fieldwise_init
struct TransparentCapture(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> TransparentCapture:
        return TransparentCapture(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(_RED_TO_BLUE)
        canvas.outline_enabled(False)
        canvas.fill(Color.GREEN)
        canvas.rectangle((0, 0), 20, 20)
        canvas.save_image(_IMG_TRANSPARENT, transparent=True)


def _render[n: Int]() raises -> MemorySurface:
    return run_headless[Scene[n]](100, 100)


def _near(got: Color, want: Color, tolerance: Int = 3) raises:
    var ok = (
        abs(Int(got.r) - Int(want.r)) <= tolerance
        and abs(Int(got.g) - Int(want.g)) <= tolerance
        and abs(Int(got.b) - Int(want.b)) <= tolerance
        and abs(Int(got.a) - Int(want.a)) <= tolerance
    )
    assert_true(ok, String("got ", got, ", want about ", want))


def _assert_runs_down(m: MemorySurface, x: Int, top: Int, bottom: Int) raises:
    """Red at row `top`, blue at row `bottom`, in column `x`."""
    var hi = m.pixel(x, top)
    var lo = m.pixel(x, bottom)
    assert_true(hi.r > 200 and hi.b < 55, String("top is ", hi))
    assert_true(lo.b > 200 and lo.r < 55, String("bottom is ", lo))


def test_a_rect_runs_top_to_bottom_by_default() raises -> None:
    var m = _render[RECT_DOWN]()
    _near(m.pixel(50, 10), Color(254, 0, 1))
    _near(m.pixel(50, 89), Color(1, 0, 254))
    _near(m.pixel(50, 50), Color(127, 0, 128), tolerance=2)
    # Level across: the same colour all along a row.
    _near(m.pixel(12, 30), m.pixel(87, 30), tolerance=1)


def test_a_direction_turns_the_run() raises -> None:
    var m = _render[RECT_RIGHT]()
    _near(m.pixel(10, 50), Color(254, 0, 1))
    _near(m.pixel(89, 50), Color(1, 0, 254))


def test_a_radial_gradient_runs_out_to_the_rim() raises -> None:
    var m = _render[RADIAL_CIRCLE]()
    _near(m.pixel(50, 50), Color.WHITE, tolerance=6)
    var rim = m.pixel(50, 12)
    assert_true(rim.r < 20, String("rim is ", rim))
    # Round: as far out sideways as upwards.
    _near(m.pixel(70, 50), m.pixel(50, 29), tolerance=2)


def test_the_gradient_turns_with_the_shape() raises -> None:
    var m = _render[ROTATED_RECT]()
    _near(m.pixel(10, 50), Color(254, 0, 1))
    _near(m.pixel(89, 50), Color(1, 0, 254))


def test_a_zero_direction_paints_the_first_stop() raises -> None:
    var m = _render[ZERO_DIRECTION]()
    _near(m.pixel(50, 10), Color.RED, tolerance=0)
    _near(m.pixel(50, 89), Color.RED, tolerance=0)


def test_the_outline_keeps_its_colour() raises -> None:
    var m = _render[OUTLINED]()
    _near(m.pixel(11, 50), Color.GREEN, tolerance=0)
    _near(m.pixel(88, 50), Color.GREEN, tolerance=0)
    _assert_runs_down(m, 50, 15, 84)


def test_translucent_stops_composite() raises -> None:
    var m = _render[TRANSLUCENT_STOP]()
    _near(m.pixel(50, 10), Color(128, 0, 0), tolerance=2)
    _near(m.pixel(50, 89), Color.RED, tolerance=2)


def test_a_triangle_spans_its_vertices() raises -> None:
    _assert_runs_down(_render[TRIANGLE](), 50, 12, 88)


def test_a_sector_spans_its_whole_circle() raises -> None:
    var m = _render[SECTOR]()
    # The lower half disc starts mid-way down the circle's gradient.
    _near(m.pixel(50, 52), Color(120, 0, 135), tolerance=2)
    var lo = m.pixel(50, 88)
    assert_true(lo.b > 200 and lo.r < 55, String("bottom is ", lo))


def test_a_polygon_spans_its_vertices() raises -> None:
    _assert_runs_down(_render[POLYGON](), 50, 11, 88)


def test_a_rounded_rect_paints_its_gradient() raises -> None:
    _assert_runs_down(_render[ROUNDED_RECT](), 50, 11, 88)


def test_the_blend_mode_applies() raises -> None:
    var m = _render[ADDED]()
    _near(m.pixel(50, 50), Color(100, 0, 100), tolerance=0)


def test_the_shadow_keeps_its_colour() raises -> None:
    var m = _render[SHADOWED]()
    # Down-right of the rect, inside the offset silhouette only.
    _near(m.pixel(85, 85), Color.GREEN, tolerance=0)
    _assert_runs_down(m, 50, 22, 78)


def test_opacity_scales_the_gradient() raises -> None:
    var m = _render[HALF_OPACITY]()
    _near(m.pixel(50, 50), Color(127, 0, 0), tolerance=1)


def test_a_background_spans_the_screen() raises -> None:
    var m = _render[BACKGROUND]()
    _near(m.pixel(50, 0), Color(254, 0, 1))
    _near(m.pixel(50, 99), Color(1, 0, 254))
    _near(m.pixel(0, 40), m.pixel(99, 40), tolerance=1)


def test_a_translucent_background_blends() raises -> None:
    _near(_render[TRANSLUCENT_BACKGROUND]().pixel(50, 50), Color(128, 0, 0))


def test_the_camera_leaves_the_background_alone() raises -> None:
    var moved = _render[CAMERA_BACKGROUND]()
    var still = _render[BACKGROUND]()
    for y in [0, 37, 99]:
        _near(moved.pixel(50, y), still.pixel(50, y), tolerance=0)


def test_fit_spans_the_design_and_bars_cover_the_rest() raises -> None:
    var m = run_headless[LaidOut[False]](100, 100, 1, 200, 100)
    _near(m.pixel(50, 50), Color(254, 0, 1))
    _near(m.pixel(149, 50), Color(1, 0, 254))
    assert_equal(m.pixel(10, 50), Color.BLACK)
    assert_equal(m.pixel(190, 50), Color.BLACK)


def test_extend_spans_the_whole_window() raises -> None:
    var m = run_headless[LaidOut[True]](100, 100, 1, 200, 100)
    _near(m.pixel(0, 50), Color(254, 0, 1))
    _near(m.pixel(199, 50), Color(1, 0, 254))


def test_a_transparent_capture_drops_the_background() raises -> None:
    _ = run_headless[TransparentCapture](100, 100)
    var img = Sprite.load(_IMG_TRANSPARENT)
    remove(_IMG_TRANSPARENT)

    def px(x: Int, y: Int) {imm img} -> Color:
        var off = (y * img.width + x) * 4
        return Color(
            img.pixels[off],
            img.pixels[off + 1],
            img.pixels[off + 2],
            img.pixels[off + 3],
        )

    assert_equal(px(5, 5).a, 0)
    assert_equal(px(50, 50), Color.GREEN)


def _gpu_matches_cpu[n: Int]() raises -> Bool:
    return _gpu_matches_cpu_for[Scene[n]](String("scene ", n), 100, 100)


def _gpu_matches_cpu_for[
    P: Program
](name: String, pixel_w: Int, pixel_h: Int) raises -> Bool:
    """Whether the GL backend paints `P` as the CPU does, pixel for
    pixel within one level, away from the shapes' edges, where the two
    rasterisers may claim different pixels. False if there is no GL context
    to try it with."""
    var gpu: MemorySurface
    try:
        gpu = run_headless[P](
            100, 100, 1, pixel_w, pixel_h, backend=RenderBackend.GPU
        )
    except:
        return False
    var cpu = run_headless[P](100, 100, 1, pixel_w, pixel_h)
    var compared = 0
    for y in range(2, pixel_h - 2):
        for x in range(2, pixel_w - 2):
            # Only where the CPU's whole 5x5 neighbourhood is one shape's
            # interior or one background: no edge within two pixels.
            var steady = True
            var ink = cpu.pixel(x, y) != Color.BLACK
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if (cpu.pixel(x + dx, y + dy) != Color.BLACK) != ink:
                        steady = False
            if not steady:
                continue
            var a = cpu.pixel(x, y)
            var b = gpu.pixel(x, y)
            var ok = (
                abs(Int(a.r) - Int(b.r)) <= 1
                and abs(Int(a.g) - Int(b.g)) <= 1
                and abs(Int(a.b) - Int(b.b)) <= 1
            )
            assert_true(
                ok,
                String(name, " at (", x, ", ", y, "): CPU ", a, ", GPU ", b),
            )
            compared += 1
    assert_true(compared > 1000, String(name, ": too few pixels"))
    return True


def test_the_gpu_paints_the_same_gradients() raises -> None:
    if not _gpu_matches_cpu[RECT_DOWN]():
        print("SKIP — no GL context")
        return
    _ = _gpu_matches_cpu[RECT_RIGHT]()
    _ = _gpu_matches_cpu[RADIAL_CIRCLE]()
    _ = _gpu_matches_cpu[ROTATED_RECT]()
    _ = _gpu_matches_cpu[ZERO_DIRECTION]()
    _ = _gpu_matches_cpu[OUTLINED]()
    _ = _gpu_matches_cpu[TRANSLUCENT_STOP]()
    _ = _gpu_matches_cpu[TRIANGLE]()
    _ = _gpu_matches_cpu[SECTOR]()
    _ = _gpu_matches_cpu[POLYGON]()
    _ = _gpu_matches_cpu[ADDED]()
    _ = _gpu_matches_cpu[SHADOWED]()
    _ = _gpu_matches_cpu[HALF_OPACITY]()
    _ = _gpu_matches_cpu[ROUNDED_RECT]()
    _ = _gpu_matches_cpu[BACKGROUND]()
    _ = _gpu_matches_cpu[TRANSLUCENT_BACKGROUND]()
    _ = _gpu_matches_cpu[CAMERA_BACKGROUND]()
    _ = _gpu_matches_cpu_for[LaidOut[False]]("fit", 200, 100)
    _ = _gpu_matches_cpu_for[LaidOut[True]]("extend", 200, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
