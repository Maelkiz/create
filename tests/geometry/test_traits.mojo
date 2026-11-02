from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from create.geometry import (
    Arc,
    Bezier,
    Circle,
    Curve,
    Line,
    Polygon,
    Rectangle,
    Region,
    Sector,
    Shape,
    Spline,
    Triangle,
)
from create.math import PI, Point2D, Vector2D


# Each helper is generic over one trait, so every shape below reaching it
# is checked by the compiler to conform, and the result is checked here.
def _moves_with_its_bounds[S: Shape](var shape: S) raises:
    var before = shape.bounds()
    shape.translate(Vector2D(3.0, -2.0))
    var after = shape.bounds()
    assert_almost_equal(after.position.x, before.position.x + 3.0, atol=1e-9)
    assert_almost_equal(after.position.y, before.position.y - 2.0, atol=1e-9)
    assert_almost_equal(after.w, before.w, atol=1e-9)
    assert_almost_equal(after.h, before.h, atol=1e-9)
    var far = Point2D(100.0, 100.0)
    assert_true(after.contains(shape.closest_point(far)))


def _holds_its_center[R: Region](var region: R) raises:
    assert_true(region.contains(region.center()))
    assert_true(region.area() > 0.0)
    region.move_to((10.0, 10.0))
    assert_true(region.contains((10.0, 10.0)))


def _runs_end_to_end[C: Curve](curve: C) raises:
    var start = curve.at(0.0)
    var end = curve.at(1.0)
    assert_equal(curve.at_distance(0.0), start)
    var far_end = curve.at_distance(curve.length())
    assert_almost_equal(far_end.x, end.x, atol=1e-6)
    assert_almost_equal(far_end.y, end.y, atol=1e-6)
    var points = curve.flatten(0.01)
    assert_equal(points[0], start)
    assert_true(curve.tangent(0.5).magnitude() > 0.0)
    var curves = curve.beziers()
    assert_almost_equal(curves[0].start.x, start.x, atol=1e-9)
    assert_almost_equal(curves[0].start.y, start.y, atol=1e-9)


def test_every_shape_moves_with_its_bounds() raises -> None:
    _moves_with_its_bounds(Rectangle((0.0, 0.0), 4.0, 2.0))
    _moves_with_its_bounds(Circle((1.0, 1.0), 2.0))
    _moves_with_its_bounds(Triangle((0.0, 0.0), (4.0, 0.0), (1.0, 3.0)))
    _moves_with_its_bounds(Sector((0.0, 0.0), 3.0, 0.0, PI / 2.0))
    _moves_with_its_bounds(Polygon.regular(Point2D(0.0, 0.0), 2.0, sides=5))
    _moves_with_its_bounds(Line((0.0, 0.0), (4.0, 3.0)))
    _moves_with_its_bounds(Arc((0.0, 0.0), 2.0, 0.0, PI))
    _moves_with_its_bounds(
        Bezier((0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 0.0))
    )
    _moves_with_its_bounds(
        Spline([Point2D(0.0, 0.0), Point2D(2.0, 3.0), Point2D(5.0, 1.0)])
    )


def test_every_region_holds_its_center() raises -> None:
    _holds_its_center(Rectangle((0.0, 0.0), 4.0, 2.0))
    _holds_its_center(Circle((1.0, 1.0), 2.0))
    _holds_its_center(Triangle((0.0, 0.0), (4.0, 0.0), (1.0, 3.0)))
    _holds_its_center(Polygon.regular(Point2D(0.0, 0.0), 2.0, sides=5))
    # A sector's center() is its tip, on its boundary; move_to places it.
    _holds_its_center(Sector((0.0, 0.0), 3.0, 0.0, PI / 2.0))


def test_every_curve_runs_end_to_end() raises -> None:
    _runs_end_to_end(Line((0.0, 0.0), (4.0, 3.0)))
    _runs_end_to_end(Arc((0.0, 0.0), 2.0, 0.0, PI))
    _runs_end_to_end(Bezier((0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 0.0)))
    _runs_end_to_end(
        Spline([Point2D(0.0, 0.0), Point2D(2.0, 3.0), Point2D(5.0, 1.0)])
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
