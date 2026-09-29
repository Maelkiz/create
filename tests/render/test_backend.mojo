# The CPU backend replays a recorded command list onto a Surface. These tests
# hand-build the list — no Canvas involved — so they check the replay itself,
# and the last one pins it against the Canvas output it has to reproduce.

from std.math import pi, max, min
from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless
from create.render.surface import MemorySurface
from create.render._viewport import Viewport
from create.render.style import Style
from create.render._backend import Backend
from create.render._raster import blend
from create.render._transform import pixel_scale, outline_thickness_px
from create.render._shadow import box_coverage
from create.render._command import (
    CMD_CLEAR,
    CMD_LETTERBOX,
    RenderCommand,
    clear_command,
    rect_command,
    circle_command,
    line_command,
    triangle_command,
    sprite_command,
    text_command,
    letterbox_command,
    bezier_command,
    bezier_chain_command,
)
from create.math.matrix import apply as mat_apply
from create.math.point2d import Point2D


comptime _W = 100
comptime _H = 100


def _base(width: Int = _W, height: Int = _H) -> Matrix[3, 3]:
    """The same world-to-pixel mapping a 1:1 frame gets, taken from `Viewport`
    rather than rebuilt, so a change there cannot silently desync these."""
    var v = Viewport()
    v.set_design(width, height)
    v.set_size(width, height)
    return v.base_matrix()


def _solid(fill: Color) -> Style:
    var s = Style()
    s.fill_color = fill
    s.fill_enabled = True
    s.outline_enabled = False
    return s^


def _replay(cmds: List[RenderCommand]) raises -> MemorySurface:
    var mem = MemorySurface(_W, _H)
    var backend = Backend()
    backend.replay(mem.surface(), cmds, 1.0)
    return mem^


def test_clear_covers_every_pixel() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color(10, 20, 30)))
    var m = _replay(cmds)
    assert_equal(m.pixel(0, 0), Color(10, 20, 30))
    assert_equal(m.pixel(_W - 1, _H - 1), Color(10, 20, 30))
    assert_equal(m.pixel(50, 50), Color(10, 20, 30))


def test_rect_replays_centred_and_y_up() raises -> None:
    # A 20x20 rect at the world origin covers pixels [40, 60) on both axes —
    # the same centring promise the Canvas tests assert.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), _solid(Color.RED), 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(41, 41), Color.RED)
    assert_equal(m.pixel(58, 58), Color.RED)
    assert_equal(m.pixel(30, 50), Color.BLACK)
    assert_equal(m.pixel(50, 30), Color.BLACK)


def test_rect_above_the_origin_lands_above_it() raises -> None:
    # Positive world y is a smaller pixel row. A y-down replay would paint the
    # mirror of this and every other assertion here would still pass.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), _solid(Color.RED), 0.0, 20.0, 10.0, 10.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 30), Color.RED)
    assert_equal(m.pixel(50, 70), Color.BLACK)


def test_rect_outline_frames_the_fill() raises -> None:
    var st = _solid(Color.RED)
    st.outline_enabled = True
    st.outline_color = Color.BLUE
    st.outline_thickness = 2
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), st, 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(41, 50), Color.BLUE)
    assert_equal(m.pixel(50, 50), Color.RED)


def test_rect_outline_with_zero_alpha_matches_outline_disabled() raises -> None:
    # An outline nobody can see should skip rasterisation the same way an
    # explicitly disabled one does — both must leave the fill untouched and
    # paint no outline colour anywhere.
    var st = _solid(Color.RED)
    st.outline_enabled = True
    st.outline_color = Color(0, 0, 255, 0)
    st.outline_thickness = 2
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), st, 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    # Column 40 is where a visible outline this thick would land — see
    # test_rect_outline_frames_the_fill's pixel(41, 50) with thickness 2.
    assert_equal(m.pixel(40, 50), Color.RED)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(30, 50), Color.BLACK)


def test_rect_outline_with_zero_thickness_matches_outline_disabled() raises -> (
    None
):
    var st = _solid(Color.RED)
    st.outline_enabled = True
    st.outline_color = Color.BLUE
    st.outline_thickness = 0
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), st, 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    # outline_thickness_px floors at 1px, so a naive gate would still paint a
    # 1px BLUE ring at column 40 — this is what catches that.
    assert_equal(m.pixel(40, 50), Color.RED)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(30, 50), Color.BLACK)


