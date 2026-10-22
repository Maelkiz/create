"""A shape's own `corner_radius`, drawn: what `canvas.draw` paints for a
rounded rectangle, triangle, polygon or sector agrees with what the shape's
`contains` holds.

A 100 x 100 offscreen canvas: screen x and y in -50..50, y up.
"""
from std.testing import TestSuite, assert_equal, assert_false, assert_true

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
    canvas.draw(r)
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
    canvas.draw(t)
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


def test_a_rounded_star_paints_what_it_contains() raises -> None:
    var star = Polygon.star((0.0, 0.0), 48.0, 20.0, 5, corner_radius=6.0)
    var canvas = _canvas()
    canvas.draw(star)
    var shot = canvas.snapshot()
    # Fillets are flattened, finer in the geometry than on screen.
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
    var checked = 0
    for j in range(0, 100, 2):
        for i in range(0, 100, 2):
            var p = _pixel_centre(i, j)
            var inside = star.contains(p)
            var near = False
            for d in offsets:
                if star.contains(p + d) != inside:
                    near = True
            if near:
                continue
            var painted = shot.pixel(i, 99 - j) == Color.RED
            if painted != inside:
                assert_equal(painted, inside, String(p))
            checked += 1
    assert_true(checked > 2000)


def _assert_sector_paints_what_it_contains(s: Sector) raises:
    var canvas = _canvas()
    canvas.draw(s)
    var shot = canvas.snapshot()
    # Curves are flattened, finer in the geometry than on screen.
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
    var checked = 0
    for j in range(0, 100, 2):
        for i in range(0, 100, 2):
            var p = _pixel_centre(i, j)
            var inside = s.contains(p)
            var near = False
            for d in offsets:
                if s.contains(p + d) != inside:
                    near = True
            if near:
                continue
            var painted = shot.pixel(i, 99 - j) == Color.RED
            if painted != inside:
                assert_equal(painted, inside, String(s) + " at " + String(p))
            checked += 1
    assert_true(checked > 2000)


def test_rounded_sectors_paint_what_they_contain() raises -> None:
    _assert_sector_paints_what_it_contains(
        Sector((-10.0, -15.0), 55.0, 0.3, PI / 3.0, corner_radius=7.0)
    )
    _assert_sector_paints_what_it_contains(
        Sector((0.0, -10.0), 45.0, 0.0, PI, corner_radius=9.0)
    )
    _assert_sector_paints_what_it_contains(
        Sector((0.0, 0.0), 45.0, 0.5, -3.0 * PI / 2.0, corner_radius=10.0)
    )


def test_a_rounded_sector_keeps_its_circle_for_a_gradient() raises -> None:
    var gradient = Gradient.linear(
        Color.RED, Color.BLUE, direction=Vector2D.RIGHT
    )
    var sharp = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    sharp.outline_enabled(False)
    sharp.fill(gradient)
    sharp.sector((0.0, 0.0), 45.0, 0.2, 1.2)
    var rounded = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    rounded.outline_enabled(False)
    rounded.fill(gradient)
    rounded.sector((0.0, 0.0), 45.0, 0.2, 1.2, corner_radius=8.0)
    # Away from the corners, the same colour: both span the whole circle.
    for p in [Point2D(20.0, 15.0), Point2D(30.0, 25.0), Point2D(12.0, 30.0)]:
        assert_equal(rounded.pixel(p), sharp.pixel(p))


def test_the_keyword_rounds_like_the_shape() raises -> None:
    var shape = _canvas()
    shape.draw(Rectangle((0.0, 0.0), 50.0, 30.0, corner_radius=9.0))
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


# The style's radius rounds what the canvas builds from numbers, and only that.


def _same(mut a: Canvas, mut b: Canvas) raises -> Bool:
    var x = a.snapshot()
    var y = b.snapshot()
    for j in range(x.height):
        for i in range(x.width):
            if x.pixel(i, j) != y.pixel(i, j):
                return False
    return True


