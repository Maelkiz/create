from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_almost_equal,
)
from std.math import cos, sin, sqrt
from create.math import PI, TAU
from create.geometry._fillet import corner_fillet
from create.geometry.geometry import (
    Rectangle,
    Circle,
    Line,
    Triangle,
    Polygon,
    Sector,
    overlaps,
)
from create.math.point2d import Point2D


def _rounded_square() -> Rectangle:
    # Inner square spans -5..5; every corner is a radius-5 quarter circle.
    return Rectangle((0.0, 0.0), 20.0, 20.0, corner_radius=5.0)


def _rounded_right_triangle() -> Triangle:
    return Triangle((0.0, 0.0), (30.0, 0.0), (0.0, 30.0), corner_radius=3.0)


# Rectangle


def test_a_rounded_rectangle_leaves_its_corner_cut_away() raises -> None:
    var r = _rounded_square()
    assert_false(r.contains(Point2D(9.0, 9.0)))
    assert_true(Rectangle((0.0, 0.0), 20.0, 20.0).contains(Point2D(9.0, 9.0)))


def test_a_rounded_rectangle_holds_its_edges_and_fillets() raises -> None:
    var r = _rounded_square()
    assert_true(r.contains(Point2D(10.0, 0.0)))
    assert_true(r.contains(Point2D(0.0, -10.0)))
    assert_true(r.contains(Point2D(6.0, 6.0)))
    # On the fillet itself: boundary-inclusive, like every region.
    var on_arc = 5.0 + 5.0 / sqrt(2.0)
    assert_true(r.contains(Point2D(on_arc - 1e-9, on_arc - 1e-9)))


def test_the_corner_radius_clamps_to_half_the_shorter_side() raises -> None:
    # Radius 100 on a 20x10 rectangle is 5: a stadium.
    var r = Rectangle((0.0, 0.0), 20.0, 10.0, corner_radius=100.0)
    assert_true(r.contains(Point2D(0.0, 5.0)))
    assert_false(r.contains(Point2D(9.0, 4.0)))
    assert_almost_equal(r.area(), 200.0 - (4.0 - PI) * 25.0, atol=1e-9)


def test_a_rounded_rectangle_closest_point_lands_on_the_fillet() raises -> None:
    var q = _rounded_square().closest_point((20.0, 20.0))
    var expected = 5.0 + 5.0 / sqrt(2.0)
    assert_almost_equal(q.x, expected, atol=1e-9)
    assert_almost_equal(q.y, expected, atol=1e-9)
    # A point inside is its own closest point.
    var inside = _rounded_square().closest_point((1.0, 2.0))
    assert_equal(inside, Point2D(1.0, 2.0))


def test_a_rounded_rectangle_area_loses_its_corners() raises -> None:
    assert_almost_equal(
        _rounded_square().area(), 400.0 - (4.0 - PI) * 25.0, atol=1e-9
    )


def test_rounded_rectangles_close_diagonally_do_not_overlap() raises -> None:
    var a = _rounded_square()
    var b = Rectangle((19.0, 19.0), 20.0, 20.0, corner_radius=5.0)
    assert_false(overlaps(a, b))
    assert_false(overlaps(b, a))
    # Sharp, their corners overlap.
    assert_true(
        overlaps(
            Rectangle((0.0, 0.0), 20.0, 20.0),
            Rectangle((19.0, 19.0), 20.0, 20.0),
        )
    )
    # Side by side, the straight edges still meet.
    assert_true(
        overlaps(a, Rectangle((19.0, 0.0), 20.0, 20.0, corner_radius=5.0))
    )


def test_a_circle_in_the_cut_away_corner_does_not_overlap() raises -> None:
    var c = Circle((9.5, 9.5), 0.5)
    assert_false(overlaps(_rounded_square(), c))
    assert_false(overlaps(c, _rounded_square()))
    assert_true(overlaps(Rectangle((0.0, 0.0), 20.0, 20.0), c))