def test_circle_replays_round() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(circle_command(_base(), _solid(Color.GREEN), 0.0, 0.0, 20.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.GREEN)
    assert_equal(m.pixel(50, 35), Color.GREEN)
    # The corner of the bounding box is outside the disc.
    assert_equal(m.pixel(35, 35), Color.BLACK)


def test_circle_samples_pixel_centres() raises -> None:
    # Centred on the corner shared by pixels 49 and 50, a radius of 10 covers
    # columns 40 to 59: ten each side, as the GPU rasterises it. Testing the
    # pixel corners instead reaches column 60 and misses nothing on the left.
    # A rotation takes the non-uniform branch, which must agree.
    for turn in range(2):
        var m = _base() @ rotate(0.3 * Float64(turn))
        var cmds = List[RenderCommand]()
        cmds.append(clear_command(Color.BLACK))
        cmds.append(circle_command(m, _solid(Color.GREEN), 0.0, 0.0, 10.0))
        var got = _replay(cmds)
        for row in [49, 50]:
            assert_equal(got.pixel(39, row), Color.BLACK)
            assert_equal(got.pixel(40, row), Color.GREEN)
            assert_equal(got.pixel(59, row), Color.GREEN)
            assert_equal(got.pixel(60, row), Color.BLACK)


def _brute_circle(
    mut mem: MemorySurface,
    m: Matrix[3, 3],
    style: Style,
    cx: Float64,
    cy: Float64,
    r: Float64,
    scale: Float64,
) raises -> None:
    """The pixel-by-pixel distance test `_circle`'s uniform branch used
    before it was rewritten to per-row analytic spans — kept here as the
    ground truth the span rewrite must reproduce byte-for-byte. Samples
    pixel centres, as the span version does: the centre moves back half a
    pixel instead, so the arithmetic is the same to the last bit."""
    var s = mem.surface()
    var W = s.width
    var H = s.height
    var p = apply(m, cx, cy)
    var pcx = p[0] - 0.5
    var pcy = p[1] - 0.5
    var pr = r * pixel_scale(m, scale)
    var pr2 = pr * pr
    var pr_inner = pr - Float64(outline_thickness_px(style, m, scale))
    var pr_inner2 = pr_inner * pr_inner
    var x0 = max(Int(pcx - pr), 0)
    var y0 = max(Int(pcy - pr), 0)
    var x1 = min(Int(pcx + pr) + 1, W)
    var y1 = min(Int(pcy + pr) + 1, H)
    for row in range(y0, y1):
        var dy = Float64(row) - pcy
        for col in range(x0, x1):
            var dx = Float64(col) - pcx
            var d2 = dx * dx + dy * dy
            if d2 <= pr2:
                var off = (row * W + col) * 4
                if style.fill_enabled and (
                    not style.outline_enabled
                    or pr_inner <= 0.0
                    or d2 <= pr_inner2
                ):
                    blend(s, off, style.fill_color)
                elif style.outline_enabled and d2 > pr_inner2:
                    blend(s, off, style.outline_color)


def _check_circle_matches_brute_force(
    cx: Float64,
    cy: Float64,
    r: Float64,
    fill_enabled: Bool,
    outline_enabled: Bool,
    outline_thickness: Int,
) raises -> None:
    var m = _base()
    var st = Style()
    st.fill_color = Color.RED
    st.fill_enabled = fill_enabled
    st.outline_color = Color.BLUE
    st.outline_enabled = outline_enabled
    st.outline_thickness = outline_thickness

    var want = MemorySurface(_W, _H)
    _brute_circle(want, m, st, cx, cy, r, 1.0)

    var cmds = List[RenderCommand]()
    cmds.append(circle_command(m, st, cx, cy, r))
    var got = _replay(cmds)

    for y in range(_H):
        for x in range(_W):
            assert_equal(
                got.pixel(x, y),
                want.pixel(x, y),
                "pixel " + String(x) + "," + String(y),
            )


def test_circle_span_matches_brute_force_fill_only() raises -> None:
    _check_circle_matches_brute_force(0.0, 0.0, 20.0, True, False, 1)


def test_circle_span_matches_brute_force_outline_only() raises -> None:
    _check_circle_matches_brute_force(0.0, 0.0, 20.0, False, True, 3)


def test_circle_span_matches_brute_force_fill_and_outline() raises -> None:
    _check_circle_matches_brute_force(0.0, 0.0, 20.0, True, True, 3)


def test_circle_span_matches_brute_force_radius_under_one_pixel() raises -> (
    None
):
    _check_circle_matches_brute_force(10.0, -8.0, 0.6, True, True, 1)
    _check_circle_matches_brute_force(10.0, -8.0, 0.6, True, False, 1)


def test_circle_span_matches_brute_force_outline_wider_than_radius() raises -> (
    None
):
    _check_circle_matches_brute_force(-15.0, 5.0, 12.0, True, True, 40)
    _check_circle_matches_brute_force(-15.0, 5.0, 12.0, False, True, 40)


def test_circle_span_matches_brute_force_pr_inner_exactly_zero() raises -> None:
    _check_circle_matches_brute_force(5.0, 5.0, 12.0, True, True, 12)


def test_line_replays_between_its_endpoints() raises -> None:
    var st = Style()
    st.fill_enabled = False
    st.outline_enabled = True
    st.outline_color = Color.WHITE
    # Two wide, so the band covers whole rows either side of y = 0, which
    # sits on the boundary between rows 49 and 50.
    st.outline_thickness = 2
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(line_command(_base(), st, -20.0, 0.0, 20.0, 0.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 49), Color.WHITE)
    assert_equal(m.pixel(50, 50), Color.WHITE)
    assert_equal(m.pixel(35, 50), Color.WHITE)
    assert_equal(m.pixel(50, 40), Color.BLACK)


def test_line_with_outline_disabled_renders_nothing() raises -> None:
    var st = Style()
    st.outline_enabled = False
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(line_command(_base(), st, -20.0, 0.0, 20.0, 0.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.BLACK)


def _s_curve() -> CubicBezier:
    return CubicBezier(
        (-40.0, -30.0), (-40.0, 60.0), (40.0, -60.0), (40.0, 30.0)
    )


def _stroke(color: Color, thickness: Int) -> Style:
    var st = Style()
    st.outline_enabled = True
    st.outline_color = color
    st.outline_thickness = thickness
    return st^


def test_bezier_replays_along_the_curve_without_gaps() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(bezier_command(_base(), _stroke(Color.WHITE, 4), _s_curve()))
    var m = _replay(cmds)
    # Four wide, so the pixel holding any point on the curve is covered,
    # joints between flattened segments included. The ends are left out:
    # each lands on a pixel boundary, where the butt end cuts square.
    var curve = _s_curve()
    for i in range(1, 200):
        var q = curve.at(Float64(i) / 200.0)
        var p = mat_apply(_base(), q.x, q.y)
        assert_equal(m.pixel(Int(p[0]), Int(p[1])), Color.WHITE)
    # Beside the curve, and past its ends, stays clear.
    assert_equal(m.pixel(5, 5), Color.BLACK)
    assert_equal(m.pixel(50, 10), Color.BLACK)
    assert_equal(m.pixel(95, 95), Color.BLACK)


def test_bezier_with_outline_disabled_renders_nothing() raises -> None:
    var st = _stroke(Color.WHITE, 4)
    st.outline_enabled = False
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(bezier_command(_base(), st, _s_curve()))
    var m = _replay(cmds)
    for y in range(_H):
        for x in range(_W):
            assert_equal(m.pixel(x, y), Color.BLACK)


def test_translucent_bezier_composites_each_pixel_once() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        bezier_command(
            _base(), _stroke(Color(255, 255, 255, 128), 6), _s_curve()
        )
    )
    var m = _replay(cmds)
    # The colour one composite gives, read where only one quad reaches.
    var mid = _s_curve().at(0.5)
    var p = mat_apply(_base(), mid.x, mid.y)
    var once = m.pixel(Int(p[0]), Int(p[1]))
    assert_true(once != Color.BLACK and once != Color.WHITE)
    var painted = 0
    for y in range(_H):
        for x in range(_W):
            var px = m.pixel(x, y)
            if px != Color.BLACK:
                # A pixel two quads both covered would be lighter.
                assert_equal(px, once)
                painted += 1
    assert_true(painted > 0)


def test_translucent_bezier_chain_composites_once_at_the_joint() raises -> None:
    # Two curves meeting smoothly at the origin: one stroke, so the joint
    # composites once like everywhere else.
    var chain: List[Point2D] = [
        (-45.0, -20.0),
        (-30.0, 40.0),
        (-10.0, 40.0),
        (0.0, 0.0),
        (10.0, -40.0),
        (30.0, -40.0),
        (45.0, 20.0),
    ]
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        bezier_chain_command(
            _base(), _stroke(Color(255, 255, 255, 128), 6), chain^
        )
    )
    var m = _replay(cmds)
    var p = mat_apply(_base(), 0.0, 0.0)
    var once = m.pixel(Int(p[0]), Int(p[1]))
    assert_true(once != Color.BLACK and once != Color.WHITE)
    var painted = 0
    for y in range(_H):
        for x in range(_W):
            var px = m.pixel(x, y)
            if px != Color.BLACK:
                assert_equal(px, once)
                painted += 1
    assert_true(painted > 0)


