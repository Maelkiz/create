# The CPU backend replays a recorded command list onto a Surface. These tests
# hand-build the list — no Canvas involved — so they check the replay itself,
# and the last one pins it against the Canvas output it has to reproduce.

from std.math import pi, max, min
from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless
from create.render.surface import MemorySurface
from create.render.viewport import Viewport
from create.render.style import Style
from create.render._backend import Backend
from create.render._raster import blend
from create.render._transform import pixel_scale, outline_thickness_px
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
)


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
    ground truth the span rewrite must reproduce byte-for-byte."""
    var s = mem.surface()
    var W = s.width
    var H = s.height
    var p = apply(m, cx, cy)
    var pcx = p[0]
    var pcy = p[1]
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
    st.outline_thickness = 1
    var cmds = List[RenderCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(line_command(_base(), st, -20.0, 0.0, 20.0, 0.0))
    var m = _replay(cmds)
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
            canvas.rectangle(12.0, 6.0, _RECT_W, _RECT_H)


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