def test_a_triangle_in_the_cut_away_corner_does_not_overlap() raises -> None:
    var t = Triangle((9.5, 9.5), (10.0, 9.5), (9.5, 10.0))
    assert_false(overlaps(_rounded_square(), t))
    assert_false(overlaps(t, _rounded_square()))
    assert_true(overlaps(Rectangle((0.0, 0.0), 20.0, 20.0), t))


def test_a_line_across_the_cut_away_corner_misses() raises -> None:
    var l = Line((9.0, 11.0), (11.0, 9.0))
    assert_false(l.intersects(_rounded_square()))
    assert_true(l.intersects(Rectangle((0.0, 0.0), 20.0, 20.0)))


def test_containment_sees_the_rounding_both_ways() raises -> None:
    # A sharp square just inside the rounded one pokes out at its corners.
    var sharp = Rectangle((0.0, 0.0), 19.0, 19.0)
    assert_false(_rounded_square().contains(sharp))
    assert_true(Rectangle((0.0, 0.0), 20.0, 20.0).contains(sharp))
    # And the rounded one fits where its sharp corners would not.
    var frame = Polygon(
        Point2D(-10.0, -8.0),
        Point2D(-8.0, -10.0),
        Point2D(8.0, -10.0),
        Point2D(10.0, -8.0),
        Point2D(10.0, 8.0),
        Point2D(8.0, 10.0),
        Point2D(-8.0, 10.0),
        Point2D(-10.0, 8.0),
    )
    assert_true(frame.contains(_rounded_square()))
    assert_false(frame.contains(Rectangle((0.0, 0.0), 20.0, 20.0)))


def test_the_outline_polygon_sits_within_the_rounded_rectangle() raises -> None:
    var r = _rounded_square()
    var outline = r._outline()
    for v in outline.vertices:
        var q = r.closest_point(v)
        assert_almost_equal(q.x, v.x, atol=1e-9)
        assert_almost_equal(q.y, v.y, atol=1e-9)
    assert_almost_equal(outline.area(), r.area(), atol=r.area() * 1e-3)


def test_a_zero_radius_rectangle_is_the_sharp_one() raises -> None:
    var r = Rectangle((0.0, 0.0), 20.0, 20.0, corner_radius=0.0)
    assert_equal(r, Rectangle((0.0, 0.0), 20.0, 20.0))
    assert_true(r.contains(Point2D(10.0, 10.0)))
    assert_equal(r.area(), 400.0)


def test_a_rounded_rectangle_compares_and_prints_its_radius() raises -> None:
    assert_true(_rounded_square() != Rectangle((0.0, 0.0), 20.0, 20.0))
    assert_equal(
        String(Rectangle((0.0, 0.0), 2.0, 3.0, corner_radius=1.0)),
        (
            "Rectangle(position=Point2D(0.0, 0.0), w=2.0, h=3.0,"
            " corner_radius=1.0)"
        ),
    )
    assert_equal(
        String(Rectangle((0.0, 0.0), 2.0, 3.0)),
        "Rectangle(position=Point2D(0.0, 0.0), w=2.0, h=3.0)",
    )


# Triangle


def test_a_rounded_triangle_leaves_its_corner_cut_away() raises -> None:
    var t = _rounded_right_triangle()
    assert_false(t.contains(Point2D(0.2, 0.2)))
    assert_true(
        Triangle((0.0, 0.0), (30.0, 0.0), (0.0, 30.0)).contains(
            Point2D(0.2, 0.2)
        )
    )
    assert_true(t.contains(Point2D(1.0, 10.0)))
    assert_true(t.contains(Point2D(0.0, 10.0)))