def test_triangle_replays_inside_only() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        triangle_command(
            _base(), _solid(Color.RED), 0.0, 20.0, -20.0, -20.0, 20.0, -20.0
        )
    )
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 60), Color.RED)
    # Outside the sloping edge, still inside the bounding box.
    assert_equal(m.pixel(32, 33), Color.BLACK)


def test_sprite_replays_from_an_interned_image() raises -> None:
    # Two pixels: red left, blue right. Interning copies them into the backend,
    # so the command only ever carries the id.
    var src = List[UInt8](length=8, fill=0)
    src[0] = 255
    src[3] = 255
    src[6] = 255
    src[7] = 255
    var mem = MemorySurface(_W, _H)
    var backend = Backend()
    var id = backend.intern_image(7, src.unsafe_ptr(), 2, 1)
    assert_equal(id, 7)

    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        sprite_command(_base(), Style(), 0.0, 0.0, 20.0, 10.0, id, 2, 1)
    )
    backend.replay(mem.surface(), cmds, 1.0)
    assert_equal(mem.pixel(45, 50), Color.RED)
    assert_equal(mem.pixel(55, 50), Color.BLUE)


def test_interning_the_same_key_twice_reuses_the_copy() raises -> None:
    var src = List[UInt8](length=4, fill=255)
    var backend = Backend()
    var a = backend.intern_image(3, src.unsafe_ptr(), 1, 1)
    var b = backend.intern_image(3, src.unsafe_ptr(), 1, 1)
    assert_equal(a, b)
    assert_equal(len(backend.images), 1)


