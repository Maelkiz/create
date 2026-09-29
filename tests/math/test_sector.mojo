from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from std.math import cos, pi, sin, tau
from create.math.geometry import (
    Arc,
    Circle,
    Line,
    Rectangle,
    Sector,
    Triangle,
    overlaps,
)
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


def _assert_point_near(p: Point2D, q: Point2D, tol: Float64 = 1e-9) raises:
    assert_almost_equal(p.x, q.x, atol=tol)
    assert_almost_equal(p.y, q.y, atol=tol)


def test_prints_in_keyword_form() raises -> None:
    assert_equal(
        String(Sector((1.0, 2.0), 10, 0.5, -1.5)),
        (
            "Sector(position=Point2D(1.0, 2.0), r=10.0, start_angle=0.5,"
            " sweep_angle=-1.5)"
        ),
    )


def test_equality() raises -> None:
    assert_true(Sector((0, 0), 5, 0.0, 1.0) == Sector((0, 0), 5, 0.0, 1.0))
    assert_true(Sector((0, 0), 5, 0.0, 1.0) != Sector((0, 0), 5, 1.0, -1.0))


def test_center_is_the_tip() raises -> None:
    var s = Sector((3, 4), 10, 0.0, pi / 2.0)
    assert_equal(s.center(), Point2D(3.0, 4.0))
    assert_almost_equal(s.end_angle(), pi / 2.0)


def test_area() raises -> None:
    assert_almost_equal(Sector((0, 0), 2, 1.0, -pi).area(), 2.0 * pi)
    # Past a full turn, the whole disc.
    assert_almost_equal(Sector((0, 0), 2, 0.0, 10.0).area(), 4.0 * pi)


def test_arc_is_the_curved_edge() raises -> None:
    assert_equal(Sector((1, 2), 3, 0.5, -1.0).arc(), Arc((1, 2), 3, 0.5, -1.0))


def test_bounds_take_in_the_tip() raises -> None:
    var b = Sector((0, 0), 10, pi / 4.0, pi / 2.0).bounds()
    assert_almost_equal(b.top(), 10.0)
    assert_almost_equal(b.bottom(), 0.0)
    assert_almost_equal(b.left(), -10.0 / 2.0**0.5)
    assert_almost_equal(b.right(), 10.0 / 2.0**0.5)


def test_contains_below_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(s.contains(Point2D(3.0, 3.0)))
    assert_true(not s.contains(Point2D(-3.0, 3.0)))
    assert_true(not s.contains(Point2D(3.0, -3.0)))
    assert_true(not s.contains(Point2D(8.0, 8.0)))
    # Directly opposite the slice: not mistaken for inside.
    assert_true(not s.contains(Point2D(-3.0, -3.0)))


def test_contains_a_clockwise_sweep() raises -> None:
    var s = Sector((0, 0), 10, 0.0, -pi / 2.0)
    assert_true(s.contains(Point2D(3.0, -3.0)))
    assert_true(not s.contains(Point2D(3.0, 3.0)))


def test_contains_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi)
    assert_true(s.contains(Point2D(0.0, 5.0)))
    assert_true(s.contains(Point2D(-5.0, 0.0)))
    assert_true(s.contains(Point2D(5.0, 0.0)))
    assert_true(not s.contains(Point2D(0.0, -0.001)))


def test_contains_just_past_a_half_turn() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi + 0.1)
    assert_true(s.contains(Point2D(-5.0, -0.1)))
    assert_true(not s.contains(Point2D(-5.0, -1.0)))
    assert_true(not s.contains(Point2D(0.0, -5.0)))


def test_three_quarters_leave_out_one_quadrant() raises -> None:
    # From +x round to -y: all but the lower right quadrant.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(s.contains(Point2D(3.0, 3.0)))
    assert_true(s.contains(Point2D(-3.0, 3.0)))
    assert_true(s.contains(Point2D(-3.0, -3.0)))
    assert_true(not s.contains(Point2D(3.0, -3.0)))
    # Its boundary radii are inside.
    assert_true(s.contains(Point2D(5.0, 0.0)))
    assert_true(s.contains(Point2D(0.0, -5.0)))


