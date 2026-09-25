"""Geometry assertions for the GL backend, with no GL involved.

Everything the GPU path decides about *where* a triangle goes is decided in
`_tessellate.mojo`, which is pure arithmetic — so it is asserted here against
plain numbers rather than against a framebuffer. That is the whole reason
tessellation is its own module: a GL context, a window and a GPU would
otherwise be prerequisites for testing a coordinate flip.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create.render._command import (
    circle_command,
    letterbox_command,
    line_command,
    rect_command,
    sprite_command,
    triangle_command,
)
from create.render.style import Style
from create.render._tessellate import (
    MODE_SOLID,
    MODE_TEXTURE,
    VertexBuffer,
    circle_segments,
    emit_circle,
    emit_letterbox,
    emit_line,
    emit_rect,
    emit_sprite,
    emit_triangle,
)
from create.math.matrix import rotate
from create.render.autoscale import AutoScale
from create.render.color import Color
from create.render.viewport import Viewport

comptime _FLOATS = 9
"""Mirrors `_tessellate._VERTEX_FLOATS`; spelled out so a change to the vertex
format fails here rather than silently re-slicing these assertions."""


def _viewport(design: Int, pixels: Int) -> Viewport:
    """A `FIT` viewport of `design` world units across `pixels` pixels."""
    var v = Viewport()
    v.autoscale = AutoScale.FIT
    v.set_design(design, design)
    v.set_size(pixels, pixels)
    return v^


def _plain() -> Style:
    """Fill only — the outline that `Style()` enables by default would double
    every vertex count these tests are asserting on."""
    var s = Style()
    s.fill_color = Color.RED
    s.fill_enabled = True
    s.outline_enabled = False
    return s^


def _x(vb: VertexBuffer, i: Int) -> Float64:
    return Float64(vb.data[i * _FLOATS])


def _y(vb: VertexBuffer, i: Int) -> Float64:
    return Float64(vb.data[i * _FLOATS + 1])


def test_a_rect_fill_is_two_triangles() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_rect(
        vb,
        rect_command(v.base_matrix(), _plain(), 0.0, 0.0, 10.0, 20.0),
        v.scale,
    )
    assert_equal(vb.count(), 6)


def test_a_rect_lands_where_the_viewport_maps_it() raises -> None:
    # 100 world units over 100 pixels is 1:1 with the origin at pixel (50, 50),
    # so a 10x20 rect at the origin spans x 45..55 and y 40..60.
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_rect(
        vb,
        rect_command(v.base_matrix(), _plain(), 0.0, 0.0, 10.0, 20.0),
        v.scale,
    )
    var min_x = _x(vb, 0)
    var max_x = _x(vb, 0)
    var min_y = _y(vb, 0)
    var max_y = _y(vb, 0)
    for i in range(1, vb.count()):
        min_x = min(min_x, _x(vb, i))
        max_x = max(max_x, _x(vb, i))
        min_y = min(min_y, _y(vb, i))
        max_y = max(max_y, _y(vb, i))
    assert_equal(min_x, 45.0)
    assert_equal(max_x, 55.0)
    assert_equal(min_y, 40.0)
    assert_equal(max_y, 60.0)


def test_positive_world_y_is_a_smaller_device_y() raises -> None:
    # The y-up convention, asserted on the vertices themselves: the rect above
    # the origin must come out nearer the top of the framebuffer.
    var v = _viewport(100, 100)
    var high = VertexBuffer()
    emit_rect(
        high,
        rect_command(v.base_matrix(), _plain(), 0.0, 20.0, 4.0, 4.0),
        v.scale,
    )
    var low = VertexBuffer()
    emit_rect(
        low,
        rect_command(v.base_matrix(), _plain(), 0.0, -20.0, 4.0, 4.0),
        v.scale,
    )
    assert_true(_y(high, 0) < _y(low, 0))


def test_the_scale_factor_reaches_the_vertices() raises -> None:
    # 100 design units over 200 pixels doubles everything, bars included.
    var vb = VertexBuffer()
    var v = _viewport(100, 200)
    emit_rect(
        vb,
        rect_command(v.base_matrix(), _plain(), 0.0, 0.0, 10.0, 10.0),
        v.scale,
    )
    var min_x = _x(vb, 0)
    var max_x = _x(vb, 0)
    for i in range(1, vb.count()):
        min_x = min(min_x, _x(vb, i))
        max_x = max(max_x, _x(vb, i))
    assert_equal(max_x - min_x, 20.0)


def test_an_outlined_rect_emits_a_fill_and_a_four_quad_ring() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    var s = _plain()
    s.outline_enabled = True
    s.outline_thickness = 2
    emit_rect(
        vb, rect_command(v.base_matrix(), s, 0.0, 0.0, 20.0, 20.0), v.scale
    )
    # One inset fill quad plus four ring quads, six vertices each.
    assert_equal(vb.count(), 30)


def test_an_outline_wider_than_the_rect_leaves_no_fill() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    var s = _plain()
    s.outline_enabled = True
    s.outline_thickness = 40
    emit_rect(
        vb, rect_command(v.base_matrix(), s, 0.0, 0.0, 10.0, 10.0), v.scale
    )
    assert_equal(vb.count(), 6)


def test_an_outlined_rect_fill_is_inset_not_full_size() raises -> None:
    # The fill stops at the outline's inner edge so a translucent shape is not
    # blended twice where the outline overlaps it.
    var v = _viewport(100, 100)
    var s = _plain()
    s.outline_enabled = True
    s.outline_thickness = 2
    var vb = VertexBuffer()
    emit_rect(
        vb, rect_command(v.base_matrix(), s, 0.0, 0.0, 20.0, 20.0), v.scale
    )
    # The fill quad is emitted first: its corners are inset by the 2px outline.
    var min_x = _x(vb, 0)
    var max_x = _x(vb, 0)
    for i in range(1, 6):
        min_x = min(min_x, _x(vb, i))
        max_x = max(max_x, _x(vb, i))
    assert_equal(min_x, 42.0)
    assert_equal(max_x, 58.0)


def test_circle_segments_grow_with_the_device_radius() raises -> None:
    assert_equal(circle_segments(1.0), 12)
    assert_equal(circle_segments(50.0), 50)
    assert_equal(circle_segments(10_000.0), 256)


def test_a_circle_fan_is_one_triangle_per_segment() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_circle(
        vb, circle_command(v.base_matrix(), _plain(), 0.0, 0.0, 30.0), v.scale
    )
    assert_equal(vb.count(), circle_segments(30.0) * 3)


def test_a_circle_reaches_its_radius_in_pixels() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_circle(
        vb, circle_command(v.base_matrix(), _plain(), 0.0, 0.0, 30.0), v.scale
    )
    var max_x = _x(vb, 0)
    for i in range(1, vb.count()):
        max_x = max(max_x, _x(vb, i))
    # The fan's outermost vertex sits exactly on the radius at angle 0.
    assert_equal(max_x, 80.0)


def test_a_line_is_one_quad_of_the_outline_thickness() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    var s = _plain()
    s.outline_enabled = True
    s.outline_thickness = 4
    s.outline_color = Color.BLUE
    emit_line(
        vb, line_command(v.base_matrix(), s, -10.0, 0.0, 10.0, 0.0), v.scale
    )
    assert_equal(vb.count(), 6)
    var min_y = _y(vb, 0)
    var max_y = _y(vb, 0)
    for i in range(1, vb.count()):
        min_y = min(min_y, _y(vb, i))
        max_y = max(max_y, _y(vb, i))
    assert_equal(max_y - min_y, 4.0)


def test_an_unoutlined_line_emits_nothing() raises -> None:
    # A line has no interior, so a fill-only style has nothing to render.
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_line(
        vb,
        line_command(v.base_matrix(), _plain(), -10.0, 0.0, 10.0, 0.0),
        v.scale,
    )
    assert_equal(vb.count(), 0)


def test_a_triangle_is_one_triangle_plus_three_edge_quads() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    var s = _plain()
    s.outline_enabled = True
    emit_triangle(
        vb,
        triangle_command(
            v.base_matrix(), s, 0.0, 10.0, -10.0, -10.0, 10.0, -10.0
        ),
        v.scale,
    )
    assert_equal(vb.count(), 3 + 3 * 6)


def test_letterbox_geometry_skips_the_transform() raises -> None:
    # `letterbox_command` records device pixels and an identity matrix, so the
    # bars must come out exactly as recorded — this is the one kind that is
    # already in device space, and mapping it would be meaningless.
    var vb = VertexBuffer()
    emit_letterbox(
        vb, letterbox_command(Color.BLACK, 20.0, 0.0, 80.0, 100.0), 100, 100
    )
    # Left and right bars only: the content rect spans the full height.
    assert_equal(vb.count(), 12)
    var max_x = _x(vb, 0)
    var min_x = _x(vb, 0)
    for i in range(vb.count()):
        max_x = max(max_x, _x(vb, i))
        min_x = min(min_x, _x(vb, i))
    assert_equal(min_x, 0.0)
    assert_equal(max_x, 100.0)


def test_letterbox_emits_all_four_bars_when_inset_on_both_axes() raises -> None:
    var vb = VertexBuffer()
    emit_letterbox(
        vb, letterbox_command(Color.BLACK, 10.0, 20.0, 90.0, 80.0), 100, 100
    )
    assert_equal(vb.count(), 24)


def test_a_full_frame_content_rect_emits_no_bars() raises -> None:
    var vb = VertexBuffer()
    emit_letterbox(
        vb, letterbox_command(Color.BLACK, 0.0, 0.0, 100.0, 100.0), 100, 100
    )
    assert_equal(vb.count(), 0)


def test_a_sprite_is_one_textured_quad_over_the_full_image() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_sprite(
        vb,
        sprite_command(
            v.base_matrix(), _plain(), 0.0, 0.0, 10.0, 10.0, 7, 32, 32
        ),
        v.scale,
    )
    assert_equal(vb.count(), 6)
    assert_equal(vb.data[8], MODE_TEXTURE)
    var min_u = Float32(1.0)
    var max_u = Float32(0.0)
    for i in range(vb.count()):
        min_u = min(min_u, vb.data[i * _FLOATS + 2])
        max_u = max(max_u, vb.data[i * _FLOATS + 2])
    assert_equal(min_u, Float32(0.0))
    assert_equal(max_u, Float32(1.0))


def test_a_sprite_is_not_flipped() raises -> None:
    # Row 0 of the image belongs at the top of the quad, which in device
    # space — y down — is the smallest y.
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_sprite(
        vb,
        sprite_command(
            v.base_matrix(), _plain(), 0.0, 0.0, 10.0, 10.0, 7, 32, 32
        ),
        v.scale,
    )
    # Vertex 0 is uv (0, 0); vertex 2 is uv (1, 1).
    assert_equal(vb.data[3], Float32(0.0))
    assert_equal(vb.data[2 * _FLOATS + 3], Float32(1.0))
    assert_true(_y(vb, 0) < _y(vb, 2))


def test_a_sprite_is_upright_under_rotation() raises -> None:
    # Only the anchor is mapped, matching the CPU blit — a rotated transform
    # moves the sprite but must not turn it.
    var v = _viewport(100, 100)
    var vb = VertexBuffer()
    emit_sprite(
        vb,
        sprite_command(
            v.base_matrix() @ rotate(0.7),
            _plain(),
            20.0,
            0.0,
            10.0,
            10.0,
            7,
            32,
            32,
        ),
        v.scale,
    )
    assert_equal(_y(vb, 0), _y(vb, 1))
    assert_equal(_x(vb, 0), _x(vb, 5))


def test_a_vertex_carries_its_colour_and_mode() raises -> None:
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    var s = _plain()
    s.fill_color = Color(255, 0, 0, 128)
    emit_rect(vb, rect_command(v.base_matrix(), s, 0.0, 0.0, 4.0, 4.0), v.scale)
    assert_equal(vb.data[4], Float32(1.0))
    assert_equal(vb.data[5], Float32(0.0))
    assert_equal(vb.data[6], Float32(0.0))
    assert_equal(vb.data[7], Float32(128.0) / 255.0)
    assert_equal(vb.data[8], MODE_SOLID)


def test_clearing_keeps_the_allocation() raises -> None:
    # The frame loop reuses one buffer; a clear that dropped the capacity
    # would allocate on every frame.
    var vb = VertexBuffer()
    var v = _viewport(100, 100)
    emit_rect(
        vb,
        rect_command(v.base_matrix(), _plain(), 0.0, 0.0, 4.0, 4.0),
        v.scale,
    )
    var cap = vb.data.capacity()
    vb.clear()
    assert_equal(vb.count(), 0)
    assert_equal(vb.data.capacity(), cap)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