def test_sprite_with_an_unknown_image_is_skipped() raises -> None:
    # A command referring to an id the backend never interned must be dropped,
    # not read out of bounds.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        sprite_command(_base(), Style(), 0.0, 0.0, 20.0, 10.0, 999, 2, 1)
    )
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.BLACK)


def test_text_replays_through_the_backend_font() raises -> None:
    # Layout happens here, at replay, in the backend that owns the font — the
    # command carried nothing but the string and its anchor.
    var st = _solid(Color.WHITE)
    st.text_color = Color.WHITE
    st.font_size = 24
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(text_command(_base(), st, -40.0, 0.0, String("III")))
    var m = _replay(cmds)
    var lit = 0
    for y in range(_H):
        for x in range(_W):
            if m.pixel(x, y) != Color.BLACK:
                lit += 1
    assert_true(lit > 0, "text drew no pixels")


def test_text_with_a_transparent_text_color_renders_nothing() raises -> None:
    var st = Style()
    st.text_color = Color(255, 255, 255, 0)
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(text_command(_base(), st, -40.0, 0.0, String("III")))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.BLACK)


def test_a_pre_matrix_relocates_the_whole_replay() raises -> None:
    # What a capture does: the commands were recorded against one mapping and
    # are replayed against another, without rewriting the command list.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), _solid(Color.RED), 0.0, 0.0, 20.0, 20.0))
    var mem = MemorySurface(_W, _H)
    var backend = Backend()
    backend.replay(mem.surface(), cmds, 1.0, pre=translate(-30.0, 0.0))
    # The rect moved 30 pixels left; the clear, which has no geometry, did not.
    assert_equal(mem.pixel(20, 50), Color.RED)
    assert_equal(mem.pixel(50, 50), Color.BLACK)


def test_skipping_the_letterbox_leaves_its_region_untouched() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.RED))
    cmds.append(letterbox_command(Color.BLUE, 10.0, 20.0, 90.0, 80.0))
    var mem = MemorySurface(_W, _H)
    var backend = Backend()
    backend.replay(mem.surface(), cmds, 1.0, skip_kinds=1 << CMD_LETTERBOX)
    assert_equal(mem.pixel(50, 50), Color.RED)
    assert_equal(mem.pixel(50, 10), Color.RED)
    assert_equal(mem.pixel(5, 50), Color.RED)


def test_skipping_the_clear_leaves_the_background_transparent() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), _solid(Color.RED), 0.0, 0.0, 20.0, 20.0))
    var mem = MemorySurface(_W, _H)
    var backend = Backend()
    backend.replay(mem.surface(), cmds, 1.0, skip_kinds=1 << CMD_CLEAR)
    assert_equal(mem.pixel(50, 50), Color.RED)
    assert_equal(mem.pixel(10, 10), Color(0, 0, 0, 0))


def test_letterbox_paints_outside_the_device_content_rect() raises -> None:
    # The one command whose geometry is already device pixels.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.RED))
    cmds.append(letterbox_command(Color.BLUE, 10.0, 20.0, 90.0, 80.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(50, 10), Color.BLUE)
    assert_equal(m.pixel(50, 90), Color.BLUE)
    assert_equal(m.pixel(5, 50), Color.BLUE)
    assert_equal(m.pixel(95, 50), Color.BLUE)


def test_commands_replay_in_order() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), _solid(Color.RED), 0.0, 0.0, 40.0, 40.0))
    cmds.append(rect_command(_base(), _solid(Color.BLUE), 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(50, 50), Color.BLUE)
    assert_equal(m.pixel(35, 50), Color.RED)


comptime _ANGLE = 0.4
comptime _RECT_W = 34.0
comptime _RECT_H = 18.0


struct RotatedRect(Program):
    """The Canvas side of the equivalence check below."""

    var _unused: Int

    @staticmethod
    def create(mut context: Context) raises -> RotatedRect:
        return RotatedRect(0)

    def __init__(out self, unused: Int):
        self._unused = unused

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        with canvas.transform(rotate(_ANGLE)):
            canvas.rectangle((12.0, 6.0), _RECT_W, _RECT_H)


def test_a_rotated_rect_replays_identically_to_canvas() raises -> None:
    # Rotation defeats the axis-aligned fast path, so this is the per-pixel
    # inverse-mapping route — the one the command buffer most has to preserve,
    # since a pre-mapped device rect could not express it at all.
    var want = run_headless[RotatedRect](_W, _H)

    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(
            _base() @ rotate(_ANGLE),
            _solid(Color.RED),
            12.0,
            6.0,
            _RECT_W,
            _RECT_H,
        )
    )
    var got = _replay(cmds)

    for y in range(_H):
        for x in range(_W):
            assert_equal(
                got.pixel(x, y),
                want.pixel(x, y),
                "pixel " + String(x) + "," + String(y),
            )


