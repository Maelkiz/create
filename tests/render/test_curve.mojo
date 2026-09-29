from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)

from create.math.bezier import Bezier
from create.math.matrix import identity, scale, translate
from create.math.point2d import Point2D
from create.render.color import Color
from create.render.style import Style
from create.render.surface import MemorySurface
from create.render._blur import blur_reach
from create.render._command import bezier_chain_command, bezier_command
from create.render._curve import (
    MITER_LIMIT,
    bezier_device_points,
    bezier_shadow_mask,
    stroke_quads,
)
from create.render._raster import fill_quad


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _s_curve() -> Bezier:
    return Bezier((0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0))


def test_device_points_follow_the_transform() raises -> None:
    var b = _s_curve()
    var c = bezier_command(scale(2.0, 2.0), Style(), b)
    var points = bezier_device_points(c, c.transform)
    _assert_point_near(points[0], Point2D(0.0, 0.0))
    _assert_point_near(points[len(points) - 1], Point2D(200.0, 0.0))


def test_device_points_refine_with_zoom() raises -> None:
    # The same curve drawn larger is flattened into more segments.
    var c = bezier_command(identity[3](), Style(), _s_curve())
    var near = bezier_device_points(c, c.transform)
    var far = bezier_device_points(c, scale(8.0, 8.0))
    assert_true(len(far) > len(near))


def _two_curve_chain() -> List[Point2D]:
    # An S-curve and a second curve leaving its end smoothly.
    return [
        (0.0, 0.0),
        (100.0, 100.0),
        (0.0, 100.0),
        (100.0, 0.0),
        (200.0, -100.0),
        (250.0, 50.0),
        (300.0, 0.0),
    ]


def test_chain_flattens_to_one_polyline() raises -> None:
    var chain = _two_curve_chain()
    var c = bezier_chain_command(identity[3](), Style(), chain.copy())
    var points = bezier_device_points(c, c.transform)
    var first = Bezier(chain[0], chain[1], chain[2], chain[3]).flatten(0.25)
    var second = Bezier(chain[3], chain[4], chain[5], chain[6]).flatten(0.25)
    # The joint appears once.
    assert_equal(len(points), len(first) + len(second) - 1)
    _assert_point_near(points[0], chain[0])
    _assert_point_near(points[len(first) - 1], chain[3])
    _assert_point_near(points[len(points) - 1], chain[6])
    for i in range(1, len(points)):
        assert_true(points[i] != points[i - 1])


def test_chain_stroke_shares_edges_across_the_joint() raises -> None:
    var c = bezier_chain_command(identity[3](), Style(), _two_curve_chain())
    var corners = stroke_quads(bezier_device_points(c, c.transform), 6.0)
    for q in range(len(corners) // 4 - 1):
        assert_equal(corners[4 * q + 1], corners[4 * (q + 1)])
        assert_equal(corners[4 * q + 2], corners[4 * (q + 1) + 3])


def test_closed_polyline_strokes_as_a_ring() raises -> None:
    var points: List[Point2D] = [
        (0.0, 0.0),
        (10.0, 0.0),
        (10.0, 10.0),
        (0.0, 10.0),
        (0.0, 0.0),
    ]
    var corners = stroke_quads(points, 2.0)
    # Four sides, the last closing back to the start.
    assert_equal(len(corners), 16)
    for q in range(4):
        var next = (q + 1) % 4
        assert_equal(corners[4 * q + 1], corners[4 * next])
        assert_equal(corners[4 * q + 2], corners[4 * next + 3])
    # The start is mitred like any corner, not butt.
    _assert_point_near(corners[0], Point2D(1.0, 1.0))
    _assert_point_near(corners[3], Point2D(-1.0, -1.0))


def test_there_and_back_is_not_a_ring() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0), (0.0, 0.0)]
    assert_equal(len(stroke_quads(points, 2.0)), 8)


def test_straight_polyline_gives_a_straight_band() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0)]
    var corners = stroke_quads(points, 4.0)
    assert_equal(len(corners), 8)
    # Left edge at +2, right at -2: exactly a line's band.
    _assert_point_near(corners[0], Point2D(0.0, 2.0))
    _assert_point_near(corners[1], Point2D(10.0, 2.0))
    _assert_point_near(corners[2], Point2D(10.0, -2.0))
    _assert_point_near(corners[3], Point2D(0.0, -2.0))
    _assert_point_near(corners[5], Point2D(20.0, 2.0))
    _assert_point_near(corners[6], Point2D(20.0, -2.0))