def test_rounded_triangle_fillets_are_centred_where_drawn() raises -> None:
    # The inner triangle's corners are the renderer's fillet centres.
    var t = _rounded_right_triangle()
    var inner = t._inner()
    var r = t._radius()
    var f = corner_fillet(t.a.x, t.a.y, t.c.x, t.c.y, t.b.x, t.b.y, r)
    assert_almost_equal(inner.a.x, f[0], atol=1e-9)
    assert_almost_equal(inner.a.y, f[1], atol=1e-9)
    f = corner_fillet(t.b.x, t.b.y, t.a.x, t.a.y, t.c.x, t.c.y, r)
    assert_almost_equal(inner.b.x, f[0], atol=1e-9)
    assert_almost_equal(inner.b.y, f[1], atol=1e-9)
    f = corner_fillet(t.c.x, t.c.y, t.b.x, t.b.y, t.a.x, t.a.y, r)
    assert_almost_equal(inner.c.x, f[0], atol=1e-9)
    assert_almost_equal(inner.c.y, f[1], atol=1e-9)


def test_a_rounded_triangle_area_matches_its_outline() raises -> None:
    var t = _rounded_right_triangle()
    assert_true(t.area() < 450.0)
    assert_almost_equal(t._outline().area(), t.area(), atol=t.area() * 1e-3)


def test_a_rounded_triangle_closest_point_lands_on_the_fillet() raises -> None:
    var q = _rounded_right_triangle().closest_point((-10.0, -10.0))
    # Fillet centred on (3, 3), radius 3, straight back towards the point.
    var expected = 3.0 - 3.0 / sqrt(2.0)
    assert_almost_equal(q.x, expected, atol=1e-9)
    assert_almost_equal(q.y, expected, atol=1e-9)


def test_a_circle_in_a_rounded_triangle_corner_does_not_overlap() raises -> (
    None
):
    var c = Circle((0.3, 0.3), 0.3)
    assert_false(overlaps(_rounded_right_triangle(), c))
    assert_true(overlaps(Triangle((0.0, 0.0), (30.0, 0.0), (0.0, 30.0)), c))


def test_rounded_triangles_close_at_their_tips_do_not_overlap() raises -> None:
    var a = _rounded_right_triangle()
    var b = Triangle(
        (-0.2, -0.2), (-30.0, -0.2), (-0.2, -30.0), corner_radius=3.0
    )
    assert_false(overlaps(a, b))
    var sharp_a = Triangle((0.0, 0.0), (30.0, 0.0), (0.0, 30.0))
    var sharp_b = Triangle((0.1, 0.1), (-30.0, 0.1), (0.1, -30.0))
    assert_true(overlaps(sharp_a, sharp_b))


def test_a_rounded_triangle_compares_and_prints_its_radius() raises -> None:
    var t = Triangle((0.0, 0.0), (1.0, 0.0), (0.0, 1.0), corner_radius=0.5)
    assert_true(t != Triangle((0.0, 0.0), (1.0, 0.0), (0.0, 1.0)))
    assert_equal(
        String(t),
        (
            "Triangle(a=Point2D(0.0, 0.0), b=Point2D(1.0, 0.0), c=Point2D(0.0,"
            " 1.0), corner_radius=0.5)"
        ),
    )


# Polygon


def _rounded_square_polygon() -> Polygon:
    return Polygon(
        Point2D(-10.0, -10.0),
        Point2D(10.0, -10.0),
        Point2D(10.0, 10.0),
        Point2D(-10.0, 10.0),
        corner_radius=5.0,
    )


def test_a_rounded_polygon_rounds_like_a_rounded_rectangle() raises -> None:
    var p = _rounded_square_polygon()
    assert_false(p.contains(Point2D(9.0, 9.0)))
    assert_true(p.contains(Point2D(10.0, 0.0)))
    assert_true(p.contains(Point2D(6.0, 6.0)))
    assert_almost_equal(p.area(), _rounded_square().area(), atol=0.5)


def test_a_rounded_star_loses_its_tips() raises -> None:
    var star = Polygon.star((0.0, 0.0), 50.0, 20.0, 5, corner_radius=5.0)
    var sharp = Polygon.star((0.0, 0.0), 50.0, 20.0, 5)
    # Just inside the top tip.
    assert_true(sharp.contains(Point2D(0.0, 49.0)))
    assert_false(star.contains(Point2D(0.0, 49.0)))
    assert_true(star.contains(Point2D(0.0, 30.0)))


