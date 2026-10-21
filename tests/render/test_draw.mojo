"""`canvas.draw(shape)`: every shape and curve is `Drawable`, and drawing one
paints exactly what the named method for its kind paints. A program's own
type made of shapes draws the same way.

Offscreen 120 x 100 canvases, antialiasing off, compared pixel for pixel.
"""

from std.math import pi
from std.testing import TestSuite, assert_equal, assert_true

from create import *


def _canvas() raises -> Canvas:
    var canvas = Canvas(120, 100, antialiasing=Antialiasing.OFF)
    canvas.fill(Color(0x40, 0x80, 0xFF))
    canvas.outline(Color.BLACK, thickness=3)
    return canvas^


def _assert_same(mut a: Canvas, mut b: Canvas, what: String) raises:
    var x = a.snapshot()
    var y = b.snapshot()
    var inked = 0
    for j in range(x.height):
        for i in range(x.width):
            var p = x.pixel(i, j)
            if p != y.pixel(i, j):
                assert_equal(p, y.pixel(i, j), what)
            if p != Color.TRANSPARENT:
                inked += 1
    assert_true(inked > 0, what + " drew nothing")


def test_draw_matches_each_named_method() raises -> None:
    var drawn = _canvas()
    var named = _canvas()
    drawn.draw(Rectangle((-30.0, 20.0), 40.0, 30.0, corner_radius=6.0))
    named.rectangle((-30.0, 20.0), 40.0, 30.0, corner_radius=6.0)
    drawn.draw(Circle((30.0, 20.0), 18.0))
    named.circle((30.0, 20.0), 18.0)
    drawn.draw(Triangle((-50.0, -40.0), (-10.0, -40.0), (-30.0, -5.0)))
    named.triangle((-50.0, -40.0), (-10.0, -40.0), (-30.0, -5.0))
    drawn.draw(Sector((20.0, -30.0), 25.0, 0.2, 2.0, corner_radius=4.0))
    named.sector((20.0, -30.0), 25.0, 0.2, 2.0, corner_radius=4.0)
    _assert_same(drawn, named, "regions")


def test_draw_matches_polygons() raises -> None:
    var drawn = _canvas()
    var named = _canvas()
    drawn.draw(
        Polygon(
            Point2D(-40.0, -30.0),
            Point2D(40.0, -30.0),
            Point2D(0.0, 10.0),
            Point2D(30.0, 40.0),
            Point2D(-30.0, 40.0),
            corner_radius=3.0,
        )
    )
    named.polygon(
        (-40.0, -30.0),
        (40.0, -30.0),
        (0.0, 10.0),
        (30.0, 40.0),
        (-30.0, 40.0),
        corner_radius=3.0,
    )
    _assert_same(drawn, named, "polygon")


def test_draw_matches_lines_and_curves() raises -> None:
    var drawn = _canvas()
    var named = _canvas()
    drawn.draw(Line((-55.0, -45.0), (55.0, -35.0)))
    named.line((-55.0, -45.0), (55.0, -35.0))
    drawn.draw(Bezier((-50.0, 0.0), (-20.0, 40.0), (20.0, -40.0), (50.0, 0.0)))
    named.bezier((-50.0, 0.0), (-20.0, 40.0), (20.0, -40.0), (50.0, 0.0))
    drawn.draw(Arc((0.0, 10.0), 30.0, 0.0, pi))
    named.arc((0.0, 10.0), 30.0, 0.0, pi)
    var points: List[Point2D] = [
        Point2D(-50.0, 40.0),
        Point2D(-10.0, 30.0),
        Point2D(20.0, 45.0),
        Point2D(50.0, 35.0),
    ]
    drawn.draw(Spline(points.copy()))
    named.spline(points^)
    _assert_same(drawn, named, "curves")


@fieldwise_init
struct _Badge(Drawable):
    """A program's own type: a rounded plate with a disc on it."""

    var plate: Rectangle
    var disc: Circle

    def draw_to[T: DrawTarget](self, mut target: T):
        target.draw(self.plate)
        target.draw(self.disc)


def test_a_compound_drawable_draws_its_parts() raises -> None:
    var badge = _Badge(
        Rectangle((0.0, 0.0), 80.0, 50.0, corner_radius=10.0),
        Circle((20.0, 0.0), 12.0),
    )
    var drawn = _canvas()
    drawn.draw(badge)
    var parts = _canvas()
    parts.draw(badge.plate)
    parts.draw(badge.disc)
    _assert_same(drawn, parts, "badge")


def _draw_all[T: Drawable & Copyable](mut canvas: Canvas, shapes: List[T]):
    for shape in shapes:
        canvas.draw(shape)


def test_a_generic_helper_draws_any_drawable() raises -> None:
    var circles: List[Circle] = [
        Circle((-30.0, 0.0), 10.0),
        Circle((0.0, 0.0), 10.0),
        Circle((30.0, 0.0), 10.0),
    ]
    var drawn = _canvas()
    _draw_all(drawn, circles)
    var named = _canvas()
    for c in circles:
        named.circle(c.position, c.r)
    _assert_same(drawn, named, "helper")


def test_draw_uses_the_current_style() raises -> None:
    var canvas = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    canvas.outline_enabled(False)
    with canvas.style(fill=Color.RED):
        canvas.draw(Rectangle((0.0, 0.0), 40.0, 40.0))
    canvas.fill(Color.GREEN)
    canvas.draw(Circle((35.0, 35.0), 8.0))
    assert_equal(canvas.pixel((0.0, 0.0)), Color.RED)
    assert_equal(canvas.pixel((35.0, 35.0)), Color.GREEN)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
