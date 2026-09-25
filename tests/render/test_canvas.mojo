# The rendering tests: render through the real Canvas into an owned buffer and
# assert on the pixels that come out. Everything here runs headless, so the
# geometry conventions the library promises — centred origin, y up, centred
# shapes, source-over alpha — are checked rather than eyeballed.

from std.math import pi
from std.os import remove
from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)

from create import *
from create.core.headless import run_headless
from create.render.surface import MemorySurface
from create.sprite.sprite import Sprite
from std.memory import ArcPointer
from create.math.geometry import Circle, Line, Rectangle, Triangle
from create.math.matrix import rotate, scale, translate
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


@fieldwise_init
struct Background(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> Background:
        return Background(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(10, 20, 30))


def test_background_fills_every_pixel() raises -> None:
    var m = run_headless[Background](16, 16)
    var want = Color(10, 20, 30)
    for y in range(16):
        for x in range(16):
            assert_equal(
                m.pixel(x, y), want, "pixel " + String(x) + "," + String(y)
            )


@fieldwise_init
struct CentredRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> CentredRect:
        return CentredRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.rectangle(0.0, 0.0, 20.0, 20.0)


def test_rect_is_centre_positioned() raises -> None:
    # A 20x20 rect at the origin covers pixels [40, 60) on both axes. If shapes
    # were top-left anchored like Processing's, it would sit in the corner.
    var m = run_headless[CentredRect](100, 100)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(41, 41), Color.RED)
    assert_equal(m.pixel(58, 58), Color.RED)
    assert_equal(m.pixel(38, 38), Color.BLACK)
    assert_equal(m.pixel(61, 61), Color.BLACK)
    # The top-left corner, where a Processing-style rect would have landed.
    assert_equal(m.pixel(5, 5), Color.BLACK)


@fieldwise_init
struct HighRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> HighRect:
        return HighRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.GREEN)
        canvas.rectangle(0.0, 30.0, 10.0, 10.0)


def test_positive_y_renders_above_centre() raises -> None:
    # The load-bearing orientation test: world y grows upward, so +30 must land
    # in *lower*-numbered rows. Row 20 is 30 pixels above centre, row 80 is 30
    # below it — a y-down mapping would swap the two assertions.
    var m = run_headless[HighRect](100, 100)
    assert_equal(m.pixel(50, 20), Color.GREEN)
    assert_equal(m.pixel(50, 80), Color.BLACK)


@fieldwise_init
struct CentredCircle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> CentredCircle:
        return CentredCircle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.CYAN)
        canvas.circle(0.0, 0.0, 20.0)


def test_circle_is_centred_and_radial() raises -> None:
    var m = run_headless[CentredCircle](100, 100)
    assert_equal(m.pixel(50, 50), Color.CYAN)
    # Well inside the radius on each axis — y up means both rows are in.
    assert_equal(m.pixel(68, 50), Color.CYAN)
    assert_equal(m.pixel(50, 32), Color.CYAN)
    # Outside the radius, but inside the square that bounds it: the corner
    # catches a circle rasterised as a box.
    assert_equal(m.pixel(66, 66), Color.BLACK)
    assert_equal(m.pixel(75, 50), Color.BLACK)
    # And not anchored top-left.
    assert_equal(m.pixel(5, 5), Color.BLACK)


@fieldwise_init
struct UprightTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> UprightTriangle:
        return UprightTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.MAGENTA)
        # Apex up, base below — in world terms, since y grows upward.
        canvas.triangle(0.0, 30.0, -30.0, -30.0, 30.0, -30.0)


def test_triangle_fills_its_interior_only() raises -> None:
    var m = run_headless[UprightTriangle](100, 100)
    # Centroid, and a point low in the wide part of the triangle.
    assert_equal(m.pixel(50, 50), Color.MAGENTA)
    assert_equal(m.pixel(35, 70), Color.MAGENTA)
    # The apex is at the top of the buffer, so the upper corners are outside.
    assert_equal(m.pixel(25, 25), Color.BLACK)
    assert_equal(m.pixel(75, 25), Color.BLACK)
    # Below the base.
    assert_equal(m.pixel(50, 85), Color.BLACK)


