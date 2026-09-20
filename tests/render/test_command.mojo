from std.testing import TestSuite, assert_equal, assert_true, assert_false

from create.render.color import Color
from create.render._style import Style
from create.render._command import (
    CMD_CLEAR,
    CMD_RECT,
    CMD_CIRCLE,
    CMD_LINE,
    CMD_TRIANGLE,
    CMD_SPRITE,
    CMD_TEXT,
    CMD_LETTERBOX,
    DrawCommand,
    clear_command,
    rect_command,
    circle_command,
    line_command,
    triangle_command,
    sprite_command,
    text_command,
    letterbox_command,
)
from create.math.matrix import identity, translate, rotate


def _styled() -> Style:
    var s = Style()
    s.fill_color = Color(10, 20, 30)
    s.outline_color = Color(40, 50, 60)
    s.outline_thickness = 3
    s.font_size = 21
    return s^


def test_rect_packs_centre_and_extent() raises -> None:
    var c = rect_command(identity[3](), Style(), 1.0, 2.0, 3.0, 4.0)
    assert_equal(c.kind, CMD_RECT)
    assert_equal(c.geom[0], 1.0)
    assert_equal(c.geom[1], 2.0)
    assert_equal(c.geom[2], 3.0)
    assert_equal(c.geom[3], 4.0)


def test_circle_packs_centre_and_radius() raises -> None:
    var c = circle_command(identity[3](), Style(), -5.0, 6.0, 7.0)
    assert_equal(c.kind, CMD_CIRCLE)
    assert_equal(c.geom[0], -5.0)
    assert_equal(c.geom[1], 6.0)
    assert_equal(c.geom[2], 7.0)


def test_line_packs_both_endpoints() raises -> None:
    var c = line_command(identity[3](), Style(), 1.0, 2.0, 3.0, 4.0)
    assert_equal(c.kind, CMD_LINE)
    assert_equal(c.geom[0], 1.0)
    assert_equal(c.geom[3], 4.0)


def test_triangle_packs_all_three_vertices() raises -> None:
    var c = triangle_command(
        identity[3](), Style(), 1.0, 2.0, 3.0, 4.0, 5.0, 6.0
    )
    assert_equal(c.kind, CMD_TRIANGLE)
    for i in range(6):
        assert_equal(c.geom[i], Float64(i + 1))


def test_sprite_carries_an_image_id_not_a_pointer() raises -> None:
    var c = sprite_command(
        identity[3](), Style(), 1.0, 2.0, 30.0, 40.0, 77, 16, 24
    )
    assert_equal(c.kind, CMD_SPRITE)
    assert_equal(c.geom[2], 30.0)
    assert_equal(c.image, 77)
    assert_equal(c.image_w, 16)
    assert_equal(c.image_h, 24)


def test_text_owns_its_string() raises -> None:
    var s = String("hello")
    var c = text_command(identity[3](), Style(), 8.0, 9.0, s^)
    assert_equal(c.kind, CMD_TEXT)
    assert_equal(c.text, "hello")
    assert_equal(c.geom[0], 8.0)
    assert_equal(c.geom[1], 9.0)


def test_clear_carries_its_colour_in_the_fill() raises -> None:
    var c = clear_command(Color(1, 2, 3, 4))
    assert_equal(c.kind, CMD_CLEAR)
    assert_equal(c.style.fill_color.r, 1)
    assert_equal(c.style.fill_color.a, 4)
    assert_true(c.style.fill_enabled)


def test_letterbox_carries_the_device_content_rect() raises -> None:
    var c = letterbox_command(Color(9, 9, 9), 10.0, 20.0, 110.0, 220.0)
    assert_equal(c.kind, CMD_LETTERBOX)
    assert_equal(c.geom[0], 10.0)
    assert_equal(c.geom[3], 220.0)
    assert_equal(c.style.fill_color.g, 9)


def test_the_transform_is_kept_whole_not_applied() raises -> None:
    # Geometry must stay local: a pre-mapped device rect could not represent a
    # rotated rectangle, which is the whole reason the matrix travels along.
    var m = rotate(0.5) @ translate(100.0, 200.0)
    var c = rect_command(m, Style(), 0.0, 0.0, 10.0, 10.0)
    assert_equal(c.geom[0], 0.0)
    assert_equal(c.geom[1], 0.0)
    for r in range(3):
        for col in range(3):
            assert_equal(c.transform[r, col], m[r, col])


def test_the_style_is_resolved_at_record_time() raises -> None:
    var s = _styled()
    var c = rect_command(identity[3](), s, 0.0, 0.0, 1.0, 1.0)
    # Mutating the style afterwards must not reach the recorded command.
    s.fill_color = Color(200, 200, 200)
    s.outline_thickness = 99
    assert_equal(c.style.fill_color.r, 10)
    assert_equal(c.style.outline_thickness, 3)
    assert_equal(c.style.font_size, 21)


def test_unused_slots_are_zero() raises -> None:
    var c = circle_command(identity[3](), Style(), 1.0, 2.0, 3.0)
    assert_equal(c.geom[3], 0.0)
    assert_equal(c.geom[4], 0.0)
    assert_equal(c.geom[5], 0.0)


def test_commands_collect_into_a_buffer() raises -> None:
    # The recording shape Frame will use: one heterogeneous list, in order.
    var cmds = List[DrawCommand]()
    cmds.append(clear_command(Color.BLACK))
    cmds.append(rect_command(identity[3](), Style(), 0.0, 0.0, 4.0, 4.0))
    cmds.append(text_command(identity[3](), Style(), 0.0, 0.0, String("hi")))
    assert_equal(len(cmds), 3)
    assert_equal(cmds[0].kind, CMD_CLEAR)
    assert_equal(cmds[1].kind, CMD_RECT)
    assert_equal(cmds[2].kind, CMD_TEXT)
    assert_equal(cmds[2].text, "hi")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
