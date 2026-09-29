from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)

from create.math.bezier import CubicBezier
from create.math.matrix import identity, scale
from create.math.point2d import Point2D
from create.render.style import Style
from create.render._command import bezier_command
from create.render._curve import (
    MITER_LIMIT,
    bezier_device_points,
    stroke_quads,
)


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _s_curve() -> CubicBezier:
    return CubicBezier((0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0))


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
    var b = CubicBezier((5.0, 5.0), (5.0, 5.0), (5.0, 5.0), (5.0, 5.0))
    var c = bezier_command(identity[3](), Style(), b)
    assert_equal(
        len(stroke_quads(bezier_device_points(c, c.transform), 3.0)), 0
    )


def test_zero_width_gives_no_quads() raises -> None:
    var points: List[Point2D] = [(0.0, 0.0), (10.0, 0.0)]
    assert_equal(len(stroke_quads(points, 0.0)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