@fieldwise_init
struct AlphaOverRed(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> AlphaOverRed:
        return AlphaOverRed(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.RED)
        canvas.outline_enabled(False)
        canvas.fill(Color(0, 0, 255, 128))
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_alpha_composites_source_over() raises -> None:
    var m = run_headless[AlphaOverRed](64, 64)
    assert_equal(m.pixel(32, 32), Color(0, 0, 255, 128).over(Color.RED))
    assert_equal(m.pixel(2, 2), Color.RED)


@fieldwise_init
struct ThickLine(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ThickLine:
        return ThickLine(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.WHITE, thickness=3)
        canvas.line(-10.0, 0.0, 10.0, 0.0)


def test_outline_thickness_scales_to_pixels() raises -> None:
    # 50x50 design in a 100x100 buffer is a 2x scale, so a 3-unit outline is 6
    # pixels thick: rows 47..52 around the centre row.
    var m = run_headless[ThickLine](50, 50, 1, 100, 100)
    for row in range(47, 53):
        assert_equal(m.pixel(50, row), Color.WHITE, "pixel 50," + String(row))
    assert_equal(m.pixel(50, 46), Color.BLACK)
    assert_equal(m.pixel(50, 53), Color.BLACK)


@fieldwise_init
struct FitBars(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> FitBars:
        return FitBars(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)


@fieldwise_init
struct ExtendNoBars(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ExtendNoBars:
        context.autoscale = AutoScale.EXTEND
        return ExtendNoBars(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLUE)


def test_fit_paints_letterbox_bars() raises -> None:
    # A 100x50 design in a 100x100 buffer scales by 1 and leaves 25 rows of bar
    # top and bottom, painted after render so they also clip the design area.
    var m = run_headless[FitBars](100, 50, 1, 100, 100)
    assert_equal(m.pixel(50, 5), Color(0x22))
    assert_equal(m.pixel(50, 95), Color(0x22))
    assert_equal(m.pixel(50, 50), Color.BLUE)


def test_extend_has_no_letterbox_bars() raises -> None:
    # Same shape under EXTEND: the world grows into the leftover instead.
    var m = run_headless[ExtendNoBars](100, 50, 1, 100, 100)
    assert_equal(m.pixel(50, 5), Color.BLUE)
    assert_equal(m.pixel(50, 95), Color.BLUE)


@fieldwise_init
struct RotatedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RotatedRect:
        return RotatedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.YELLOW)
        with canvas.transform(rotate(pi / 4.0)):
            canvas.rectangle(0.0, 0.0, 20.0, 20.0)


def test_rotation_takes_the_inverse_mapped_path() raises -> None:
    # Rotating a square 45 degrees swaps which points are inside: the corners of
    # the axis-aligned box fall out, and the diagonal tips fall in.
    var m = run_headless[RotatedRect](100, 100)
    assert_equal(m.pixel(50, 50), Color.YELLOW)
    # World (0, 13) — outside the unrotated square, inside the rotated one.
    assert_equal(m.pixel(50, 37), Color.YELLOW)
    # World (-9, 9) — inside the unrotated square, outside the rotated one.
    assert_equal(m.pixel(41, 41), Color.BLACK)


@fieldwise_init
struct SharpRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SharpRect:
        return SharpRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(0)
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_corner_radius_zero_matches_sharp_rect() raises -> None:
    # A 40x40 rect at the origin covers device pixels [30, 70) on both axes.
    # corner_radius(0) must leave every corner square, not just mostly so.
    var m = run_headless[SharpRect](100, 100)
    assert_equal(m.pixel(31, 31), Color.RED)
    assert_equal(m.pixel(68, 68), Color.RED)


@fieldwise_init
struct RoundedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RoundedRect:
        return RoundedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(10)
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_rect_corner_radius_rounds_the_corner() raises -> None:
    # Same 40x40 rect, corner_radius 10: the top-left fillet is a disc of
    # radius 10 centred on device pixel (40, 40).
    var m = run_headless[RoundedRect](100, 100)
    # Right at the sharp rect's own corner — well outside the fillet disc.
    assert_equal(m.pixel(31, 31), Color.BLACK)
    # Close to the fillet's own centre — inside the disc, so still filled.
    assert_equal(m.pixel(39, 39), Color.RED)


@fieldwise_init
struct RoundedRectOutlined(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RoundedRectOutlined:
        return RoundedRectOutlined(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.BLUE, thickness=2)
        canvas.fill(Color.RED)
        canvas.corner_radius(10)
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_rect_corner_radius_outline_follows_the_arc() raises -> None:
    # Same fillet, centred on device pixel (40, 40), radius 10, with a 2-unit
    # outline: outer ring at distance 10, inner edge at distance 8. Probing
    # along the diagonal (not an axis) is what actually exercises the arc
    # rather than a square corner's straight edges.
    var m = run_headless[RoundedRectOutlined](100, 100)
    # Distance from (40, 40) is about 9.9 — inside the outer radius, outside
    # the inner one: on the ring.
    assert_equal(m.pixel(33, 33), Color.BLUE)
    # Distance about 11.3 — outside the fillet disc entirely.
    assert_equal(m.pixel(32, 32), Color.BLACK)
    # Distance about 7.1 — inside the inner radius: fill, not outline.
    assert_equal(m.pixel(35, 35), Color.RED)


def test_rect_corner_radius_keeps_the_flat_edge() raises -> None:
    # Away from either corner, the top edge of the same rect is untouched by
    # rounding — still the sharp rect's own straight boundary at row 30/31.
    var m = run_headless[RoundedRect](100, 100)
    assert_equal(m.pixel(50, 31), Color.RED)
    assert_equal(m.pixel(50, 29), Color.BLACK)


@fieldwise_init
struct ScaledRoundedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ScaledRoundedRect:
        return ScaledRoundedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(5)
        canvas.rectangle(0.0, 0.0, 20.0, 20.0)


def test_corner_radius_scales_to_pixels() raises -> None:
    # 50x50 design in a 100x100 buffer is a 2x scale: a 20x20 world rect with
    # a 5-unit corner_radius covers the same device pixels — [30, 70) with a
    # 10-pixel fillet — as RoundedRect's own 40x40-at-1x case above.
    var m = run_headless[ScaledRoundedRect](50, 50, 1, 100, 100)
    assert_equal(m.pixel(31, 31), Color.BLACK)
    assert_equal(m.pixel(39, 39), Color.RED)


@fieldwise_init
struct RotatedRoundedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RotatedRoundedRect:
        return RotatedRoundedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.YELLOW)
        canvas.corner_radius(6)
        with canvas.transform(rotate(pi / 4.0)):
            canvas.rectangle(0.0, 0.0, 20.0, 20.0)


def test_rect_corner_radius_under_rotation() raises -> None:
    # Same rotated square as test_rotation_takes_the_inverse_mapped_path, but
    # with corner_radius 6. World (0, 13) maps to local (9.19, 9.19) — right
    # next to the local corner vertex (10, 10) — so a fillet that size must
    # now exclude it, where the sharp rotated square included it.
    var m = run_headless[RotatedRoundedRect](100, 100)
    assert_equal(m.pixel(50, 50), Color.YELLOW)
    assert_equal(m.pixel(50, 37), Color.BLACK)
    # Deep interior, far from any corner: unaffected by rounding.
    assert_equal(m.pixel(46, 46), Color.YELLOW)


@fieldwise_init
struct SharpTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SharpTriangle:
        return SharpTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(0)
        # Right angle at world (-20, -20), legs of length 20 along +x and +y.
        canvas.triangle(-20.0, -20.0, 0.0, -20.0, -20.0, 0.0)


def test_corner_radius_zero_matches_sharp_triangle() raises -> None:
    # The right-angle vertex maps to device pixel (30, 70). corner_radius(0)
    # must leave it square, same as the untouched sharp path.
    var m = run_headless[SharpTriangle](100, 100)
    assert_equal(m.pixel(30, 70), Color.RED)
    assert_equal(m.pixel(37, 63), Color.RED)


@fieldwise_init
struct RoundedTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RoundedTriangle:
        return RoundedTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(5)
        # Right angle at world (-20, -20), legs of length 20 along +x and +y —
        # same corner shape as corner_fillet's own known right-angle test.
        # The other two vertices are 45 degrees, which clamp the requested
        # radius 5 down to `10 * tan(pi / 8)` (about 4.14, via
        # triangle_corner_radius), so the right angle's own fillet centre
        # ends up at world (-15.86, -15.86), device pixel (34, 66) — offset
        # from the vertex by the clamped radius, not the requested one.
        canvas.triangle(-20.0, -20.0, 0.0, -20.0, -20.0, 0.0)


def test_triangle_corner_radius_rounds_the_corner() raises -> None:
    var m = run_headless[RoundedTriangle](100, 100)
    # Right at the sharp triangle's own vertex — distance from the fillet
    # centre is the clamped radius times sqrt(2), about 5.86, well outside
    # the disc.
    assert_equal(m.pixel(30, 70), Color.BLACK)
    # Close to the fillet's own centre — inside the disc, so still filled.
    assert_equal(m.pixel(35, 65), Color.RED)
    # Deep interior, far from the rounded corner: unaffected by rounding.
    assert_equal(m.pixel(35, 62), Color.RED)


@fieldwise_init
struct RoundedTriangleOutlined(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RoundedTriangleOutlined:
        return RoundedTriangleOutlined(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.BLUE, thickness=4)
        canvas.fill(Color.RED)
        canvas.corner_radius(5)
        canvas.triangle(-20.0, -20.0, 0.0, -20.0, -20.0, 0.0)


def test_triangle_corner_radius_outline_is_centred() raises -> None:
    # Same fillet as RoundedTriangle (radius clamped to about 4.14), with a
    # 4-unit outline. The outline band is centred on the arc (unlike a
    # rect's inset ring), so it straddles both sides of the fillet boundary
    # — bleeding outward, past the arc, into the wedge that was cut away
    # from the original sharp corner. A rect-style inset outline would
    # leave that whole wedge as bare background instead.
    var m = run_headless[RoundedTriangleOutlined](100, 100)
    # On the arc itself, toward the old sharp vertex.
    assert_equal(m.pixel(31, 69), Color.BLUE)
    # Further out along the same direction, past the arc — in the cut-away
    # wedge — but still within the centred band's outward half.
    assert_equal(m.pixel(30, 68), Color.BLUE)
    # Past the old sharp vertex and past the outline band entirely: plain
    # background.
    assert_equal(m.pixel(25, 71), Color.BLACK)
    # Well inside the fillet disc: fill, not outline.
    assert_equal(m.pixel(35, 65), Color.RED)


@fieldwise_init
struct ThinRoundedTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ThinRoundedTriangle:
        return ThinRoundedTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        # A requested radius far larger than this sliver triangle could ever
        # support — triangle_corner_radius must clamp it, not let the
        # fillets balloon past the triangle's own edges.
        canvas.corner_radius(1000)
        canvas.triangle(0.0, 20.0, -30.0, -20.0, 30.0, -21.0)


def test_triangle_corner_radius_clamps_to_incircle() raises -> None:
    var m = run_headless[ThinRoundedTriangle](100, 100)
    # Centroid: still filled, so the clamp didn't collapse the shape.
    assert_equal(m.pixel(50, 57), Color.RED)
    # Just outside the sliver's own sharp hull, near an end tip — an
    # unclamped radius would have ballooned a fillet disc out past the
    # triangle's own edges and painted here; the clamp must keep it BLACK.
    assert_equal(m.pixel(20, 60), Color.BLACK)
    assert_equal(m.pixel(80, 60), Color.BLACK)


@fieldwise_init
struct RotatedRoundedTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RotatedRoundedTriangle:
        return RotatedRoundedTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.YELLOW)
        canvas.corner_radius(6)
        with canvas.transform(rotate(pi / 4.0)):
            canvas.triangle(-20.0, -20.0, 0.0, -20.0, -20.0, 0.0)


def test_triangle_corner_radius_under_rotation() raises -> None:
    # Same right triangle as RoundedTriangle, rotated 45 degrees — this
    # takes the non-uniform (local-space) branch of the rounded-triangle
    # fill, since a pure rotation still has off-diagonal matrix terms.
    var m = run_headless[RotatedRoundedTriangle](100, 100)
    # Deep interior: unaffected by rounding or rotation.
    assert_equal(m.pixel(50, 68), Color.YELLOW)
    # Local (-20, -20) is the right-angle vertex being rounded away. Rotated
    # 45 degrees it lands at world (0, -28.28) — device pixel (50, 78),
    # which the sharp (unrounded) version of this same triangle does fill,
    # but the rounded corner cuts away.
    assert_equal(m.pixel(50, 78), Color.BLACK)


struct SpriteBlit(Program):
    var sprite: Sprite

    def __init__(out self, var sprite: Sprite):
        self.sprite = sprite^

    @staticmethod
    def create(mut context: Context) raises -> SpriteBlit:
        return SpriteBlit(Sprite.load("tests/fixtures/test_2x2.bmp"))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.sprite(self.sprite, 0.0, 0.0)


def test_sprite_blits_unflipped() raises -> None:
    # test_2x2.bmp: top-left red, top-right white, bottom-left blue, bottom-
    # right white. Sprites are not y-flipped — only their anchor is mapped — so
    # the image's top row stays on top.
    var m = run_headless[SpriteBlit](100, 100)
    assert_equal(m.pixel(49, 49), Color.RED)
    assert_equal(m.pixel(50, 49), Color.WHITE)
    assert_equal(m.pixel(49, 50), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.WHITE)


struct PngSpriteBlit(Program):
    var sprite: Sprite

    def __init__(out self, var sprite: Sprite):
        self.sprite = sprite^

    @staticmethod
    def create(mut context: Context) raises -> PngSpriteBlit:
        return PngSpriteBlit(Sprite.load("tests/fixtures/test_2x2.png"))

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.sprite(self.sprite, 0.0, 0.0)


def test_png_sprite_blits_unflipped() raises -> None:
    # test_2x2.png: top-left=red, top-right=green, bottom-left=blue,
    # bottom-right=white -- proves the decode-to-screen path for a format
    # other than BMP, sharing the already-covered raster blit.
    var m = run_headless[PngSpriteBlit](100, 100)
    assert_equal(m.pixel(49, 49), Color.RED)
    assert_equal(m.pixel(50, 49), Color(0, 255, 0))
    assert_equal(m.pixel(49, 50), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.WHITE)


@fieldwise_init
struct StyleAcrossFrames(Program):
    # Frame 1 sets a style and renders nothing; frame 2 renders without setting
    # one. Style is per-frame, so frame 2 must get the defaults back.
    var frame: Int

    @staticmethod
    def create(mut context: Context) raises -> StyleAcrossFrames:
        return StyleAcrossFrames(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.frame = context.time.frame_count

        canvas.background(Color.BLACK)
        if self.frame == 1:
            canvas.fill(Color.RED)
            canvas.outline_enabled(False)
        else:
            canvas.rectangle((0, 0), 20, 20)


def test_style_does_not_survive_the_frame_boundary() raises -> None:
    # Only the last frame's buffer comes back, so red here would mean frame
    # 1's fill leaked forward. Default fill is transparent, so frame 2's
    # rectangle lets the black background show through.
    var m = run_headless[StyleAcrossFrames](100, 100, 2)
    assert_equal(m.pixel(50, 50), Color.BLACK)


@fieldwise_init
struct GuardedStyle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> GuardedStyle:
        return GuardedStyle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        with canvas.style():
            canvas.fill(Color.BLUE)
            canvas.rectangle((-25, 0), 20, 20)
        canvas.rectangle((25, 0), 20, 20)


def test_style_guard_restores_on_scope_exit() raises -> None:
    var m = run_headless[GuardedStyle](100, 100)
    assert_equal(m.pixel(25, 50), Color.BLUE)
    assert_equal(m.pixel(75, 50), Color.RED)


@fieldwise_init
struct AppliedStyle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> AppliedStyle:
        return AppliedStyle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.GREEN, thickness=4)
        canvas.fill(Color.RED)
        # Sets no outline, so the block renders with the default 1-unit
        # black one rather than the green set above.
        with canvas.style(Style(fill=Color.BLUE)):
            canvas.rectangle((-25, 0), 20, 20)
        canvas.rectangle((25, 0), 20, 20)


def test_style_object_replaces_the_whole_style_in_scope() raises -> None:
    var m = run_headless[AppliedStyle](100, 100)
    assert_equal(m.pixel(25, 50), Color.BLUE)
    assert_equal(m.pixel(15, 50), Color.BLACK)  # default outline, not green
    assert_equal(m.pixel(75, 50), Color.RED)  # restored on exit
    assert_equal(m.pixel(66, 50), Color.GREEN)


@fieldwise_init
struct NestedStyles(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> NestedStyles:
        return NestedStyles(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        var outer = Style(fill=Color.RED, outline_enabled=False)
        var inner = Style(fill=Color.BLUE, outline_enabled=False)
        with canvas.style(outer):
            with canvas.style(inner):
                canvas.rectangle((-30, 0), 16, 16)
            canvas.rectangle((0, 0), 16, 16)
        canvas.rectangle((30, 0), 16, 16)


def test_style_objects_nest() raises -> None:
    var m = run_headless[NestedStyles](100, 100)
    assert_equal(m.pixel(20, 50), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.RED)
    # Back to the frame's own style: transparent fill, black outline.
    assert_equal(m.pixel(80, 50), Color.BLACK)


@fieldwise_init
struct BareStyleCall(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> BareStyleCall:
        return BareStyleCall(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        _ = canvas.style(Style(fill=Color.BLUE, outline_enabled=False))
        canvas.rectangle((0, 0), 20, 20)


def test_style_object_outside_a_with_block_holds() raises -> None:
    var m = run_headless[BareStyleCall](100, 100)
    assert_equal(m.pixel(50, 50), Color.BLUE)


@fieldwise_init
struct StrokedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> StrokedRect:
        return StrokedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.RED)
        canvas.outline(Color.BLUE, thickness=4)
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_rect_outline_renders_all_four_bands() raises -> None:
    # The border is four separate fill_pixels calls, so a single-corner
    # assertion would miss three of them.
    var m = run_headless[StrokedRect](100, 100)
    assert_equal(m.pixel(50, 31), Color.BLUE)  # top band
    assert_equal(m.pixel(50, 68), Color.BLUE)  # bottom band
    assert_equal(m.pixel(31, 50), Color.BLUE)  # left band
    assert_equal(m.pixel(68, 50), Color.BLUE)  # right band
    assert_equal(m.pixel(50, 50), Color.RED)  # well inside the border


@fieldwise_init
struct StrokedCircle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> StrokedCircle:
        return StrokedCircle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.GREEN)
        canvas.outline(Color.WHITE, thickness=4)
        canvas.circle(0.0, 0.0, 20.0)


def test_circle_outline_renders_the_ring() raises -> None:
    var m = run_headless[StrokedCircle](100, 100)
    # Radius 20, outline thickness 4: the ring is d in (16, 20].
    assert_equal(m.pixel(69, 50), Color.WHITE)  # just inside the outer radius
    assert_equal(m.pixel(65, 50), Color.GREEN)  # just inside the inner radius
    assert_equal(m.pixel(75, 50), Color.BLACK)  # outside the outer radius


@fieldwise_init
struct StrokedTriangle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> StrokedTriangle:
        return StrokedTriangle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.ORANGE)
        canvas.outline(Color.WHITE, thickness=4)
        canvas.triangle(0.0, 30.0, -30.0, -30.0, 30.0, -30.0)


def test_triangle_outline_renders_the_edges() raises -> None:
    var m = run_headless[StrokedTriangle](100, 100)
    # (-15, 0) sits exactly on the apex-to-base-left edge.
    assert_equal(m.pixel(35, 50), Color.WHITE)
    assert_equal(m.pixel(50, 50), Color.ORANGE)  # well inside the fill


@fieldwise_init
struct NoFillRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> NoFillRect:
        return NoFillRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill_enabled(False)
        canvas.outline(Color.WHITE, thickness=4)
        canvas.rectangle(0.0, 0.0, 40.0, 40.0)


def test_no_fill_leaves_the_rect_interior_untouched() raises -> None:
    var m = run_headless[NoFillRect](100, 100)
    assert_equal(m.pixel(50, 50), Color.BLACK)  # interior stayed background
    assert_equal(m.pixel(50, 31), Color.WHITE)  # border still outlines


@fieldwise_init
struct NoFillCircle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> NoFillCircle:
        return NoFillCircle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill_enabled(False)
        canvas.outline(Color.WHITE, thickness=4)
        canvas.circle(0.0, 0.0, 20.0)


def test_no_fill_leaves_the_circle_interior_untouched() raises -> None:
    var m = run_headless[NoFillCircle](100, 100)
    assert_equal(m.pixel(60, 50), Color.BLACK)  # interior stayed background
    assert_equal(m.pixel(69, 50), Color.WHITE)  # ring still outlines


@fieldwise_init
struct FillSwitching(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> FillSwitching:
        return FillSwitching(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.fill_enabled(False)
        canvas.rectangle((-30, 0), 16, 16)  # off
        canvas.fill_enabled(True)
        canvas.rectangle((0, 0), 16, 16)  # back on, color remembered
        canvas.fill_enabled(False)
        canvas.fill(Color.BLUE)
        canvas.rectangle((30, 0), 16, 16)  # a new color switches it on


def test_fill_enabled_switches_fill_and_keeps_its_color() raises -> None:
    var m = run_headless[FillSwitching](100, 100)
    assert_equal(m.pixel(20, 50), Color.BLACK)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(80, 50), Color.BLUE)


@fieldwise_init
struct OutlineSwitching(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> OutlineSwitching:
        return OutlineSwitching(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.RED, thickness=4)
        canvas.outline_enabled(False)
        canvas.rectangle((-30, 0), 16, 16)  # off
        canvas.outline_enabled(True)
        canvas.rectangle((0, 0), 16, 16)  # back on, color remembered
        canvas.outline_enabled(False)
        canvas.outline(Color.BLUE)
        canvas.rectangle((30, 0), 16, 16)  # a new color switches it on


def test_outline_enabled_switches_outline_and_keeps_its_color() raises -> None:
    # Sampled one pixel inside each rectangle's left edge, on the inset ring.
    var m = run_headless[OutlineSwitching](100, 100)
    assert_equal(m.pixel(13, 50), Color.BLACK)
    assert_equal(m.pixel(43, 50), Color.RED)
    assert_equal(m.pixel(73, 50), Color.BLUE)


@fieldwise_init
struct RotatedCircle(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RotatedCircle:
        return RotatedCircle(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.CYAN)
        with canvas.transform(rotate(pi / 4.0)):
            canvas.circle(0.0, 0.0, 20.0)


def test_circle_under_rotation_matches_the_axis_aligned_result() raises -> None:
    # A circle centred on the origin is rotation-invariant, so a 45-degree
    # turn — which forces the non-uniform, per-pixel path — must produce the
    # exact same pixels as test_circle_is_centred_and_radial's axis-aligned
    # fast path. This is what makes the check a cross-path equivalence test
    # rather than a restatement of either implementation.
    var m = run_headless[RotatedCircle](100, 100)
    assert_equal(m.pixel(50, 50), Color.CYAN)
    assert_equal(m.pixel(68, 50), Color.CYAN)
    assert_equal(m.pixel(50, 32), Color.CYAN)
    assert_equal(m.pixel(66, 66), Color.BLACK)
    assert_equal(m.pixel(75, 50), Color.BLACK)
    assert_equal(m.pixel(5, 5), Color.BLACK)


@fieldwise_init
struct QuarterTurnRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> QuarterTurnRect:
        return QuarterTurnRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.YELLOW)
        with canvas.transform(rotate(pi / 2.0)):
            canvas.rectangle(0.0, 0.0, 20.0, 40.0)


@fieldwise_init
struct SwappedRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SwappedRect:
        return SwappedRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.YELLOW)
        canvas.rectangle(0.0, 0.0, 40.0, 20.0)


def _assert_quarter_turn_pixels(m: MemorySurface) raises:
    assert_equal(m.pixel(50, 50), Color.YELLOW)  # centre
    assert_equal(m.pixel(68, 50), Color.YELLOW)  # inside the wide axis
    assert_equal(m.pixel(50, 32), Color.BLACK)  # outside the narrow axis
    assert_equal(m.pixel(5, 5), Color.BLACK)


def test_quarter_turn_matches_dimension_swapped_rect() raises -> None:
    # A quarter turn fails _uniform() (m[0, 1] and m[1, 0] are non-zero) yet
    # is an exact axis-aligned result: a 20x40 rect rotated 90 degrees must
    # cover the same pixels as an unrotated 40x20 rect.
    _assert_quarter_turn_pixels(run_headless[QuarterTurnRect](100, 100))
    _assert_quarter_turn_pixels(run_headless[SwappedRect](100, 100))


@fieldwise_init
struct GeometryOverloads(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> GeometryOverloads:
        return GeometryOverloads(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)

        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.rectangle(Rectangle(-90.0, 40.0, 20.0, 20.0))

        canvas.fill(Color.GREEN)
        canvas.circle(Circle(-30.0, 40.0, 10.0))

        canvas.outline(Color.BLUE, thickness=3)
        canvas.line(Line(20.0, 40.0, 40.0, 40.0))

        canvas.outline_enabled(False)
        canvas.fill(Color.CYAN)
        canvas.triangle(Triangle(90.0, 50.0, 80.0, 30.0, 100.0, 30.0))

        canvas.fill(Color.MAGENTA)
        canvas.rectangle(Point2D(-90.0, -40.0), 20.0, 20.0)

        canvas.fill(Color.YELLOW)
        canvas.circle(Point2D(-30.0, -40.0), 10.0)

        canvas.outline(Color.ORANGE, thickness=3)
        canvas.line(Point2D(20.0, -40.0), Point2D(40.0, -40.0))

        canvas.outline_enabled(False)
        canvas.fill(Color.LIGHT_GRAY)
        canvas.triangle(
            Point2D(90.0, -30.0), Point2D(80.0, -50.0), Point2D(100.0, -50.0)
        )

        # The one overload naming both types: a position and an extent.
        canvas.fill(Color.WHITE)
        canvas.rectangle(Point2D(-90.0, 0.0), Vector2D(20.0, 20.0))


def test_geometry_overloads_dispatch_correctly() raises -> None:
    # These are one-line forwards, so the value is dispatch and argument
    # order — that rect(Rectangle(x, y, w, h)) centres on (x, y) like the
    # float form, not a corner — not the raster.
    var m = run_headless[GeometryOverloads](240, 240)
    assert_equal(m.pixel(30, 80), Color.RED)  # rect(Rectangle)
    assert_equal(m.pixel(90, 80), Color.GREEN)  # circle(Circle)
    assert_equal(m.pixel(150, 80), Color.BLUE)  # line(Line)
    assert_equal(m.pixel(210, 85), Color.CYAN)  # triangle(Triangle)
    assert_equal(m.pixel(30, 160), Color.MAGENTA)  # rect(Point2D, w, h)
    assert_equal(m.pixel(90, 160), Color.YELLOW)  # circle(Point2D, r)
    assert_equal(m.pixel(150, 160), Color.ORANGE)  # line(Point2D, Point2D)
    assert_equal(m.pixel(210, 165), Color.LIGHT_GRAY)  # triangle(Point2D x3)
    assert_equal(m.pixel(30, 120), Color.WHITE)  # rect(Point2D, Vector2D)
    assert_equal(m.pixel(5, 5), Color.BLACK)


@fieldwise_init
struct ToWorldRoundTrip(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ToWorldRoundTrip:
        return ToWorldRoundTrip(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        with canvas.transform(translate(10.0, 20.0)):
            var origin = canvas.to_local(10.0, 20.0)
            assert_almost_equal(origin[0], 0.0)
            assert_almost_equal(origin[1], 0.0)
            var back = canvas.to_world(0.0, 0.0)
            assert_almost_equal(back[0], 10.0)
            assert_almost_equal(back[1], 20.0)

        with canvas.transform(translate(5.0, -8.0) @ rotate(pi / 3.0)):
            var world = canvas.to_world(7.0, -2.0)
            var local = canvas.to_local(world[0], world[1])
            assert_almost_equal(local[0], 7.0)
            assert_almost_equal(local[1], -2.0)


def test_to_world_and_to_local_round_trip_through_a_transform() raises -> None:
    # Asserted inline in `update` — `run_headless` hands the buffer back, not
    # the program, so there is no field the test function could read after.
    _ = run_headless[ToWorldRoundTrip](100, 100)


@fieldwise_init
struct ThickLineUnderNonUniformScale(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> ThickLineUnderNonUniformScale:
        return ThickLineUnderNonUniformScale(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline(Color.WHITE, thickness=3)
        with canvas.transform(scale(3.0, 1.0)):
            canvas.line(-10.0 / 3.0, 0.0, 10.0 / 3.0, 0.0)


def test_outline_thickness_under_non_uniform_transform_follows_autoscale() raises -> (
    None
):
    # scale(3.0, 1.0) makes the transform non-uniform, so _pixel_scale must
    # fall back to canvas.scale (the autoscale factor, 2x here) rather than
    # the local transform's own 3x — a 3-unit outline comes out 6 pixels
    # thick, not 18.
    var m = run_headless[ThickLineUnderNonUniformScale](50, 50, 1, 100, 100)
    for row in range(47, 53):
        assert_equal(m.pixel(50, row), Color.WHITE, "pixel 50," + String(row))
    assert_equal(m.pixel(50, 46), Color.BLACK)
    assert_equal(m.pixel(50, 53), Color.BLACK)


def _non_background_box(
    m: MemorySurface, bg: Color
) -> Tuple[Int, Int, Int, Int]:
    """Bounding box of every pixel that differs from `bg` — `(x0, y0, x1, y1)`,
    inclusive. Returns `(-1, -1, -1, -1)` when nothing was rendered.

    Unlike test_text.mojo's transparent buffers, everything rendered here goes
    onto an opaque background, so ink is found by difference from the known
    background colour rather than by alpha.
    """
    var x0 = m.width
    var y0 = m.height
    var x1 = -1
    var y1 = -1
    for y in range(m.height):
        for x in range(m.width):
            if m.pixel(x, y) != bg:
                x0 = min(x0, x)
                y0 = min(y0, y)
                x1 = max(x1, x)
                y1 = max(y1, y)
    if x1 < 0:
        return (-1, -1, -1, -1)
    return (x0, y0, x1, y1)


@fieldwise_init
struct TextThroughCanvas(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> TextThroughCanvas:
        return TextThroughCanvas(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.text_color(Color.WHITE)
        canvas.font_size(24)
        canvas.text_align(Align.TOP_LEFT)
        canvas.text("Hi", 0.0, 0.0)


def test_text_renders_below_and_right_of_a_top_left_anchor() raises -> None:
    # The anchor is the buffer centre (100, 100); LEFT/TOP must put the ink
    # at or past it on both axes, the same shape test_text.mojo checks
    # against TextRenderer directly, but now through Canvas's own style and
    # transform plumbing.
    var m = run_headless[TextThroughCanvas](200, 200)
    var box = _non_background_box(m, Color.BLACK)
    assert_true(box[2] >= 0, "nothing was rendered")
    assert_true(box[0] >= 100, "ink started left of the anchor")
    assert_true(box[1] >= 100, "ink started above the anchor")


@fieldwise_init
struct TransparentText(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> TransparentText:
        return TransparentText(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.text_color(Color(255, 255, 255, 0))
        canvas.text("Hi", 0.0, 0.0)


def test_a_transparent_text_color_suppresses_text() raises -> None:
    var m = run_headless[TransparentText](200, 200)
    assert_equal(_non_background_box(m, Color.BLACK)[2], -1)


@fieldwise_init
struct TextBesideShape(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> TextBesideShape:
        return TextBesideShape(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.rectangle((-60.0, 0.0), 40.0, 40.0)
        canvas.text_color(Color.GREEN)
        canvas.font_size(48)
        canvas.text_align(Align.CENTER)
        canvas.text("Hi", 40.0, 0.0)


def test_text_color_is_independent_of_fill() raises -> None:
    # Both in one frame: the shape keeps the fill, the glyphs take the text
    # colour, so neither setting reaches the other.
    var m = run_headless[TextBesideShape](200, 200)
    assert_equal(m.pixel(40, 100), Color.RED)  # inside the rectangle
    var ink_is_green = False
    for x in range(120, 190):
        for y in range(70, 130):
            var c = m.pixel(x, y)
            if c != Color.BLACK:
                assert_equal(c.r, 0)
                assert_equal(c.b, 0)
                ink_is_green = True
    assert_true(ink_is_green, "no glyph ink was rendered")


@fieldwise_init
struct SmallText(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SmallText:
        return SmallText(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.text_color(Color.WHITE)
        canvas.font_size(12)
        canvas.text_align(Align.TOP_LEFT)
        canvas.text("Hi", 0.0, 0.0)


@fieldwise_init
struct BigText(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> BigText:
        return BigText(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.text_color(Color.WHITE)
        canvas.font_size(48)
        canvas.text_align(Align.TOP_LEFT)
        canvas.text("Hi", 0.0, 0.0)


def test_font_size_grows_the_text_extent() raises -> None:
    var small = _non_background_box(
        run_headless[SmallText](200, 200), Color.BLACK
    )
    var big = _non_background_box(run_headless[BigText](200, 200), Color.BLACK)
    assert_true(
        (big[2] - big[0]) > (small[2] - small[0]),
        "larger font_size was not wider",
    )


struct QuitOnFrameTwo(Program):
    var frame: Int

    def __init__(out self):
        self.frame = 0

    @staticmethod
    def create(mut context: Context) raises -> QuitOnFrameTwo:
        return QuitOnFrameTwo()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.frame = context.time.frame_count
        if self.frame == 2:
            context.quit()

        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        if self.frame == 1:
            canvas.fill(Color.RED)
        elif self.frame == 2:
            canvas.fill(Color.GREEN)
        else:
            canvas.fill(Color.BLUE)
        canvas.rectangle(0.0, 0.0, 100.0, 100.0)


def test_frame_quit_stops_the_loop() raises -> None:
    # update() quits on frame 2; run_headless checks canvas._quit before each
    # iteration, so frames 3-5 must never run. If they did, the buffer would
    # show frame 5's blue rather than frame 2's green.
    var m = run_headless[QuitOnFrameTwo](50, 50, 5)
    assert_equal(m.pixel(25, 25), Color.GREEN)


def _takes_a_bare_canvas(mut canvas: Canvas) raises:
    """Never called — an uncalled `def` body is still type-checked, so this is
    a compile-time guard against `Canvas` ever gaining a parameter. A bare
    `Canvas` reference is what every `update` signature in the library relies
    on; see the `Canvas` docstring.
    """
    canvas.background(Color.BLACK)


struct AnimatorBlit(Program):
    """Eight 2x2 frames, frame i tinted R = i * 20, advanced by the run loop.

    `SpriteAnimation`, `SpriteAnimator` and the `canvas.sprite` overload all
    arrive through `from create import *` alone.
    """

    var animator: SpriteAnimator

    def __init__(out self, var animator: SpriteAnimator):
        self.animator = animator^

    @staticmethod
    def create(mut context: Context) raises -> AnimatorBlit:
        var frames = List[Sprite]()
        for i in range(8):
            frames.append(Sprite.solid(2, 2, UInt8(i * 20), 0, 0))
        var a = SpriteAnimator(ArcPointer(SpriteAnimation(frames^, 100.0)))
        a.play()
        return AnimatorBlit(a^)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.animator.update(context.time.delta)

        canvas.background(Color.BLACK)
        canvas.sprite(self.animator, 0.0, 0.0)


def test_animator_blits_the_current_frame() raises -> None:
    # Headless frames are a synthetic 16ms; at 100 fps a frame is held 10ms, so
    # the playhead runs ahead of the loop: after one frame it is on index 1,
    # and after three (48ms, 4.8 frame durations) on index 4. Same render call
    # each time, so the overload reads the live index rather than a frame
    # captured at construction.
    assert_equal(
        run_headless[AnimatorBlit](100, 100, frames=1).pixel(50, 50),
        Color(20, 0, 0),
    )
    assert_equal(
        run_headless[AnimatorBlit](100, 100, frames=3).pixel(50, 50),
        Color(80, 0, 0),
    )


struct AnimatorSized(Program):
    var animator: SpriteAnimator

    def __init__(out self, var animator: SpriteAnimator):
        self.animator = animator^

    @staticmethod
    def create(mut context: Context) raises -> AnimatorSized:
        var frames = List[Sprite]()
        frames.append(Sprite.solid(2, 2, 255, 0, 0))
        return AnimatorSized(
            SpriteAnimator(ArcPointer(SpriteAnimation(frames^)))
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.sprite(self.animator, Point2D(0.0, 0.0), 40, 40)


def test_animator_sized_overload_scales() raises -> None:
    # A 2x2 frame rendered at 40x40 covers the centre out to +/-20 world units.
    var m = run_headless[AnimatorSized](100, 100)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(31, 31), Color.RED)
    assert_equal(m.pixel(69, 69), Color.RED)
    assert_equal(m.pixel(29, 29), Color.BLACK)


struct AnimatorEveryOverload(Program):
    """Renders through all six `canvas.sprite(SpriteAnimator, ...)` overloads.

    Five of them delegate to the two that index the frame, so without a call
    site each they are never type-checked: a library build only checks the
    `def` bodies it reaches. The assertions below double as the positioning
    check -- every overload must land its frame on the same anchor its
    `Sprite` counterpart would.
    """

    var animator: SpriteAnimator

    def __init__(out self, var animator: SpriteAnimator):
        self.animator = animator^

    @staticmethod
    def create(mut context: Context) raises -> AnimatorEveryOverload:
        var frames = List[Sprite]()
        frames.append(Sprite.solid(2, 2, 255, 0, 0))
        return AnimatorEveryOverload(
            SpriteAnimator(ArcPointer(SpriteAnimation(frames^)))
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        # Top row: the unsized overloads, at 1:1 so the 2x2 frame covers its
        # own anchor pixel.
        canvas.sprite(self.animator, -40.0, 40.0)
        canvas.sprite(self.animator, -20, 40)
        canvas.sprite(self.animator, Point2D(0.0, 40.0))
        # Bottom row: the sized overloads, scaled up to 4x4.
        canvas.sprite(self.animator, -40.0, -40.0, 4, 4)
        canvas.sprite(self.animator, -20, -40, 4, 4)
        canvas.sprite(self.animator, Point2D(0.0, -40.0), 4, 4)


def test_every_animator_overload_renders_at_its_anchor() raises -> None:
    # World (x, y) maps to pixel (50 + x, 50 - y) at 1:1 on a 100x100 frame.
    var m = run_headless[AnimatorEveryOverload](100, 100)
    assert_equal(m.pixel(10, 10), Color.RED)  # (a, Float64, Float64)
    assert_equal(m.pixel(30, 10), Color.RED)  # (a, Int, Int)
    assert_equal(m.pixel(50, 10), Color.RED)  # (a, Point2D)
    assert_equal(m.pixel(10, 90), Color.RED)  # (a, Float64, Float64, w, h)
    assert_equal(m.pixel(30, 90), Color.RED)  # (a, Int, Int, w, h)
    assert_equal(m.pixel(50, 90), Color.RED)  # (a, Point2D, w, h)
    # Between the two rows nothing was rendered.
    assert_equal(m.pixel(50, 50), Color.BLACK)


# --- canvas.save_image -------------------------------------------------------
#
# Every one of these runs a design of 200x100 into a 640x480 buffer, so the
# live frame is scaled by 3.2 and letterboxed — the export is only proving
# anything if the framebuffer it came from looks nothing like it.

comptime _IMG_1X = "/tmp/mojo_create_test_save_image_1x.png"
comptime _IMG_2X = "/tmp/mojo_create_test_save_image_2x.png"
comptime _IMG_ALPHA = "/tmp/mojo_create_test_save_image_alpha.png"


def _saved(path: String) raises -> Sprite:
    """Read back a file one of these programs wrote, then delete it."""
    var back = Sprite.load(path)
    remove(path)
    return back^


def _px(s: Sprite, x: Int, y: Int) -> Color:
    var off = (y * s.width + x) * 4
    return Color(
        s.pixels[off], s.pixels[off + 1], s.pixels[off + 2], s.pixels[off + 3]
    )


def _scene(mut canvas: Canvas):
    """A black ground with a 20x20 red square on the origin.

    In design space the square covers x in [90, 110) and y in [40, 60), so the
    export can be checked against design coordinates directly.
    """
    canvas.background(Color.BLACK)
    canvas.outline_enabled(False)
    canvas.fill(Color.RED)
    canvas.rectangle(0.0, 0.0, 20.0, 20.0)


@fieldwise_init
struct SaveImage(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SaveImage:
        return SaveImage(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        _scene(canvas)
        canvas.save_image(_IMG_1X)


@fieldwise_init
struct SaveImage2x(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SaveImage2x:
        return SaveImage2x(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        _scene(canvas)
        canvas.save_image(_IMG_2X, scale=2.0)


@fieldwise_init
struct SaveImageTransparent(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SaveImageTransparent:
        return SaveImageTransparent(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        _scene(canvas)
        canvas.save_image(_IMG_ALPHA, transparent=True)


def test_save_image_writes_the_design_resolution() raises -> None:
    var m = run_headless[SaveImage](200, 100, 1, 640, 480)
    # The framebuffer it was captured from is neither that size nor bar-free.
    assert_equal(m.width, 640)
    assert_equal(m.pixel(320, 5), Color(0x22))
    var img = _saved(_IMG_1X)
    assert_equal(img.width, 200)
    assert_equal(img.height, 100)


def test_save_image_lays_out_in_design_coordinates() raises -> None:
    _ = run_headless[SaveImage](200, 100, 1, 640, 480)
    var img = _saved(_IMG_1X)
    assert_equal(_px(img, 100, 50), Color.RED)
    assert_equal(_px(img, 91, 41), Color.RED)
    assert_equal(_px(img, 108, 58), Color.RED)
    assert_equal(_px(img, 50, 50), Color.BLACK)


def test_save_image_has_no_letterbox_bars() raises -> None:
    _ = run_headless[SaveImage](200, 100, 1, 640, 480)
    var img = _saved(_IMG_1X)
    # Every corner is the program's own background, not the bar colour the
    # live frame carries at the same relative position.
    assert_equal(_px(img, 0, 0), Color.BLACK)
    assert_equal(_px(img, 199, 0), Color.BLACK)
    assert_equal(_px(img, 0, 99), Color.BLACK)
    assert_equal(_px(img, 199, 99), Color.BLACK)


def test_save_image_scales_the_whole_export() raises -> None:
    _ = run_headless[SaveImage2x](200, 100, 1, 640, 480)
    var img = _saved(_IMG_2X)
    assert_equal(img.width, 400)
    assert_equal(img.height, 200)
    # The identical layout at twice the resolution: the square now covers
    # [180, 220) x [80, 120).
    assert_equal(_px(img, 200, 100), Color.RED)
    assert_equal(_px(img, 182, 82), Color.RED)
    assert_equal(_px(img, 100, 100), Color.BLACK)


def test_save_image_can_keep_the_background_clear() raises -> None:
    _ = run_headless[SaveImageTransparent](200, 100, 1, 640, 480)
    var img = _saved(_IMG_ALPHA)
    assert_equal(_px(img, 100, 50), Color.RED)
    # Nothing was rendered here and the clear was dropped, so the buffer's own
    # alpha 0 survives all the way to the file.
    assert_equal(_px(img, 10, 10), Color(0, 0, 0, 0))


comptime _SHOT = "/tmp/mojo_create_test_save_screenshot.png"
comptime _BOTH_SHOT = "/tmp/mojo_create_test_save_both_shot.png"
comptime _BOTH_IMG = "/tmp/mojo_create_test_save_both_image.png"


@fieldwise_init
struct SaveScreenshot(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SaveScreenshot:
        return SaveScreenshot(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        _scene(canvas)
        canvas.save_screenshot(_SHOT)


@fieldwise_init
struct SaveBoth(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> SaveBoth:
        return SaveBoth(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        _scene(canvas)
        canvas.save_screenshot(_BOTH_SHOT)
        canvas.save_image(_BOTH_IMG)


def test_save_screenshot_writes_the_framebuffer_resolution() raises -> None:
    _ = run_headless[SaveScreenshot](200, 100, 1, 640, 480)
    var shot = _saved(_SHOT)
    assert_equal(shot.width, 640)
    assert_equal(shot.height, 480)


def test_save_screenshot_keeps_the_letterbox_bars() raises -> None:
    # The exact complement of the save_image assertion: same frame, and the
    # corner that is the program's background there is bar here.
    _ = run_headless[SaveScreenshot](200, 100, 1, 640, 480)
    var shot = _saved(_SHOT)
    assert_equal(_px(shot, 320, 5), Color(0x22))
    assert_equal(_px(shot, 320, 474), Color(0x22))
    # The design area sits in the middle, scaled by 3.2 rather than 1:1.
    assert_equal(_px(shot, 320, 240), Color.RED)


def test_both_captures_can_be_pending_in_one_frame() raises -> None:
    _ = run_headless[SaveBoth](200, 100, 1, 640, 480)
    var shot = _saved(_BOTH_SHOT)
    var img = _saved(_BOTH_IMG)
    assert_equal(shot.width, 640)
    assert_equal(img.width, 200)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
