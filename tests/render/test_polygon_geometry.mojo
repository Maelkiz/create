from std.math import pi, sqrt
from std.testing import TestSuite, assert_equal, assert_true

from create.math.geometry import Polygon
from create.math.matrix import (
    Matrix,
    apply as mat_apply,
    identity,
    inverse,
    rotate,
    scale,
    translate,
)
from create.math.point2d import Point2D
from create.render.color import Color
from create.render.style import Style
from create.render.surface import MemorySurface
from create.render._command import CMD_POLYGON, polygon_command
from create.render._polygon import PolygonQuads, polygon_quads
from create.render._raster import fill_quad
from create.render._transform import outline_thickness_px, pixel_scale

comptime _SIZE = 64
comptime _INK = Color(255, 255, 255, 128)


def _l_shape() -> Polygon:
    return Polygon(
        (-20.0, -20.0),
        (20.0, -20.0),
        (20.0, -4.0),
        (-4.0, -4.0),
        (-4.0, 20.0),
        (-20.0, 20.0),
    )


def _pentagram() -> Polygon:
    """Five self-crossing vertices: the centre is wound twice."""
    var points = List[Point2D]()
    var p = Polygon.regular((0.0, 0.0), 26.0, 5)
    for i in range(5):
        points.append(p.vertices[(2 * i) % 5])
    return Polygon(points^)


def _polygons() -> List[Polygon]:
    """Convex, clockwise, concave, a star and a self-crossing one."""
    return [
        Polygon.regular((0.0, 0.0), 24.0, 6),
        Polygon((-18.0, 12.0), (18.0, 12.0), (18.0, -12.0), (-18.0, -12.0)),
        _l_shape(),
        Polygon.star((0.0, 0.0), 26.0, 11.0, 5),
        _pentagram(),
    ]


def _device(m: Matrix[3, 3]) -> Matrix[3, 3]:
    """`m` moved to the middle of the test surface."""
    return translate(Float64(_SIZE) / 2.0, Float64(_SIZE) / 2.0) @ m


def _quads(
    p: Polygon, m: Matrix[3, 3], style: Style = Style(), grow: Float64 = 0.0
) -> PolygonQuads:
    var c = polygon_command(m, style, p.vertices.copy())
    c.geom[0] = grow
    return polygon_quads(c, c.transform, 1.0)


def _paint(mut surface: MemorySurface, corners: List[Point2D]):
    for i in range(0, len(corners), 4):
        var qx = Array[Float64, 4](fill=0.0)
        var qy = Array[Float64, 4](fill=0.0)
        for k in range(4):
            qx[k] = corners[i + k].x
            qy[k] = corners[i + k].y
        fill_quad(surface.surface(), qx, qy, _INK)


def _painted(q: PolygonQuads) -> MemorySurface:
    """Every quad painted translucent once: a pixel two quads share comes
    out brighter than one only one of them covers."""
    var surface = MemorySurface(_SIZE, _SIZE)
    _paint(surface, q.fill)
    _paint(surface, q.outline)
    return surface^


def _once() -> Color:
    var surface = MemorySurface(1, 1)
    var corners: List[Point2D] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
    ]
    _paint(surface, corners)
    return surface.pixel(0, 0)


def _signed_distance(s: Polygon, p: Point2D) -> Float64:
    """How far `p` lies inside the polygon's edge; negative outside."""
    var d = Float64.MAX
    for i in range(len(s.vertices)):
        d = min(d, p.dist(s._edge(i).closest_point(p)))
    return d if s.contains(p) else -d


def _area(corners: List[Point2D]) -> Float64:
    var total = 0.0
    for i in range(0, len(corners), 4):
        for k in range(4):
            var a = corners[i + k]
            var b = corners[i + (k + 1) % 4]
            total += a.x * b.y - b.x * a.y
    return total / 2.0


def _convex(corners: List[Point2D], i: Int) -> Bool:
    """Whether the quad at `i` turns one way only, repeated corners aside."""
    var positive = False
    var negative = False
    for k in range(4):
        var a = corners[i + k]
        var b = corners[i + (k + 1) % 4]
        var c = corners[i + (k + 2) % 4]
        var cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        if cross > 1e-9:
            positive = True
        elif cross < -1e-9:
            negative = True
    return not (positive and negative)


def _assert_tiles(
    s: Polygon, m: Matrix[3, 3], style: Style = Style(), grow: Float64 = 0.0
) raises:
    """Quads convex, painted at most once, and covering the polygon grown
    by `grow`: each pixel centre more than a pixel from an edge is painted
    exactly when it lies no further than `grow` outside the polygon, and
    painted in the fill exactly when it lies the outline's width further in.
    """
    var device = _device(m)
    var q = _quads(s, device, style, grow)
    for corners in [q.fill.copy(), q.outline.copy()]:
        for i in range(0, len(corners), 4):
            assert_true(_convex(corners, i))
    var surface = _painted(q)
    var fill = MemorySurface(_SIZE, _SIZE)
    _paint(fill, q.fill)
    var once = _once()
    var back = inverse(device)
    var pixel_units = 1.0 / sqrt(abs(m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0]))
    var near = 1.5 * pixel_units
    var t = 0.0
    if style._outline_visible() and len(q.fill) > 0 and len(q.outline) > 0:
        t = Float64(outline_thickness_px(style, device, 1.0)) / pixel_scale(
            device, 1.0
        )
    for y in range(_SIZE):
        for x in range(_SIZE):
            var color = surface.pixel(x, y)
            assert_true(color.a == 0 or color == once)
            var p = Point2D(mat_apply(back, Float64(x) + 0.5, Float64(y) + 0.5))
            var d = _signed_distance(s, p)
            if abs(d + grow) > near:
                assert_equal(color.a != 0, d >= -grow)
            if t > 0.0 and abs(d + grow - t) > near:
                assert_equal(fill.pixel(x, y).a != 0, d >= t - grow)