def test_contains_the_boundary() raises -> None:
    var s = Sector((1, 2), 10, 0.3, 1.2)
    assert_true(s.contains(Point2D(1.0, 2.0)))
    assert_true(s.contains(s.arc().at(0.0)))
    assert_true(s.contains(s.arc().at(0.5)))
    assert_true(s.contains(s.arc().at(1.0)))
    assert_true(s.contains(Point2D(1, 2).lerp(s.arc().at(1.0), 0.5)))


def test_a_full_turn_is_the_disc() raises -> None:
    var s = Sector((0, 0), 10, 1.0, -tau)
    assert_true(s.contains(Point2D(-7.0, -7.0)))
    assert_true(s.contains(Point2D(0.0, -10.0)))
    assert_true(not s.contains(Point2D(0.0, -10.001)))


def test_closest_point_inside_is_itself() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_equal(s.closest_point((2.0, 3.0)), Point2D(2.0, 3.0))


def test_closest_point_beyond_the_arc() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(s.closest_point((0.0, 20.0)), Point2D(0.0, 10.0))
    _assert_point_near(s.closest_point((30.0, 30.0)), s.arc().at(0.5))


def test_closest_point_beside_a_radius() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_point_near(s.closest_point((4.0, -3.0)), Point2D(4.0, 0.0))
    _assert_point_near(s.closest_point((-3.0, 6.0)), Point2D(0.0, 6.0))


def test_closest_point_in_the_missing_wedge() raises -> None:
    # Three quarters, missing the lower right: the nearer of the two radii
    # bounding it, along +x and -y.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    _assert_point_near(s.closest_point((3.0, -1.0)), Point2D(3.0, 0.0))
    _assert_point_near(s.closest_point((1.0, -3.0)), Point2D(0.0, -3.0))


def test_zero_radius_is_the_tip() raises -> None:
    var s = Sector((4, 5), 0, 0.0, pi)
    assert_true(s.contains(Point2D(4.0, 5.0)))
    assert_true(not s.contains(Point2D(4.0, 5.001)))
    assert_equal(s.area(), 0.0)
    _assert_point_near(s.closest_point((10.0, 10.0)), Point2D(4.0, 5.0))


def test_zero_sweep_is_one_radius() raises -> None:
    var s = Sector((0, 0), 10, pi / 2.0, 0.0)
    assert_true(s.contains(Point2D(0.0, 5.0)))
    assert_true(not s.contains(Point2D(0.1, 5.0)))
    assert_true(not s.contains(Point2D(0.0, -5.0)))
    assert_equal(s.area(), 0.0)
    _assert_point_near(s.closest_point((3.0, 5.0)), Point2D(0.0, 5.0))


def test_move_to_and_translate_move_the_tip() raises -> None:
    var s = Sector((0, 0), 5, 0.0, 1.0)
    s.move_to((3.0, 4.0))
    assert_equal(s.position, Point2D(3.0, 4.0))
    s.translate(Vector2D(1.0, -1.0))
    assert_equal(s.position, Point2D(4.0, 3.0))


def _assert_overlap(a: Sector, b: Circle, expected: Bool) raises:
    assert_equal(overlaps(a, b), expected)
    assert_equal(overlaps(b, a), expected)


def _assert_overlap(a: Sector, b: Rectangle, expected: Bool) raises:
    assert_equal(overlaps(a, b), expected)
    assert_equal(overlaps(b, a), expected)


def _assert_overlap(a: Sector, b: Triangle, expected: Bool) raises:
    assert_equal(overlaps(a, b), expected)
    assert_equal(overlaps(b, a), expected)


def _assert_overlap(a: Sector, b: Sector, expected: Bool) raises:
    assert_equal(overlaps(a, b), expected)
    assert_equal(overlaps(b, a), expected)


