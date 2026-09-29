from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import cos, pi, sin, tau
from create.math.geometry import (
    overlaps,
    Arc,
    Circle,
    Line,
    Polygon,
    Rectangle,
    Sector,
    Triangle,
)
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def _square() -> Polygon:
    return Polygon((0, 0), (10, 0), (10, 10), (0, 10))


def _l_shape() -> Polygon:
    """A 10 by 10 square missing its top-right quarter: concave, with the
    notch at (7.5, 7.5)."""
    return Polygon((0, 0), (10, 0), (10, 5), (5, 5), (5, 10), (0, 10))


def _pentagram() -> Polygon:
    """Five points on a circle joined every second one: the edges cross,
    and the inner pentagon is wound twice."""
    var vertices = List[Point2D]()
    for i in range(5):
        var angle = tau / 4.0 + 2.0 * tau * Float64(i) / 5.0
        vertices.append(Point2D(10.0 * cos(angle), 10.0 * sin(angle)))
    return Polygon(vertices^)


def test_variadic_and_list_constructors_agree() raises -> None:
    var from_list = Polygon([Point2D(0, 0), Point2D(10, 0), Point2D(5, 8)])
    assert_true(Polygon((0, 0), (10, 0), (5, 8)) == from_list)
    assert_true(Polygon((0, 0), (10, 0), (5, 9)) != from_list)


def test_prints_in_keyword_form() raises -> None:
    assert_equal(
        String(Polygon((1, 2), (3.5, 4))),
        "Polygon(vertices=[Point2D(1.0, 2.0), Point2D(3.5, 4.0)])",
    )


def test_regular_starts_straight_up() raises -> None:
    var p = Polygon.regular((0, 0), 10, 6)
    assert_equal(len(p.vertices), 6)
    _assert_point_near(p.vertices[0], Point2D(0.0, 10.0))
    for v in p.vertices:
        assert_almost_equal((v - Point2D(0, 0)).mag(), 10.0)
    # Counter-clockwise: the second vertex is up and to the left.
    assert_true(p.vertices[1].x < 0.0 and p.vertices[1].y > 0.0)


def test_regular_start_angle_and_position() raises -> None:
    var p = Polygon.regular((5, -3), 2, 4, start_angle=0.0)
    _assert_point_near(p.vertices[0], Point2D(7.0, -3.0))
    _assert_point_near(p.vertices[1], Point2D(5.0, -1.0))
    _assert_point_near(p.center(), Point2D(5.0, -3.0))


def test_star_alternates_radii() raises -> None:
    var s = Polygon.star((0, 0), 10, 4, 5)
    assert_equal(len(s.vertices), 10)
    _assert_point_near(s.vertices[0], Point2D(0.0, 10.0))
    for i in range(10):
        var expected = 10.0 if i % 2 == 0 else 4.0
        assert_almost_equal((s.vertices[i] - Point2D(0, 0)).mag(), expected)
    # The first inner vertex sits halfway to the second tip.
    var angle = tau / 4.0 + pi / 5.0
    _assert_point_near(
        s.vertices[1], Point2D(4.0 * cos(angle), 4.0 * sin(angle))
    )


def test_area_and_center_of_a_square() raises -> None:
    assert_almost_equal(_square().area(), 100.0)
    _assert_point_near(_square().center(), Point2D(5.0, 5.0))


def test_area_and_center_of_a_concave_polygon() raises -> None:
    var l = _l_shape()
    assert_almost_equal(l.area(), 75.0)
    # Three 5 by 5 squares at (2.5, 2.5), (7.5, 2.5), (2.5, 7.5).
    _assert_point_near(l.center(), Point2D(12.5 / 3.0, 12.5 / 3.0))


def test_winding_does_not_change_area() raises -> None:
    var clockwise = Polygon((0, 0), (0, 10), (10, 10), (10, 0))
    assert_almost_equal(clockwise.area(), 100.0)
    _assert_point_near(clockwise.center(), Point2D(5.0, 5.0))


def test_star_center_is_its_position() raises -> None:
    _assert_point_near(
        Polygon.star((3, 4), 10, 4, 5).center(), Point2D(3.0, 4.0), 1e-9
    )


def test_degenerate_center_is_the_vertex_mean() raises -> None:
    _assert_point_near(Polygon((0, 0), (4, 0), (8, 0)).center(), (4.0, 0.0))
    _assert_point_near(Polygon().center(), Point2D(0.0, 0.0))
    assert_almost_equal(Polygon((0, 0), (4, 0)).area(), 0.0)