def test_a_rounded_star_fills_its_notches() raises -> None:
    var star = Polygon.star((0.0, 0.0), 50.0, 20.0, 5, corner_radius=5.0)
    var sharp = Polygon.star((0.0, 0.0), 50.0, 20.0, 5)
    # Just outside the inner corner between the first two tips.
    var angle = PI / 2.0 + PI / 5.0
    var p = Point2D(20.5 * cos(angle), 20.5 * sin(angle))
    assert_false(sharp.contains(p))
    assert_true(star.contains(p))


def test_each_corner_clamps_on_its_own() raises -> None:
    # A long thin bar: the radius is clamped by the short edges, not lost.
    var bar = Polygon(
        Point2D(-50.0, -5.0),
        Point2D(50.0, -5.0),
        Point2D(50.0, 5.0),
        Point2D(-50.0, 5.0),
        corner_radius=100.0,
    )
    assert_false(bar.contains(Point2D(49.5, 4.5)))
    assert_true(bar.contains(Point2D(0.0, 4.9)))
    assert_true(bar.contains(Point2D(49.9, 0.0)))


def test_a_rounded_polygon_tests_against_other_shapes() raises -> None:
    var p = _rounded_square_polygon()
    assert_false(overlaps(p, Circle((9.5, 9.5), 0.5)))
    assert_false(overlaps(Circle((9.5, 9.5), 0.5), p))
    var corner = Triangle((9.5, 9.5), (10.0, 9.5), (9.5, 10.0))
    assert_false(overlaps(p, corner))
    assert_false(overlaps(corner, p))
    assert_false(Line((9.0, 11.0), (11.0, 9.0)).intersects(p))
    assert_true(overlaps(p, _rounded_square()))
    assert_true(Rectangle((0.0, 0.0), 20.0, 20.0).contains(p))
    assert_false(p.contains(Rectangle((0.0, 0.0), 19.0, 19.0)))


def test_a_rounded_polygon_compares_and_prints_its_radius() raises -> None:
    var sharp = Polygon.regular((0.0, 0.0), 10.0, 4)
    var rounded = Polygon.regular((0.0, 0.0), 10.0, 4, corner_radius=2.0)
    assert_true(sharp != rounded)
    assert_equal(
        String(
            Polygon(Point2D(0.0, 0.0), Point2D(1.0, 0.0), corner_radius=0.5)
        ),
        (
            "Polygon(vertices=[Point2D(0.0, 0.0), Point2D(1.0, 0.0)],"
            " corner_radius=0.5)"
        ),
    )
    assert_equal(
        String(Polygon(Point2D(0.0, 0.0), Point2D(1.0, 0.0))),
        "Polygon(vertices=[Point2D(0.0, 0.0), Point2D(1.0, 0.0)])",
    )


# Sector


def _rounded_quarter() -> Sector:
    return Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0, corner_radius=8.0)


def test_a_rounded_sector_loses_its_tip_and_arc_ends() raises -> None:
    var s = _rounded_quarter()
    var sharp = Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0)
    # The tip.
    assert_true(sharp.contains(Point2D(0.5, 0.5)))
    assert_false(s.contains(Point2D(0.5, 0.5)))
    # The corner where the start radius meets the arc.
    assert_true(sharp.contains(Point2D(49.5, 0.5)))
    assert_false(s.contains(Point2D(49.5, 0.5)))
    # And the end radius.
    assert_false(s.contains(Point2D(0.5, 49.5)))
    # The middle, the arc's middle and the radii away from the corners.
    assert_true(s.contains(Point2D(20.0, 20.0)))
    var on_arc = 49.9 / sqrt(2.0)
    assert_true(s.contains(Point2D(on_arc, on_arc)))
    assert_true(s.contains(Point2D(25.0, 0.1)))