def test_neighbouring_quads_share_their_joining_edge() raises -> None:
    var c = bezier_command(identity[3](), Style(), _s_curve())
    var corners = stroke_quads(bezier_device_points(c, c.transform), 6.0)
    var quads = len(corners) // 4
    assert_true(quads > 2)
    for q in range(quads - 1):
        # This quad's far edge is the next one's near edge, exactly.
        assert_equal(corners[4 * q + 1], corners[4 * (q + 1)])
        assert_equal(corners[4 * q + 2], corners[4 * (q + 1) + 3])


def test_miter_keeps_both_edges_at_half_width() raises -> None:
    # A right-angle corner: the mitred corner is sqrt(2) half-widths out.
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]
    var corners = stroke_quads(points, 2.0)
    _assert_point_near(corners[1], Point2D(9.0, 1.0))
    _assert_point_near(corners[2], Point2D(11.0, -1.0))


def test_miter_is_clamped_at_a_sharp_turn() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0), (0.0, 0.1)]
    var corners = stroke_quads(points, 2.0)
    var reach = (corners[1] - Point2D(10.0, 0.0)).mag()
    assert_almost_equal(reach, MITER_LIMIT, atol=1e-9)


def test_repeated_points_are_skipped() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (0.0, 0.0), (10.0, 0.0)]
    assert_equal(len(stroke_quads(points, 2.0)), 4)


def test_zero_length_gives_no_quads() raises -> None:
    var b = Bezier((5.0, 5.0), (5.0, 5.0), (5.0, 5.0), (5.0, 5.0))
    var c = bezier_command(identity[3](), Style(), b)
    assert_equal(
        len(stroke_quads(bezier_device_points(c, c.transform), 3.0)), 0
    )


def test_zero_width_gives_no_quads() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0)]
    assert_equal(len(stroke_quads(points, 0.0)), 0)


def _stroked(thickness: Int) -> Style:
    var s = Style()
    s.outline_thickness = thickness
    return s^


def _mass(pixels: List[UInt8]) -> Int:
    var total = 0
    for p in pixels:
        total += Int(p)
    return total


def test_an_unblurred_mask_is_the_stroke_itself() raises -> None:
    # Moved in from the edges, so the whole stroke lands on the surface.
    var c = bezier_command(translate(10.0, 10.0), _stroked(5), _s_curve())
    var placed = bezier_shadow_mask(c, c.transform, 1.0, 0)
    assert_equal(placed.mask.pad, 0)
    # The same quads filled straight onto a device-sized surface.
    var device = MemorySurface(120, 120)
    var s = device.surface()
    var corners = stroke_quads(bezier_device_points(c, c.transform), 5.0)
    for q in range(0, len(corners), 4):
        var qx: Array[Float64, 4] = [
            corners[q].x,
            corners[q + 1].x,
            corners[q + 2].x,
            corners[q + 3].x,
        ]
        var qy: Array[Float64, 4] = [
            corners[q].y,
            corners[q + 1].y,
            corners[q + 2].y,
            corners[q + 3].y,
        ]
        fill_quad(s, qx, qy, Color.WHITE)
    var inked = 0
    for y in range(120):
        for x in range(120):
            var mx = x - placed.x
            var my = y - placed.y
            var covered = UInt8(0)
            if (
                mx >= 0
                and my >= 0
                and mx < placed.mask.width
                and my < placed.mask.height
            ):
                covered = placed.mask.pixels[my * placed.mask.width + mx]
            assert_equal(covered, device.pixel(x, y).a)
            if covered > 0:
                inked += 1
    assert_equal(_mass(placed.mask.pixels), inked * 255)


def test_a_blurred_mask_grows_by_the_reach_and_keeps_its_mass() raises -> None:
    var c = bezier_command(identity[3](), _stroked(5), _s_curve())
    var hard = bezier_shadow_mask(c, c.transform, 1.0, 0)
    var soft = bezier_shadow_mask(c, c.transform, 1.0, 8)
    var pad = blur_reach(4.0)
    assert_equal(soft.mask.pad, pad)
    assert_equal(soft.x, hard.x - pad)
    assert_equal(soft.y, hard.y - pad)
    assert_equal(soft.mask.width, hard.mask.width + 2 * pad)
    var before = Float64(_mass(hard.mask.pixels))
    var after = Float64(_mass(soft.mask.pixels))
    assert_true(abs(after - before) / before < 0.02)


def test_an_invisible_stroke_gives_an_empty_mask() raises -> None:
    var s = _stroked(5)
    s.outline_enabled = False
    var c = bezier_command(identity[3](), s, _s_curve())
    var placed = bezier_shadow_mask(c, c.transform, 1.0, 8)
    assert_equal(placed.mask.width, 0)
    assert_equal(len(placed.mask.pixels), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