def test_render_backend_writes_its_constant_name() raises -> None:
    assert_equal(String(RenderBackend.CPU), "RenderBackend.CPU")
    assert_equal(String(RenderBackend.GPU), "RenderBackend.GPU")
    assert_equal(String(RenderBackend(99)), "RenderBackend(99)")


def _shadowed(fill: Color, shadow: Color) -> Style:
    var s = _solid(fill)
    s.shadow_enabled = True
    s.shadow_color = shadow
    s.shadow_offset = Vector2D(10, -10)
    s.shadow_blur = 0.0
    return s^


def test_shadow_lands_down_right_and_under_the_shape() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(
            _base(), _shadowed(Color.WHITE, Color.RED), 0.0, 0.0, 20.0, 20.0
        )
    )
    var m = _replay(cmds)
    # Shape covers [40, 60); its shadow [50, 70), device rows running down.
    assert_equal(m.pixel(50, 50), Color.WHITE)
    assert_equal(m.pixel(65, 65), Color.RED)
    assert_equal(m.pixel(55, 65), Color.RED)
    assert_equal(m.pixel(45, 45), Color.WHITE)
    assert_equal(m.pixel(35, 35), Color.BLACK)
    assert_equal(m.pixel(72, 72), Color.BLACK)


def test_translucent_shadow_is_one_even_layer_under_an_outline() raises -> None:
    var s = _shadowed(Color.WHITE, Color(0, 0, 0, 128))
    s.outline_enabled = True
    s.outline_color = Color.BLUE
    s.outline_thickness = 3
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.WHITE))
    cmds.append(rect_command(_base(), s, 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    # Row 51 is where the shifted outline ring would run; it must not be any
    # darker than the middle of the silhouette.
    assert_equal(m.pixel(65, 51), m.pixel(65, 65))
    assert_true(m.pixel(65, 65) != Color.WHITE)


def test_a_later_shadow_falls_over_earlier_shapes() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(_base(), _solid(Color.WHITE), 0.0, 0.0, 20.0, 20.0)
    )
    cmds.append(
        rect_command(
            _base(), _shadowed(Color.GREEN, Color.RED), -10.0, 10.0, 20.0, 20.0
        )
    )
    var m = _replay(cmds)
    assert_equal(m.pixel(55, 55), Color.RED)
    assert_equal(m.pixel(45, 45), Color.GREEN)


def test_disabled_shadow_paints_nothing() raises -> None:
    var s = _shadowed(Color.WHITE, Color.RED)
    s.shadow_enabled = False
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), s, 0.0, 0.0, 20.0, 20.0))
    var m = _replay(cmds)
    assert_equal(m.pixel(65, 65), Color.BLACK)


def test_circle_and_line_cast_shadows() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        circle_command(
            _base(), _shadowed(Color.WHITE, Color.RED), 0.0, 0.0, 8.0
        )
    )
    var ls = _shadowed(Color.WHITE, Color.RED)
    ls.outline_enabled = True
    ls.outline_color = Color.WHITE
    ls.outline_thickness = 2
    cmds.append(line_command(_base(), ls, -40.0, 40.0, -20.0, 40.0))
    var m = _replay(cmds)
    # Circle centre (50, 50) shadow centre (60, 60), outside the disc.
    assert_equal(m.pixel(60, 60), Color.RED)
    # Line at device row 10, cols 10..30; shadow at row 20, cols 20..40.
    assert_equal(m.pixel(35, 20), Color.RED)


def test_bezier_casts_its_stroke_at_the_offset() raises -> None:
    var plain = _stroke(Color.WHITE, 4)
    var shadowed = _shadowed(Color.WHITE, Color.RED)
    shadowed.fill_enabled = False
    shadowed.outline_enabled = True
    shadowed.outline_color = Color.WHITE
    shadowed.outline_thickness = 4
    var alone = List[RenderCommand]()
    alone.append(clear_command(Color.BLACK))
    alone.append(bezier_command(_base(), plain, _s_curve()))
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(bezier_command(_base(), shadowed, _s_curve()))
    var stroke = _replay(alone)
    var m = _replay(cmds)
    # The shadow is the stroke moved 10 right and 10 down, under the stroke.
    var shadow_pixels = 0
    for y in range(_H - 10):
        for x in range(_W - 10):
            var moved = m.pixel(x + 10, y + 10)
            if stroke.pixel(x, y) == Color.WHITE:
                assert_true(moved == Color.RED or moved == Color.WHITE)
                if moved == Color.RED:
                    shadow_pixels += 1
            elif stroke.pixel(x + 10, y + 10) != Color.WHITE:
                assert_equal(moved, Color.BLACK)
    assert_true(shadow_pixels > 0)


