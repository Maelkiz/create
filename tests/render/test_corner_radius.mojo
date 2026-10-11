"""A shape's own `corner_radius`, drawn: what `canvas.rectangle` and
`canvas.triangle` paint agrees with what the shape's `contains` holds.

A 100 x 100 offscreen canvas: screen x and y in -50..50, y up.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *


def _canvas() raises -> Canvas:
    var canvas = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    canvas.fill(Color.RED)
    canvas.outline_enabled(False)
    return canvas^


def _pixel_centre(i: Int, j: Int) -> Point2D:
    """The centre of image pixel `(i, 99 - j)`: `j` counts up from the
    bottom, as y does."""
    return Point2D(-49.5 + Float64(i), -49.5 + Float64(j))


def test_a_rounded_rectangle_paints_what_it_contains() raises -> None:
    var r = Rectangle((3.0, -2.0), 60.0, 44.0, corner_radius=15.0)
    # Pixel centres this close to the edge may fall either way.
    var grown = Rectangle(r.position, r.w + 0.2, r.h + 0.2, corner_radius=15.1)
    var shrunk = Rectangle(r.position, r.w - 0.2, r.h - 0.2, corner_radius=14.9)
    var canvas = _canvas()
    canvas.rectangle(r)
    var shot = canvas.snapshot()
    var checked = 0
    for j in range(100):
        for i in range(100):
            var p = _pixel_centre(i, j)
            if grown.contains(p) != shrunk.contains(p):
                continue
            var painted = shot.pixel(i, 99 - j) == Color.RED
            if painted != r.contains(p):
                assert_equal(painted, r.contains(p), String(p))
            checked += 1
    assert_true(checked > 9000)


def test_a_rounded_triangle_paints_what_it_contains() raises -> None:
    var t = Triangle(
        (-40.0, -35.0), (45.0, -30.0), (-5.0, 40.0), corner_radius=8.0
    )
    var canvas = _canvas()
    canvas.triangle(t)
    var shot = canvas.snapshot()
    # The triangle's fillets are drawn as chords, which sit inside the true
    # arc by up to about a quarter pixel at this radius, so centres within
    # half a pixel of the edge may fall either way.
    var offsets: List[Vector2D] = [
        Vector2D(0.5, 0.0),
        Vector2D(-0.5, 0.0),
        Vector2D(0.0, 0.5),
        Vector2D(0.0, -0.5),
        Vector2D(0.35, 0.35),
        Vector2D(-0.35, 0.35),
        Vector2D(0.35, -0.35),
        Vector2D(-0.35, -0.35),
    ]
    # Every other pixel each way is plenty, and the check is slow unoptimised.
    var checked = 0
    for j in range(0, 100, 2):
        for i in range(0, 100, 2):
            var p = _pixel_centre(i, j)
            # Skip centres within half a pixel of the rounded boundary.
            var inside = t.contains(p)
            var near = False
            for d in offsets:
                if t.contains(p + d) != inside:
                    near = True
            if near:
                continue
            var painted = shot.pixel(i, 99 - j) == Color.RED
            if painted != inside:
                assert_equal(painted, inside, String(p))
            checked += 1
    assert_true(checked > 2200)


def test_the_keyword_rounds_like_the_shape() raises -> None:
    var shape = _canvas()
    shape.rectangle(Rectangle((0.0, 0.0), 50.0, 30.0, corner_radius=9.0))
    var keyword = _canvas()
    keyword.rectangle((0.0, 0.0), 50.0, 30.0, corner_radius=9.0)
    var a = shape.snapshot()
    var b = keyword.snapshot()
    for y in range(a.height):
        for x in range(a.width):
            assert_equal(a.pixel(x, y), b.pixel(x, y))


def test_a_rounded_clip_keeps_only_the_rounded_shape() raises -> None:
    var canvas = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    with canvas.clip(Rectangle((0.0, 0.0), 60.0, 60.0, corner_radius=20.0)):
        canvas.background(Color.RED)
    # The sharp corner is cut away, the middle of each edge kept.
    assert_equal(canvas.pixel((29.0, 29.0)), Color.TRANSPARENT)
    assert_equal(canvas.pixel((0.0, 29.0)), Color.RED)
    assert_equal(canvas.pixel((29.0, 0.0)), Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