def test_bounds() raises -> None:
    var b = Polygon((-1, 2), (4, -3), (0, 6)).bounds()
    assert_equal(b, Rectangle((1.5, 1.5), 5.0, 9.0))
    assert_equal(Polygon().bounds(), Rectangle((0, 0), 0.0, 0.0))


def test_contains_convex() raises -> None:
    var sq = _square()
    assert_true(sq.contains(Point2D(5, 5)))
    assert_true(not sq.contains(Point2D(11, 5)))
    assert_true(not sq.contains(Point2D(-1, 5)))


def test_contains_the_boundary() raises -> None:
    var sq = _square()
    assert_true(sq.contains(Point2D(10, 5)))
    assert_true(sq.contains(Point2D(5, 0)))
    assert_true(sq.contains(Point2D(10, 10)))
    assert_true(sq.contains(Point2D(0, 0)))


def test_contains_concave() raises -> None:
    var l = _l_shape()
    assert_true(l.contains(Point2D(2.5, 7.5)))
    assert_true(l.contains(Point2D(7.5, 2.5)))
    assert_true(not l.contains(Point2D(7.5, 7.5)))
    # The reflex corner itself is on the boundary.
    assert_true(l.contains(Point2D(5, 5)))


def test_contains_is_nonzero_through_a_pentagram() raises -> None:
    var star = _pentagram()
    # The inner pentagon is wound twice: still inside under nonzero.
    assert_true(star.contains(Point2D(0, 0)))
    # A tip is wound once.
    assert_true(star.contains(Point2D(0, 8)))
    # Between two tips, outside.
    assert_true(not star.contains(Point2D(0, -9)))


def test_contains_ignores_winding() raises -> None:
    var clockwise = Polygon((0, 0), (0, 10), (10, 10), (10, 0))
    assert_true(clockwise.contains(Point2D(5, 5)))
    assert_true(not clockwise.contains(Point2D(15, 5)))


def test_contains_horizontal_ray_through_a_vertex() raises -> None:
    # The ray to the right of (0, 5) passes exactly through the vertex
    # (5, 5) -- counted once, not twice.
    var diamond = Polygon((5, 0), (10, 5), (5, 10), (0, 5))
    assert_true(diamond.contains(Point2D(1, 5)))
    assert_true(not diamond.contains(Point2D(-1, 5)))


def test_degenerate_polygon_is_its_edges() raises -> None:
    var segment = Polygon((0, 0), (10, 0))
    assert_true(segment.contains(Point2D(5, 0)))
    assert_true(not segment.contains(Point2D(5, 1)))
    var point = Polygon((2, 3))
    assert_true(point.contains(Point2D(2, 3)))
    assert_true(not point.contains(Point2D(2, 4)))
    assert_true(not Polygon().contains(Point2D(0, 0)))


def test_closest_point() raises -> None:
    var l = _l_shape()
    _assert_point_near(l.closest_point(Point2D(2, 2)), Point2D(2.0, 2.0))
    _assert_point_near(l.closest_point(Point2D(8, 7)), Point2D(8.0, 5.0))
    _assert_point_near(l.closest_point(Point2D(-3, 4)), Point2D(0.0, 4.0))


def test_move_to_moves_the_centroid() raises -> None:
    var l = _l_shape()
    l.move_to(Point2D(0, 0))
    _assert_point_near(l.center(), Point2D(0.0, 0.0))
    _assert_point_near(l.vertices[0], Point2D(-12.5 / 3.0, -12.5 / 3.0))


def test_translate() raises -> None:
    var sq = _square()
    sq.translate(Vector2D(1, -2))
    assert_equal(sq.vertices[0], Point2D(1.0, -2.0))
    assert_equal(sq.vertices[2], Point2D(11.0, 8.0))


def test_overlaps_circle() raises -> None:
    var l = _l_shape()
    # Sitting in the notch, clear of both arms.
    var in_notch = Circle((8, 8), 1.5)
    assert_true(not overlaps(l, in_notch))
    assert_true(not overlaps(in_notch, l))
    # Tangent to both edges of the notch.
    var touching = Circle((8, 8), 3)
    assert_true(overlaps(l, touching) and overlaps(touching, l))
    # Polygon wholly inside a circle, and a circle wholly inside the arm.
    var around = Circle((5, 5), 20)
    assert_true(overlaps(l, around) and overlaps(around, l))
    var inside = Circle((2.5, 2.5), 1)
    assert_true(overlaps(l, inside) and overlaps(inside, l))