def test_overlaps_a_circle() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_overlap(s, Circle((5, 5), 1), True)
    _assert_overlap(s, Circle((-5, -5), 3), False)
    # Straddling a radius from outside.
    _assert_overlap(s, Circle((5, -1), 2), True)
    # Just beyond the arc.
    _assert_overlap(s, Circle((0, 12), 1.9), False)
    _assert_overlap(s, Circle((0, 12), 2), True)


def test_does_not_overlap_in_the_missing_wedge() raises -> None:
    # Three quarters, missing the lower right quadrant.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    _assert_overlap(s, Circle((5, -5), 2), False)
    _assert_overlap(s, Rectangle((5, -5), 4, 4), False)
    _assert_overlap(s, Triangle((2, -2), (8, -2), (2, -8)), False)
    _assert_overlap(s, Sector((5, -5), 3, 0.0, tau), False)


def test_overlaps_a_polygon_holding_it() raises -> None:
    var s = Sector((0, 0), 10, 0.3, 1.0)
    _assert_overlap(s, Rectangle((0, 0), 100, 100), True)
    _assert_overlap(s, Triangle((-50, -50), (50, -50), (0, 50)), True)
    # Holding it but not its tip.
    _assert_overlap(
        Sector((-20, 0), 30, -0.1, 0.2), Rectangle((5, 0), 4, 4), True
    )


def test_overlaps_a_polygon_it_holds() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_overlap(s, Rectangle((3, 3), 1, 1), True)
    _assert_overlap(s, Triangle((2, 2), (3, 2), (2, 3)), True)


def test_overlaps_a_polygon_crossing_only_its_edges() raises -> None:
    # A thin bar across the slice, no vertex inside and not holding the tip.
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_overlap(s, Rectangle((5, 5), 40.0, 0.5), True)
    # Crossing just the arc.
    _assert_overlap(
        Sector((0, 0), 10, -0.2, 0.4), Rectangle((10, 0), 0.5, 20.0), True
    )


def test_touching_overlaps() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    _assert_overlap(s, Rectangle((-1, 5), 2, 2), True)
    _assert_overlap(s, Triangle((0, 0), (-3, -1), (-1, -3)), True)
    _assert_overlap(s, Circle((0, 15), 5), True)


def test_overlaps_another_sector() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    # Holding the other's tip.
    _assert_overlap(s, Sector((3, 3), 1, 0.0, 0.5), True)
    # Tips apart, slices crossing.
    _assert_overlap(s, Sector((12, 5), 10, pi - 0.2, 0.4), True)
    # Tips apart, pointing away.
    _assert_overlap(s, Sector((12, 5), 10, -0.2, 0.4), False)
    # One wholly inside the other's missing wedge.
    _assert_overlap(
        Sector((0, 0), 10, 0.0, 1.5 * pi),
        Sector((5, -5), 10, -0.2, 0.4),
        False,
    )


def test_degenerate_sectors_overlap_as_their_shape() raises -> None:
    # Zero radius: the tip.
    _assert_overlap(Sector((4, 5), 0, 0.0, pi), Circle((4, 6), 1), True)
    _assert_overlap(Sector((4, 5), 0, 0.0, pi), Circle((4, 7), 1), False)
    # Zero sweep: one radius, along +y.
    var ray = Sector((0, 0), 10, pi / 2.0, 0.0)
    _assert_overlap(ray, Rectangle((0, 5), 40, 1), True)
    _assert_overlap(ray, Rectangle((0, -5), 40, 1), False)


def test_line_intersects() raises -> None:
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    # Wholly inside.
    assert_true(Line((-3, 3), (-4, 4)).intersects(s))
    # Crossing an edge from outside.
    assert_true(Line((15, 5), (5, 5)).intersects(s))
    # Wholly in the missing wedge.
    assert_true(not Line((2, -2), (5, -6)).intersects(s))
    # Touching a radius.
    assert_true(Line((3, 0), (3, -5)).intersects(s))