def _outlined(thickness: Int) -> Style:
    return Style(fill=Color.RED, outline_thickness=thickness)


def test_polygon_command_records_its_vertices() raises -> None:
    var p = _l_shape()
    var c = polygon_command(identity[3](), Style(), p.vertices.copy())
    assert_equal(c.kind, CMD_POLYGON)
    assert_equal(len(c.points), 6)
    assert_true(c.points[3] == Point2D(-4.0, -4.0))
    assert_equal(c.geom[0], 0.0)


def test_fill_only_tiles_the_polygon() raises -> None:
    var style = Style(fill=Color.RED, outline_enabled=False)
    for p in _polygons():
        var q = _quads(p, identity[3](), style)
        assert_equal(len(q.outline), 0)
        _assert_tiles(p, identity[3](), style)


def test_fill_and_outline_tile_the_polygon_once() raises -> None:
    for p in _polygons():
        _assert_tiles(p, identity[3](), _outlined(3))
        _assert_tiles(p, identity[3](), _outlined(6))


def test_quads_cover_the_area_exactly() raises -> None:
    # Fill and outline together cover a simple polygon's area, no more.
    for p in [_polygons()[0].copy(), _polygons()[1].copy(), _l_shape()]:
        var q = _quads(p, identity[3](), _outlined(3))
        assert_true(abs(_area(q.fill) + _area(q.outline) - p.area()) < 1e-6)


def test_the_pentagram_fills_its_centre() raises -> None:
    # Nonzero: the doubly wound pentagon counts, once.
    var p = _pentagram()
    var q = _quads(
        p, identity[3](), Style(fill=Color.RED, outline_enabled=False)
    )
    var star = Polygon.star((0.0, 0.0), 26.0, 26.0 * 0.381966, 5)
    assert_true(abs(_area(q.fill) - star.area()) < 1e-3)


def test_the_l_shape_leaves_its_notch_empty() raises -> None:
    var q = _quads(_l_shape(), identity[3](), _outlined(2))
    for corners in [q.fill.copy(), q.outline.copy()]:
        for c in corners:
            assert_true(not (c.x > -4.0 + 1e-9 and c.y > -4.0 + 1e-9))


def test_square_outline_is_as_thick_as_asked() raises -> None:
    # A 40-wide square with a 5-unit outline: a 30-wide fill.
    var p = Polygon((-20.0, -20.0), (20.0, -20.0), (20.0, 20.0), (-20.0, 20.0))
    var q = _quads(p, identity[3](), _outlined(5))
    assert_true(abs(_area(q.fill) - 900.0) < 1e-6)
    assert_true(abs(_area(q.outline) - 700.0) < 1e-6)


def test_transformed_polygons_tile_once() raises -> None:
    for p in _polygons():
        _assert_tiles(p, rotate(0.7) @ scale(1.2), _outlined(3))
        _assert_tiles(p, scale(1.3, 0.6), _outlined(3))


def test_outline_wider_than_the_polygon_leaves_one_colour() raises -> None:
    var p = Polygon.regular((0.0, 0.0), 10.0, 6)
    var q = _quads(p, identity[3](), _outlined(12))
    assert_true(len(q.fill) > 0)
    assert_equal(len(q.outline), 0)
    _assert_tiles(p, identity[3](), _outlined(12))
    var style = _outlined(12)
    style.fill_enabled = False
    q = _quads(p, identity[3](), style)
    assert_equal(len(q.fill), 0)
    assert_true(len(q.outline) > 0)
    _assert_tiles(p, identity[3](), style)


def test_grown_square_is_rounded() raises -> None:
    # w² + 4wd + πd², less what the discs' 12 segments cut off the corners.
    var p = Polygon((-10.0, -10.0), (10.0, -10.0), (10.0, 10.0), (-10.0, 10.0))
    var q = _quads(
        p, identity[3](), Style(fill=Color.RED, outline_enabled=False), 4.0
    )
    var expected = 400.0 + 4.0 * 20.0 * 4.0 + pi * 16.0
    var area = _area(q.fill)
    assert_true(area < expected)
    assert_true(area > expected - 3.0)


def test_grown_polygons_tile_their_minkowski_sum() raises -> None:
    for p in _polygons():
        _assert_tiles(p, identity[3](), _outlined(3), 4.0)
        _assert_tiles(p, rotate(0.7) @ scale(1.1), _outlined(3), 3.0)


def test_shrunk_polygons_tile_their_erosion() raises -> None:
    for p in _polygons():
        _assert_tiles(p, identity[3](), _outlined(3), -3.0)


def test_a_grown_outline_only_polygon_is_a_ring() raises -> None:
    var style = _outlined(6)
    style.fill_enabled = False
    for p in _polygons():
        _assert_tiles(p, identity[3](), style, 3.0)


def test_degenerate_polygons_give_no_quads() raises -> None:
    for p in [
        Polygon((0.0, 0.0), (10.0, 0.0)),
        Polygon((0.0, 0.0), (10.0, 0.0), (20.0, 0.0)),
        Polygon(List[Point2D]()),
    ]:
        var q = _quads(p, identity[3](), _outlined(2))
        assert_equal(len(q.fill), 0)
        assert_equal(len(q.outline), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