def _blurred(fill: Color, blur: Float64) -> Style:
    """White ink blurred by `blur`, thrown 60 units right of its shape."""
    var s = _shadowed(fill, Color.WHITE)
    s.shadow_offset = Vector2D(60, 0)
    s.shadow_blur = blur
    return s^


def _near(got: UInt8, want: Float64, tolerance: Int = 1) -> Bool:
    return abs(Int(got) - Int(want + 0.5)) <= tolerance


def test_blurred_rect_shadow_follows_the_box_profile() raises -> None:
    # Shape at x in [-40, -20]; shadow at [20, 40] -> device columns 70..90,
    # tall enough that the vertical factor is 1 on row 50. sigma = 4.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(
            _base(), _blurred(Color.GREEN, 8.0), -30.0, 0.0, 20.0, 90.0
        )
    )
    var m = _replay(cmds)
    for px in range(60, 100):
        var x = Float64(px) + 0.5
        var want = 255.0 * box_coverage(
            (x - 70.0) / 4.0, (90.0 - x) / 4.0, 1e9, 1e9
        )
        assert_true(_near(m.pixel(px, 50).r, want), String(px))
    # Half on the silhouette's edge, symmetric about it.
    assert_true(abs(Int(m.pixel(70, 50).r) + Int(m.pixel(69, 50).r) - 255) <= 2)
    # A hard shadow would stop at 90; this one fades to nothing by 4 sigma.
    assert_true(m.pixel(96, 50).r > 0)
    for px in range(90 + 16, 100):
        assert_equal(m.pixel(px, 50), Color.BLACK)


def test_blurred_ring_shadow_is_hollow() raises -> None:
    var s = _blurred(Color.GREEN, 2.0)
    s.fill_enabled = False
    s.outline_enabled = True
    s.outline_color = Color.GREEN
    s.outline_thickness = 4
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), s, -30.0, 0.0, 30.0, 30.0))
    var m = _replay(cmds)
    # Shadow spans columns 65..95; its ring's middle is at 67, its hole at 80.
    assert_true(m.pixel(67, 50).r > 200)
    assert_equal(m.pixel(80, 50), Color.BLACK)


def test_every_shape_kind_casts_a_blurred_shadow() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        circle_command(_base(), _blurred(Color.GREEN, 4.0), -30.0, 30.0, 8.0)
    )
    cmds.append(
        triangle_command(
            _base(),
            _blurred(Color.GREEN, 4.0),
            -40.0,
            -10.0,
            -20.0,
            -10.0,
            -30.0,
            10.0,
        )
    )
    var ls = _blurred(Color.GREEN, 4.0)
    ls.outline_enabled = True
    ls.outline_color = Color.GREEN
    ls.outline_thickness = 4
    cmds.append(line_command(_base(), ls, -40.0, -35.0, -20.0, -35.0))
    var m = _replay(cmds)
    # Each shadow's middle is solid, and it softens away from it.
    assert_true(m.pixel(80, 20).r > 240)  # circle, centre (80, 20)
    assert_true(m.pixel(80, 51).r > 200)  # triangle, centroid near (80, 53)
    assert_true(m.pixel(80, 85).r > 150)  # line, row 85
    assert_true(m.pixel(80, 92).r < 20)
    assert_equal(m.pixel(80, 0), Color.BLACK)


def _blurred_sprite_frame(mut backend: Backend, mut mem: MemorySurface) raises:
    """A 20x20 opaque sprite at the world origin, its shadow blurred by 8
    and thrown 40 units right: sprite over columns 30..49, shadow 70..89."""
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    var s = _blurred(Color.GREEN, 8.0)
    s.shadow_offset = Vector2D(40, 0)
    cmds.append(sprite_command(_base(), s^, -10.0, 0.0, 20.0, 20.0, 3, 2, 2))
    backend.replay(mem.surface(), cmds, 1.0)


def test_a_blurred_sprite_shadow_softens_past_its_silhouette() raises -> None:
    var src = List[UInt8](length=16, fill=255)
    var backend = Backend()
    _ = backend.intern_image(3, src.unsafe_ptr(), 2, 2)
    var mem = MemorySurface(_W, _H)
    _blurred_sprite_frame(backend, mem)
    # The silhouette spans columns 70..89 on row 50 (sprite at 30..49).
    assert_true(mem.pixel(80, 50).r > 240, "the middle isn't solid")
    var edge = Int(mem.pixel(89, 50).r) + Int(mem.pixel(90, 50).r)
    assert_true(abs(edge - 255) <= 40, "the edge isn't half covered")
    assert_true(mem.pixel(94, 50).r > 0, "the blur stops at the edge")
    assert_true(mem.pixel(94, 50).r < 128)
    # Once the frame is cached, a repeat blurs nothing new.
    assert_equal(len(backend.shadow_masks), 1)
    _blurred_sprite_frame(backend, mem)
    assert_equal(len(backend.shadow_masks), 1)