def test_arc_intersects() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    # Wholly inside.
    assert_true(Arc((0, 0), 5, 0.2, 0.5).intersects(s))
    # Crossing the curved edge.
    assert_true(Arc((10, 10), 5, pi, 1.0).intersects(s))
    # On the far side of the circle.
    assert_true(not Arc((0, 0), 5, pi, 0.5).intersects(s))
    # Crossing only a radius.
    assert_true(Arc((5, 0), 2, 0.0, -pi).intersects(s))


def test_contains_a_line() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(s.contains(Line((1, 1), (5, 6))))
    # Along a radius.
    assert_true(s.contains(Line((0, 0), (0, 10))))
    assert_true(not s.contains(Line((1, 1), (-1, 5))))
    assert_true(not s.contains(Line((1, 1), (9, 9))))


def test_a_line_across_the_missing_wedge_is_not_contained() raises -> None:
    # Both ends inside the three-quarter sector, the middle in the missing
    # lower right quadrant.
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(s.contains(Point2D(5.0, 1.0)))
    assert_true(s.contains(Point2D(-1.0, -5.0)))
    assert_true(not s.contains(Line((5, 1), (-1, -5))))
    # Round the other side of the tip, it is.
    assert_true(s.contains(Line((5, 1), (-1, 1))))
    # Through the tip, from one radius to the other.
    assert_true(not s.contains(Line((5, 0), (0, -5))))
    assert_true(s.contains(Line((5, 0), (-5, 0))))


def test_contains_a_rectangle_and_a_triangle() raises -> None:
    var s = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(s.contains(Rectangle((-3, 3), 2, 2)))
    # Straddling the missing wedge's corner at the tip.
    assert_true(not s.contains(Rectangle((0, 0), 2, 2)))
    assert_true(not s.contains(Rectangle((-3, 3), 20, 2)))
    assert_true(s.contains(Triangle((-1, 1), (-5, 1), (-1, -5))))
    assert_true(not s.contains(Triangle((5, 1), (-1, 1), (-1, -5))))
    assert_true(not s.contains(Triangle((5, 1), (6, 1), (-1, -5))))


def test_contains_a_circle() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(s.contains(Circle((4, 4), 2)))
    # Tangent to a radius and to the arc from the inside.
    assert_true(s.contains(Circle((2, 4), 2)))
    var t = 10.0 / (1.0 + 2.0**0.5)
    assert_true(s.contains(Circle((t, t), t)))
    # Bulging out through a radius, its centre inside.
    assert_true(not s.contains(Circle((1, 4), 2)))
    assert_true(not s.contains(Circle((5, 5), 4)))
    assert_true(s.contains(Circle((3, 3), 0)))


def test_contains_a_sector() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(s.contains(s))
    assert_true(s.contains(Sector((0, 0), 5, 0.2, 0.5)))
    assert_true(s.contains(Sector((2, 2), 3, 0.0, pi / 2.0)))
    # Too wide for the slice at the same tip.
    assert_true(not s.contains(Sector((0, 0), 5, 0.2, 2.0)))
    # Its arc bulges through the radius though both its ends are inside.
    assert_true(not s.contains(Sector((2, 5), 3, pi / 2.0, pi)))
    # A three-quarter sector holds nothing reaching into its missing wedge.
    var pac = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(pac.contains(Sector((0, 0), 5, 0.1, 1.4 * pi)))
    assert_true(not pac.contains(Sector((0, 0), 5, 0.0, tau)))


