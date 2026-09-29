from std.math import pi, sqrt, tau
from std.testing import TestSuite, assert_equal, assert_true

from create.math.geometry import Line, Sector
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
from create.render._command import CMD_SECTOR, sector_command
from create.render._raster import fill_quad
from create.render._sector import SectorQuads, sector_quads
from create.render._transform import outline_thickness_px, pixel_scale

comptime _SIZE = 64
comptime _INK = Color(255, 255, 255, 128)


def _sectors() -> List[Sector]:
    """Below, at and above a half turn, clockwise, and a full turn."""
    return [
        Sector((0.0, 0.0), 24.0, 0.3, 1.1),
        Sector((0.0, 0.0), 24.0, -0.5, pi),
        Sector((0.0, 0.0), 24.0, 0.2, 1.3 * pi),
        Sector((0.0, 0.0), 24.0, 2.0, -1.8 * pi),
        Sector((0.0, 0.0), 24.0, 0.0, tau),
    ]


def _device(m: Matrix[3, 3]) -> Matrix[3, 3]:
    """`m` moved to the middle of the test surface."""
    return translate(Float64(_SIZE) / 2.0, Float64(_SIZE) / 2.0) @ m


def _quads(
    s: Sector, m: Matrix[3, 3], style: Style = Style(), grow: Float64 = 0.0
) -> SectorQuads:
    var c = sector_command(
        m,
        style,
        s.position.x,
        s.position.y,
        s.r,
        s.start_angle,
        s.sweep_angle,
    )
    c.geom[5] = grow
    return sector_quads(c, c.transform, 1.0)


def _paint(mut surface: MemorySurface, corners: List[Point2D]):
    for i in range(0, len(corners), 4):
        var qx = Array[Float64, 4](fill=0.0)
        var qy = Array[Float64, 4](fill=0.0)
        for k in range(4):
            qx[k] = corners[i + k].x
            qy[k] = corners[i + k].y
        fill_quad(surface.surface(), qx, qy, _INK)


def _painted(q: SectorQuads) -> MemorySurface:
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


def _signed_distance(s: Sector, p: Point2D) -> Float64:
    """How far `p` lies inside the sector's edge; negative outside."""
    if not s.contains(p):
        return -p.dist(s.closest_point(p))
    var d = s.r - p.dist(s.position)
    if abs(s.sweep_angle) < tau:
        for radius in s._radii():
            d = min(d, p.dist(radius.closest_point(p)))
    return d


def _assert_tiles(
    s: Sector, m: Matrix[3, 3], style: Style = Style(), grow: Float64 = 0.0
) raises:
    """Quads convex, painted at most once, and covering the sector grown by
    `grow`: each pixel centre more than a pixel from an edge is painted
    exactly when it lies no further than `grow` outside the sector, and
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


def _outlined(thickness: Int) -> Style:
    return Style(fill=Color.RED, outline_thickness=thickness)


def test_sector_command_records_its_geometry() raises -> None:
    var c = sector_command(identity[3](), Style(), 1.0, 2.0, 3.0, 0.5, -1.0)
    assert_equal(c.kind, CMD_SECTOR)
    assert_equal(c.geom[0], 1.0)
    assert_equal(c.geom[1], 2.0)
    assert_equal(c.geom[2], 3.0)
    assert_equal(c.geom[3], 0.5)
    assert_equal(c.geom[4], -1.0)


def test_fill_only_tiles_the_sector() raises -> None:
    var style = Style(fill=Color.RED, outline_enabled=False)
    for s in _sectors():
        var q = _quads(s, identity[3](), style)
        assert_equal(len(q.outline), 0)
        _assert_tiles(s, identity[3](), style)


def test_fill_and_outline_tile_the_sector_once() raises -> None:
    for s in _sectors():
        _assert_tiles(s, identity[3](), _outlined(3))
        _assert_tiles(s, identity[3](), _outlined(9))


def test_outline_is_as_thick_as_asked() raises -> None:
    # A quarter sector with a 5-unit outline: the fill starts 5 in from
    # both straight edges and stops 5 short of the arc.
    var s = Sector((0.0, 0.0), 24.0, 0.0, pi / 2.0)
    var q = _quads(s, identity[3](), _outlined(5))
    var lo = Float64.MAX
    var hi = 0.0
    for p in q.fill:
        lo = min(lo, min(p.x, p.y))
        hi = max(hi, p.dist(Point2D(0.0, 0.0)))
    assert_true(abs(lo - 5.0) < 1e-9)
    assert_true(abs(hi - 19.0) < 1e-9)


def test_transformed_sectors_tile_once() raises -> None:
    for s in _sectors():
        _assert_tiles(s, rotate(0.7) @ scale(1.2), _outlined(3))
        _assert_tiles(s, scale(1.3, 0.6), _outlined(3))


def test_non_uniform_scale_gives_an_elliptical_sector() raises -> None:
    var s = Sector((0.0, 0.0), 24.0, 0.0, tau)
    var q = _quads(s, scale(1.5, 0.5), _outlined(2))
    var wide = 0.0
    var tall = 0.0
    for p in q.outline:
        wide = max(wide, abs(p.x))
        tall = max(tall, abs(p.y))
    assert_true(abs(wide - 36.0) < 1e-9)
    assert_true(abs(tall - 12.0) < 1e-9)


def test_outline_wider_than_the_radius_leaves_one_colour() raises -> None:
    # Fill visible: the fill wins the whole sector, as a circle's does.
    var s = Sector((0.0, 0.0), 10.0, 0.0, 2.0)
    var q = _quads(s, identity[3](), _outlined(10))
    assert_true(len(q.fill) > 0)
    assert_equal(len(q.outline), 0)
    _assert_tiles(s, identity[3](), _outlined(10))
    # Fill off: the outline does.
    var style = _outlined(10)
    style.fill_enabled = False
    q = _quads(s, identity[3](), style)
    assert_equal(len(q.fill), 0)
    assert_true(len(q.outline) > 0)
    _assert_tiles(s, identity[3](), style)


def test_grown_sectors_tile_their_minkowski_sum() raises -> None:
    # Round the tip and the arc's ends into the missing wedge, with the
    # outline an inset band of the grown shape.
    for s in _sectors():
        _assert_tiles(s, identity[3](), _outlined(3), 4.0)
        _assert_tiles(s, rotate(0.7) @ scale(1.1), _outlined(3), 3.0)


def test_shrunk_sectors_tile_their_erosion() raises -> None:
    for s in _sectors():
        _assert_tiles(s, identity[3](), _outlined(3), -4.0)


def test_a_grown_outline_only_sector_is_a_ring() raises -> None:
    # A shadow's ring: the outline band of the grown sector, fill switched
    # off, still tiles once with the hole in the right place.
    var style = _outlined(10)
    style.fill_enabled = False
    for s in _sectors():
        _assert_tiles(s, identity[3](), style, 3.0)


def test_shrunk_to_nothing_gives_no_quads() raises -> None:
    var q = _quads(
        Sector((0.0, 0.0), 10.0, 0.0, 1.0), identity[3](), grow=-10.0
    )
    assert_equal(len(q.fill), 0)
    assert_equal(len(q.outline), 0)


def test_degenerate_sectors_give_no_quads() raises -> None:
    for s in [
        Sector((0.0, 0.0), 0.0, 0.0, 1.0),
        Sector((0.0, 0.0), 10.0, 1.0, 0.0),
    ]:
        var q = _quads(s, identity[3](), _outlined(2))
        assert_equal(len(q.fill), 0)
        assert_equal(len(q.outline), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