def test_a_rounded_sector_stays_inside_the_sharp_one() raises -> None:
    var s = _rounded_quarter()
    var sharp = Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0)
    for v in s._outline().vertices:
        assert_true(sharp.contains(v))
    assert_true(s.area() < sharp.area())


def test_a_rounded_wide_sector_fills_its_notch() raises -> None:
    var s = Sector((0.0, 0.0), 50.0, 0.0, 3.0 * PI / 2.0, corner_radius=8.0)
    var sharp = Sector((0.0, 0.0), 50.0, 0.0, 3.0 * PI / 2.0)
    # In the missing wedge, just past the tip.
    var p = Point2D(0.5 * cos(-PI / 4.0), 0.5 * sin(-PI / 4.0))
    assert_false(sharp.contains(p))
    assert_true(s.contains(p))
    assert_true(s.area() > sharp.area() - 200.0)


def test_a_clockwise_sector_rounds_the_same() raises -> None:
    var ccw = _rounded_quarter()
    var cw = Sector((0.0, 0.0), 50.0, PI / 2.0, -PI / 2.0, corner_radius=8.0)
    for p in [
        Point2D(0.5, 0.5),
        Point2D(49.5, 0.5),
        Point2D(20.0, 20.0),
        Point2D(25.0, 0.1),
    ]:
        assert_equal(cw.contains(p), ccw.contains(p))
    assert_almost_equal(cw.area(), ccw.area(), atol=1e-6)


def test_a_half_turn_sector_rounds_only_its_arc_ends() raises -> None:
    var s = Sector((0.0, 0.0), 50.0, 0.0, PI, corner_radius=8.0)
    # The tip runs straight on: nothing to round.
    assert_true(s.contains(Point2D(0.0, 0.2)))
    assert_false(s.contains(Point2D(49.5, 0.5)))
    assert_false(s.contains(Point2D(-49.5, 0.5)))


def test_a_whole_disc_has_no_corners() raises -> None:
    var s = Sector((0.0, 0.0), 10.0, 0.0, TAU, corner_radius=5.0)
    assert_true(s.contains(Point2D(9.9, 0.0)))
    assert_almost_equal(s.area(), PI * 100.0, atol=1e-9)


def test_a_rounded_sector_corner_radius_clamps() raises -> None:
    # Far too large: clamped, still a rounded slice holding its middle.
    var s = Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0, corner_radius=1000.0)
    assert_true(s.contains(Point2D(18.0, 18.0)))
    assert_false(s.contains(Point2D(49.0, 2.0)))
    var sharp = Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0)
    for v in s._outline().vertices:
        assert_true(sharp.contains(v))


def test_a_rounded_sector_tests_against_other_shapes() raises -> None:
    var s = _rounded_quarter()
    var at_tip = Circle((0.4, 0.4), 0.4)
    assert_false(overlaps(s, at_tip))
    assert_false(overlaps(at_tip, s))
    assert_true(overlaps(Sector((0.0, 0.0), 50.0, 0.0, PI / 2.0), at_tip))
    var corner = Rectangle((49.4, 0.6), 0.8, 0.8)
    assert_false(overlaps(s, corner))
    assert_false(overlaps(corner, s))
    assert_true(Rectangle((25.0, 25.0), 50.0, 50.0).contains(s))
    assert_false(s.contains(Rectangle((25.0, 25.0), 50.0, 50.0)))
    assert_false(Line((-1.0, 1.0), (1.0, -1.0)).intersects(s))
    assert_true(overlaps(s, Sector((40.0, 40.0), 10.0, PI, PI / 2.0)))


def test_a_rounded_sector_compares_and_prints_its_radius() raises -> None:
    var sharp = Sector((0.0, 0.0), 1.0, 0.0, 1.0)
    var rounded = Sector((0.0, 0.0), 1.0, 0.0, 1.0, corner_radius=0.25)
    assert_true(sharp != rounded)
    assert_equal(
        String(rounded),
        (
            "Sector(position=Point2D(0.0, 0.0), r=1.0, start_angle=0.0,"
            " sweep_angle=1.0, corner_radius=0.25)"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