def test_regions_contain_a_sector() raises -> None:
    var s = Sector((0, 0), 10, 0.0, pi / 2.0)
    assert_true(Rectangle((5, 5), 10, 10).contains(s))
    assert_true(not Rectangle((5, 5), 9.9, 10.0).contains(s))
    assert_true(Circle((0, 0), 10).contains(s))
    assert_true(Circle((5, 5), 7.1).contains(s))
    assert_true(not Circle((5, 5), 7.0).contains(s))
    assert_true(Triangle((0, 0), (20, 0), (0, 20)).contains(s))
    # Holds the tip and both arc ends, but not the arc's middle.
    assert_true(not Triangle((0, 0), (10, 0), (0, 10)).contains(s))
    # A three-quarter sector reaches down the -y axis.
    var pac = Sector((0, 0), 10, 0.0, 1.5 * pi)
    assert_true(not Circle((0, 0), 20).contains(Sector((25, 0), 1, 0.0, 1.0)))
    assert_true(not Rectangle((0, 5), 30, 10).contains(pac))
    assert_true(not Triangle((-20, 0), (20, 0), (0, 20)).contains(pac))


def test_degenerate_sectors_contain_and_are_contained() raises -> None:
    var tip = Sector((4, 5), 0, 0.0, pi)
    assert_true(tip.contains(Line((4, 5), (4, 5))))
    assert_true(not tip.contains(Line((4, 5), (4, 6))))
    assert_true(tip.contains(Circle((4, 5), 0)))
    assert_true(Circle((4, 5), 1).contains(tip))
    assert_true(Triangle((0, 0), (10, 0), (0, 10)).contains(tip))
    var ray = Sector((0, 0), 10, pi / 2.0, 0.0)
    assert_true(ray.contains(Line((0, 2), (0, 8))))
    assert_true(not ray.contains(Line((0, 2), (1, 8))))
    assert_true(Rectangle((0, 5), 1, 10).contains(ray))
    assert_true(Triangle((-1, 0), (1, 0), (0, 11)).contains(ray))


# A brute-force check of `contains` against points sampled along the
# outline. Sampling can miss a sliver of the outline leaving the sector --
# a segment grazing the tip through the missing wedge, say -- so where the
# coarse pass disagrees the check is redone a hundred times finer.


def _sampled_contains(s: Sector, l: Line, n: Int) -> Bool:
    for i in range(n + 1):
        if not s.contains(l.start.lerp(l.end, Float64(i) / Float64(n))):
            return False
    return True


def _sampled_contains(s: Sector, c: Circle, n: Int) -> Bool:
    for i in range(n):
        var angle = tau * Float64(i) / Float64(n)
        var p = Point2D(
            c.position.x + c.r * cos(angle), c.position.y + c.r * sin(angle)
        )
        if not s.contains(p):
            return False
    return True


def _grid_sectors() -> List[Sector]:
    return [
        Sector((0, 0), 10, 0.3, pi / 2.0),
        Sector((0, 0), 10, 1.0, pi),
        Sector((0, 0), 10, 0.3, 1.5 * pi),
        Sector((0, 0), 10, 2.0, -1.8 * pi),
        Sector((0, 0), 10, 0.0, tau),
    ]


def test_contains_agrees_with_sampling_for_lines() raises -> None:
    for s in _grid_sectors():
        for x0 in range(-10, 11, 4):
            for y0 in range(-10, 11, 4):
                for x1 in range(-10, 11, 4):
                    for y1 in range(-10, 11, 4):
                        var l = Line(
                            Point2D(Float64(x0) + 0.5, Float64(y0) + 0.25),
                            Point2D(Float64(x1) + 0.5, Float64(y1) + 0.25),
                        )
                        var sampled = _sampled_contains(s, l, 100)
                        if sampled != s.contains(l):
                            sampled = _sampled_contains(s, l, 10000)
                        assert_equal(s.contains(l), sampled, String(l))


def test_contains_agrees_with_sampling_for_circles() raises -> None:
    for s in _grid_sectors():
        for x in range(-9, 10, 3):
            for y in range(-9, 10, 3):
                for r in range(1, 5):
                    var c = Circle(
                        Point2D(Float64(x) + 0.25, Float64(y) + 0.5),
                        Float64(r) * 0.9,
                    )
                    var sampled = _sampled_contains(s, c, 180)
                    if sampled != s.contains(c):
                        sampled = _sampled_contains(s, c, 18000)
                    assert_equal(s.contains(c), sampled, String(c))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