def test_a_blurred_text_shadow_is_softer_than_a_hard_one() raises -> None:
    # Red under green, so a pixel with red and no green is shadow alone.
    var hard = _shadowed(Color.GREEN, Color.RED)
    hard.text_color = Color.GREEN
    hard.font_size = 40
    hard.shadow_offset = Vector2D(0, 0)
    var soft = hard.copy()
    soft.shadow_blur = 8.0
    var a = List[RenderCommand]()
    a.append(clear_command(Color.BLACK))
    a.append(text_command(_base(), hard^, 0.0, 0.0, "l"))
    var b = List[RenderCommand]()
    b.append(clear_command(Color.BLACK))
    b.append(text_command(_base(), soft^, 0.0, 0.0, "l"))
    var ma = _replay(a)
    var mb = _replay(b)
    # The hard shadow sits exactly under the glyph; the blurred one spills
    # out beside it in the shadow colour.
    var spill_hard = 0
    var spill_soft = 0
    for y in range(_H):
        for x in range(_W):
            if ma.pixel(x, y).g == 0 and ma.pixel(x, y).r > 0:
                spill_hard += 1
            if mb.pixel(x, y).g == 0 and mb.pixel(x, y).r > 0:
                spill_soft += 1
    assert_equal(spill_hard, 0)
    assert_true(spill_soft > 50)


def test_a_blurred_bezier_shadow_fades_past_the_stroke() raises -> None:
    # Red under green, so a pixel with red and no green is shadow alone.
    var hard = _shadowed(Color.GREEN, Color.RED)
    hard.fill_enabled = False
    hard.outline_enabled = True
    hard.outline_color = Color.GREEN
    hard.outline_thickness = 4
    hard.shadow_offset = Vector2D(0, 0)
    var soft = hard.copy()
    soft.shadow_blur = 8.0
    var a = List[RenderCommand]()
    a.append(clear_command(Color.BLACK))
    a.append(bezier_command(_base(), hard^, _s_curve()))
    var b = List[RenderCommand]()
    b.append(clear_command(Color.BLACK))
    b.append(bezier_command(_base(), soft^, _s_curve()))
    var ma = _replay(a)
    var mb = _replay(b)
    var spill_hard = 0
    var spill_soft = 0
    var brightest = 0
    for y in range(_H):
        for x in range(_W):
            if ma.pixel(x, y).g == 0 and ma.pixel(x, y).r > 0:
                spill_hard += 1
            var p = mb.pixel(x, y)
            if p.g == 0 and p.r > 0:
                spill_soft += 1
                brightest = max(brightest, Int(p.r))
    assert_equal(spill_hard, 0)
    assert_true(spill_soft > 100, "the blur doesn't spill past the stroke")
    # Spilled shadow is a fade, never the solid shadow colour.
    assert_true(brightest < 255)
    # Beyond the blur's reach, nothing.
    assert_equal(mb.pixel(2, 2), Color.BLACK)
    assert_equal(mb.pixel(_W - 3, _H - 3), Color.BLACK)


def _inset(fill: Color, offset: Vector2D, blur: Float64 = 0.0) -> Style:
    """`fill` with a red inset shadow thrown by `offset`."""
    var s = _shadowed(fill, Color.RED)
    s.shadow_inset = True
    s.shadow_offset = offset
    s.shadow_blur = blur
    return s^


def test_an_inset_shadow_bands_the_edges_the_offset_leaves() raises -> None:
    # Rect over device [30, 70); the silhouette moves 4 right and 4 down,
    # uncovering the left and top edges.
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(
            _base(), _inset(Color.WHITE, Vector2D(4, -4)), 0.0, 0.0, 40.0, 40.0
        )
    )
    var m = _replay(cmds)
    assert_equal(m.pixel(30, 50), Color.RED)
    assert_equal(m.pixel(33, 50), Color.RED)
    assert_equal(m.pixel(34, 50), Color.WHITE)
    assert_equal(m.pixel(50, 33), Color.RED)
    assert_equal(m.pixel(50, 34), Color.WHITE)
    assert_equal(m.pixel(69, 50), Color.WHITE)
    assert_equal(m.pixel(50, 69), Color.WHITE)
    # Nothing outside the shape.
    assert_equal(m.pixel(29, 50), Color.BLACK)
    assert_equal(m.pixel(50, 29), Color.BLACK)
    assert_equal(m.pixel(72, 72), Color.BLACK)