def test_the_style_rounds_shapes_built_from_numbers() raises -> None:
    var styled = _canvas()
    styled.corner_radius(8)
    styled.rectangle((-20.0, 20.0), 40.0, 30.0)
    styled.triangle((10.0, 5.0), (45.0, 5.0), (28.0, 40.0))
    styled.polygon((-45.0, -45.0), (-5.0, -45.0), (-5.0, -10.0), (-45.0, -10.0))
    styled.sector((25.0, -40.0), 30.0, 0.3, 1.2)
    var shapes = _canvas()
    shapes.draw(Rectangle((-20.0, 20.0), 40.0, 30.0, corner_radius=8))
    shapes.draw(
        Triangle((10.0, 5.0), (45.0, 5.0), (28.0, 40.0), corner_radius=8)
    )
    shapes.draw(
        Polygon(
            Point2D(-45.0, -45.0),
            Point2D(-5.0, -45.0),
            Point2D(-5.0, -10.0),
            Point2D(-45.0, -10.0),
            corner_radius=8,
        )
    )
    shapes.draw(Sector((25.0, -40.0), 30.0, 0.3, 1.2, corner_radius=8))
    assert_true(_same(styled, shapes))
    # And the sharp ones differ, so the comparison means something.
    var sharp = _canvas()
    sharp.rectangle((-20.0, 20.0), 40.0, 30.0)
    var rounded = _canvas()
    rounded.corner_radius(8)
    rounded.rectangle((-20.0, 20.0), 40.0, 30.0)
    assert_false(_same(sharp, rounded))


def test_a_named_radius_beats_the_style() raises -> None:
    var named = _canvas()
    named.corner_radius(12)
    named.rectangle((0.0, 0.0), 60.0, 40.0, corner_radius=0)
    named.rectangle((0.0, 0.0), 30.0, 20.0, corner_radius=3)
    var shapes = _canvas()
    shapes.draw(Rectangle((0.0, 0.0), 60.0, 40.0))
    shapes.draw(Rectangle((0.0, 0.0), 30.0, 20.0, corner_radius=3))
    assert_true(_same(named, shapes))


def test_a_float_radius_reaches_every_keyword() raises -> None:
    var r = 6.5
    var named = _canvas()
    named.rectangle((0.0, 0.0), 60.0, 40.0, corner_radius=r)
    var styled = _canvas()
    with styled.style(corner_radius=r):
        styled.rectangle((0.0, 0.0), 60.0, 40.0)
    var whole = _canvas()
    with whole.style(
        Style(fill=Color.RED, outline_enabled=False, corner_radius=r)
    ):
        whole.rectangle((0.0, 0.0), 60.0, 40.0)
    assert_true(_same(named, styled))
    assert_true(_same(named, whole))


def test_draw_and_clip_ignore_the_style_radius() raises -> None:
    var styled = _canvas()
    styled.corner_radius(15)
    styled.draw(Rectangle((0.0, 0.0), 60.0, 40.0))
    var sharp = _canvas()
    sharp.draw(Rectangle((0.0, 0.0), 60.0, 40.0))
    assert_true(_same(styled, sharp))
    var canvas = Canvas(100, 100, antialiasing=Antialiasing.OFF)
    canvas.corner_radius(20)
    with canvas.clip(Rectangle((0.0, 0.0), 60.0, 60.0)):
        canvas.background(Color.RED)
    # A sharp clip keeps its corner.
    assert_equal(canvas.pixel((29.0, 29.0)), Color.RED)


def test_a_style_block_radius_unwinds() raises -> None:
    var canvas = _canvas()
    with canvas.style(corner_radius=20):
        canvas.rectangle((-25.0, 0.0), 40.0, 40.0)
    canvas.rectangle((25.0, 0.0), 40.0, 40.0)
    # Rounded inside the block, sharp after it.
    assert_equal(canvas.pixel((-44.0, 19.0)), Color.TRANSPARENT)
    assert_equal(canvas.pixel((44.0, 19.0)), Color.RED)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