def test_overlaps_rectangle() raises -> None:
    var l = _l_shape()
    var in_notch = Rectangle((8, 8), 3, 3)
    assert_true(not overlaps(l, in_notch) and not overlaps(in_notch, l))
    # Sharing the notch's edge counts.
    var on_edge = Rectangle((7.5, 6), 5, 2)
    assert_true(overlaps(l, on_edge) and overlaps(on_edge, l))
    var around = Rectangle((5, 5), 30, 30)
    assert_true(overlaps(l, around) and overlaps(around, l))
    var inside = Rectangle((2, 2), 1, 1)
    assert_true(overlaps(l, inside) and overlaps(inside, l))
    var far = Rectangle((30, 0), 2, 2)
    assert_true(not overlaps(l, far) and not overlaps(far, l))


def test_overlaps_triangle() raises -> None:
    var l = _l_shape()
    var in_notch = Triangle((6, 6), (9, 6), (6, 9))
    assert_true(not overlaps(l, in_notch) and not overlaps(in_notch, l))
    # Bridging the notch from arm to arm, all vertices outside the L.
    var bridging = Triangle((7, 12), (12, 7), (12, 12))
    assert_true(not overlaps(l, bridging))
    var crossing = Triangle((2, 12), (12, 2), (12, 12))
    assert_true(overlaps(l, crossing) and overlaps(crossing, l))
    var around = Triangle((-20, -20), (40, -20), (5, 40))
    assert_true(overlaps(l, around) and overlaps(around, l))


def test_overlaps_sector() raises -> None:
    var l = _l_shape()
    # The notch holds a quarter disc pointing into its corner.
    var in_notch = Sector((9, 9), 3, pi, pi / 2.0)
    assert_true(not overlaps(l, in_notch) and not overlaps(in_notch, l))
    # The tip inside the polygon.
    var tip_inside = Sector((2, 2), 50, 0.0, 0.1)
    assert_true(overlaps(l, tip_inside) and overlaps(tip_inside, l))
    # Reaching in from outside, the tip clear of the polygon.
    var arc_reaches = Sector((20, 2), 11, pi - 0.2, 0.4)
    assert_true(overlaps(l, arc_reaches) and overlaps(arc_reaches, l))
    # The polygon wholly inside the sector.
    var around = Sector((-5, -5), 40, 0.0, pi / 2.0)
    assert_true(overlaps(l, around) and overlaps(around, l))


def test_overlaps_polygon() raises -> None:
    var l = _l_shape()
    var in_notch = Polygon.regular((8, 8), 1.5, 5)
    assert_true(not overlaps(l, in_notch) and not overlaps(in_notch, l))
    var small = Polygon.regular((2, 2), 1, 6)
    assert_true(overlaps(l, small) and overlaps(small, l))
    var big = Polygon.regular((5, 5), 30, 3)
    assert_true(overlaps(l, big) and overlaps(big, l))
    assert_true(overlaps(l, l))
    assert_true(not overlaps(l, Polygon()) and not overlaps(Polygon(), l))


def test_overlaps_follow_the_nonzero_rule() raises -> None:
    # A square wound twice around a hole: the outer ring counts once, the
    # hole zero times -- a shape in the hole overlaps nothing.
    var ring = Polygon(
        (0, 0),
        (10, 0),
        (10, 10),
        (0, 10),
        (0, 0),
        (3, 3),
        (3, 7),
        (7, 7),
        (7, 3),
        (3, 3),
    )
    assert_true(not ring.contains(Point2D(5, 5)))
    var in_hole = Circle((5, 5), 1)
    assert_true(not overlaps(ring, in_hole) and not overlaps(in_hole, ring))
    var in_hole_polygon = Polygon.regular((5, 5), 1, 4)
    assert_true(not overlaps(ring, in_hole_polygon))
    assert_true(not overlaps(in_hole_polygon, ring))
    # The pentagram's doubly wound centre is filled.
    var star = _pentagram()
    var at_center = Rectangle((0, 0), 1, 1)
    assert_true(overlaps(star, at_center) and overlaps(at_center, star))


def test_line_intersects() raises -> None:
    var l = _l_shape()
    # Across the notch, touching neither arm.
    assert_true(not Line((6, 9), (9, 6)).intersects(l))
    assert_true(Line((2, 2), (3, 3)).intersects(l))
    assert_true(Line((-5, 2), (20, 2)).intersects(l))
    assert_true(Line((5, 12), (5, 5)).intersects(l))
    assert_true(not Line((20, 20), (30, 20)).intersects(l))


def test_arc_intersects() raises -> None:
    var l = _l_shape()
    assert_true(not Arc((10, 10), 3, pi, pi / 2.0).intersects(l))
    assert_true(Arc((10, 10), 6, pi, pi / 2.0).intersects(l))
    assert_true(Arc((2, 2), 1, 0.0, tau).intersects(l))
    assert_true(not Arc((30, 30), 2, 0.0, tau).intersects(l))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