def test_an_inset_shadow_stays_inside_the_outline() raises -> None:
    for blur in [0.0, 8.0]:
        var s = _inset(Color.WHITE, Vector2D(4, -4), blur)
        s.outline_enabled = True
        s.outline_color = Color.BLUE
        s.outline_thickness = 3
        var cmds = List[RenderCommand]()
        cmds.append(clear_command(Color.BLACK))
        cmds.append(rect_command(_base(), s, 0.0, 0.0, 40.0, 40.0))
        var m = _replay(cmds)
        for y in range(_H):
            for x in range(_W):
                var inside = x >= 30 and x < 70 and y >= 30 and y < 70
                var ring = inside and (x < 33 or x >= 67 or y < 33 or y >= 67)
                if not inside:
                    assert_equal(m.pixel(x, y), Color.BLACK)
                elif ring:
                    assert_equal(m.pixel(x, y), Color.BLUE)
        # The band starts at the outline's inner edge: red over the white
        # fill, not blue.
        var band = m.pixel(33, 50)
        assert_equal(band.r, 255)
        assert_equal(band.g, band.b)
        assert_true(band.g < 255)


def test_a_blurred_inset_shadow_fades_inwards() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(
        rect_command(
            _base(),
            _inset(Color.BLACK, Vector2D(4, -4), 8.0),
            0.0,
            0.0,
            60.0,
            60.0,
        )
    )
    var m = _replay(cmds)
    # Left edge at column 20; the silhouette's edge at 24, sigma 4.
    var last = 256
    for x in range(20, 45):
        var r = Int(m.pixel(x, 50).r)
        assert_true(r <= last, String(x))
        last = r
    # Half on the silhouette's edge, symmetric about it.
    assert_true(abs(Int(m.pixel(23, 50).r) + Int(m.pixel(24, 50).r) - 255) <= 2)
    assert_equal(m.pixel(50, 50), Color.BLACK)
    # The side the offset moves towards stays mostly under the silhouette:
    # four pixels further from its edge than the far side's mirror pixel.
    assert_true(Int(m.pixel(78, 50).r) * 4 < Int(m.pixel(21, 50).r))


def test_spread_shrinks_an_inset_silhouette_all_round() raises -> None:
    var s = _inset(Color.WHITE, Vector2D(0, 0))
    s.shadow_spread = 5.0
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(_base(), s, 0.0, 0.0, 40.0, 40.0))
    var m = _replay(cmds)
    for i in [30, 34, 65, 69]:
        assert_equal(m.pixel(i, 50), Color.RED, String(i))
        assert_equal(m.pixel(50, i), Color.RED, String(i))
    assert_equal(m.pixel(35, 50), Color.WHITE)
    assert_equal(m.pixel(64, 50), Color.WHITE)


def test_circles_and_triangles_take_inset_shadows_inside_only() raises -> None:
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    var cs = _inset(Color.WHITE, Vector2D(6, -6))
    # Unfilled: an inset shadow paints anyway.
    cs.fill_enabled = False
    cmds.append(circle_command(_base(), cs, -25.0, 25.0, 20.0))
    var ts = _inset(Color.WHITE, Vector2D(6, -6))
    ts.corner_radius = 4
    cmds.append(
        triangle_command(_base(), ts, 5.0, -45.0, 45.0, -45.0, 25.0, -5.0)
    )
    var m = _replay(cmds)
    # Circle at device (25, 25): its left inner edge is shadowed, its
    # centre not — and with no fill, the centre shows the background.
    assert_equal(m.pixel(7, 25), Color.RED)
    assert_equal(m.pixel(25, 25), Color.BLACK)
    assert_equal(m.pixel(42, 25), Color.BLACK)
    # Triangle over device (55, 95), (95, 95), (75, 55): its upper-left edge
    # is shadowed, the middle of its bottom edge not.
    assert_equal(m.pixel(64, 80), Color.RED)
    assert_equal(m.pixel(75, 90), Color.WHITE)
    # Every red pixel lies inside one of the two shapes.
    for y in range(_H):
        for x in range(_W):
            if m.pixel(x, y) != Color.RED:
                continue
            var cx = Float64(x) + 0.5 - 25.0
            var cy = Float64(y) + 0.5 - 25.0
            var in_circle = cx * cx + cy * cy <= 400.0
            var in_triangle = y >= 55 and y < 95 and x >= 55 and x < 95
            assert_true(in_circle or in_triangle, String(x, ",", y))


def test_lines_ignore_inset() raises -> None:
    var s = _inset(Color.WHITE, Vector2D(4, -4))
    s.outline_enabled = True
    s.outline_color = Color.WHITE
    s.outline_thickness = 6
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(line_command(_base(), s, -30.0, 0.0, 30.0, 0.0))
    var m = _replay(cmds)
    for y in range(_H):
        for x in range(_W):
            assert_true(m.pixel(x, y) != Color.RED)


def test_beziers_ignore_inset() raises -> None:
    var s = _inset(Color.WHITE, Vector2D(4, -4))
    s.outline_enabled = True
    s.outline_color = Color.WHITE
    s.outline_thickness = 6
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(bezier_command(_base(), s, _s_curve()))
    var m = _replay(cmds)
    for y in range(_H):
        for x in range(_W):
            assert_true(m.pixel(x, y) != Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
