"""`canvas.clip`: what it keeps, on both backends.

Each scene renders onto a 200 x 100 frame (screen x in -100..100, y in
-50..50, y up) and is sampled away from every edge, so the assertions hold
whichever pixel-centre convention a backend breaks ties by. The GPU half
reruns every scene and also compares whole frames, skipping with no GL
context like the other GL tests.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless
from create.render._clip import _ClipRows
from create.render.render_backend import RenderBackend

comptime _W = 200
comptime _H = 100
comptime _GRAY = Color(200)

comptime _RECT = 0
comptime _INVERTED_CIRCLE = 1
comptime _NESTED = 2
comptime _ROTATED = 3
comptime _FROZEN = 4
comptime _CONCAVE = 5
comptime _PAINTS = 6
"""A gradient fill, glyphs and a hard shadow, all reaching past the clip:
the CPU's shaded spans and per-pixel `blend` are clipped separately from
its solid spans."""
comptime _WEDGE = 7
"""A sector nested in a triangle: the two overloads the others leave out."""
comptime _SCENES = 8


@fieldwise_init
struct Clipped[scene: Int](Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> Clipped[Self.scene]:
        return Clipped[Self.scene](0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        comptime if Self.scene == _RECT:
            with canvas.clip(Rectangle((0, 0), 40, 20)):
                canvas.background(Color.RED)
        elif Self.scene == _INVERTED_CIRCLE:
            with canvas.clip(Circle((0, 0), 20), invert=True):
                canvas.background(Color.BLUE)
        elif Self.scene == _NESTED:
            with canvas.clip(Rectangle((-20, 0), 80, 40)):
                with canvas.clip(Rectangle((20, 0), 80, 40)):
                    canvas.rectangle((0, 0), 200, 100)
                canvas.fill(Color.BLUE)
                canvas.rectangle((-50, 0), 60, 100)
        elif Self.scene == _ROTATED:
            with canvas.transform(rotate(pi / 4.0)):
                with canvas.clip(Rectangle((0, 0), 40, 40)):
                    canvas.rectangle((0, 0), 200, 200)
        elif Self.scene == _FROZEN:
            with canvas.clip(Rectangle((0, 0), 20, 20)):
                with canvas.transform(translate(30.0, 0.0)):
                    canvas.rectangle((0, 0), 100, 100)
        elif Self.scene == _WEDGE:
            with canvas.clip(Triangle((-40, -30), (40, -30), (0, 30))):
                with canvas.clip(Sector((0, 0), 25, 0.0, pi)):
                    canvas.rectangle((0, 0), 200, 100)
        elif Self.scene == _PAINTS:
            with canvas.clip(Rectangle((0, 0), 40, 20)):
                canvas.fill(Gradient.linear(Color.RED, Color.BLUE))
                canvas.rectangle((0, 0), 100, 60)
                canvas.shadow(color=Color.BLACK, offset=Vector2D(30, -30))
                canvas.rectangle((-30, 30), 30, 30)
                canvas.font_size(40)
                canvas.text_color(Color.BLACK)
                canvas.text("MMMMMMMM", (0, 0))
        else:
            var l_shape = Polygon(
                [
                    Point2D(-30, -30),
                    Point2D(30, -30),
                    Point2D(30, 0),
                    Point2D(0, 0),
                    Point2D(0, 30),
                    Point2D(-30, 30),
                ]
            )
            with canvas.clip(l_shape):
                canvas.rectangle((0, 0), 200, 100)
        # Outside every clip again: a mark in the corner proves the guard
        # closed.
        canvas.fill(Color.GREEN)
        canvas.rectangle((90, 40), 10, 10)


def _at(m: MemorySurface, x: Int, y: Int) -> Color:
    """The pixel under screen point `(x, y)`."""
    return m.pixel(_W // 2 + x, _H // 2 - y)


def _frame[scene: Int](backend: RenderBackend) raises -> MemorySurface:
    return run_headless[Clipped[scene]](_W, _H, backend=backend)


def _check(scene: Int, m: MemorySurface) raises:
    """The samples every backend must agree on."""
    var name = "scene " + String(scene)
    assert_equal(_at(m, 90, 40), Color.GREEN, name + ": closed")
    if scene == _RECT:
        assert_equal(_at(m, 0, 0), Color.RED, name)
        assert_equal(_at(m, 15, 5), Color.RED, name)
        assert_equal(_at(m, 30, 0), _GRAY, name + ": outside, not cleared")
        assert_equal(_at(m, 0, 15), _GRAY, name)
    elif scene == _INVERTED_CIRCLE:
        assert_equal(_at(m, 0, 0), _GRAY, name + ": the hole")
        assert_equal(_at(m, 12, 12), _GRAY, name)
        assert_equal(_at(m, 50, 0), Color.BLUE, name)
        assert_equal(_at(m, 0, 40), Color.BLUE, name)
        assert_equal(_at(m, 18, 18), Color.BLUE, name + ": past the rim")
    elif scene == _NESTED:
        assert_equal(_at(m, 0, 0), Color.RED, name + ": inside both")
        assert_equal(_at(m, 40, 0), _GRAY, name + ": outer only")
        assert_equal(_at(m, -40, 0), Color.BLUE, name + ": inner closed")
        assert_equal(_at(m, -70, 0), _GRAY, name + ": outer still on")
        assert_equal(_at(m, 0, 30), _GRAY, name)
    elif scene == _ROTATED:
        # A diamond, |x| + |y| < 28.3, not the upright square.
        assert_equal(_at(m, 25, 0), Color.RED, name)
        assert_equal(_at(m, 0, -25), Color.RED, name)
        assert_equal(_at(m, 10, 10), Color.RED, name)
        assert_equal(_at(m, 16, 16), _GRAY, name + ": a square's corner")
    elif scene == _FROZEN:
        assert_equal(_at(m, 0, 0), Color.RED, name + ": the clip stayed")
        assert_equal(_at(m, 30, 0), _GRAY, name + ": the rect moved")
    elif scene == _WEDGE:
        assert_equal(_at(m, 0, 10), Color.RED, name)
        assert_equal(_at(m, 5, 5), Color.RED, name)
        assert_equal(_at(m, 0, -10), _GRAY, name + ": below the sector")
        assert_equal(_at(m, 20, 20), _GRAY, name + ": beside the triangle")
    elif scene == _PAINTS:
        assert_true(_at(m, 0, 0) != _GRAY, name + ": inside")
        for y in range(-_H // 2 + 1, _H // 2):
            for x in range(-_W // 2, _W // 2):
                var outside = x < -21 or x > 20 or y < -11 or y > 11
                if outside and x < 80:
                    assert_equal(
                        _at(m, x, y),
                        _GRAY,
                        name + ": at " + String(x) + ", " + String(y),
                    )
    else:
        assert_equal(_at(m, 15, -15), Color.RED, name)
        assert_equal(_at(m, -15, 15), Color.RED, name)
        assert_equal(_at(m, -15, -15), Color.RED, name)
        assert_equal(_at(m, 15, 15), _GRAY, name + ": the notch")
        assert_equal(_at(m, 40, 0), _GRAY, name)


def _all[backend: RenderBackend]() raises -> List[MemorySurface]:
    var out = List[MemorySurface]()
    out.append(_frame[_RECT](backend))
    out.append(_frame[_INVERTED_CIRCLE](backend))
    out.append(_frame[_NESTED](backend))
    out.append(_frame[_ROTATED](backend))
    out.append(_frame[_FROZEN](backend))
    out.append(_frame[_CONCAVE](backend))
    out.append(_frame[_PAINTS](backend))
    out.append(_frame[_WEDGE](backend))
    return out^


def _same_rgb(a: MemorySurface, b: MemorySurface, x: Int, y: Int) -> Bool:
    var i = (y * _W + x) * 4
    for k in range(3):
        if a.data[i + k] != b.data[i + k]:
            return False
    return True


def _flat(m: MemorySurface, x: Int, y: Int) -> Bool:
    """Whether `(x, y)` and its eight neighbours are all one colour."""
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            if not _rgb_equal(m, x, y, x + dx, y + dy):
                return False
    return True


def _rgb_equal(m: MemorySurface, x0: Int, y0: Int, x1: Int, y1: Int) -> Bool:
    var i = (y0 * _W + x0) * 4
    var j = (y1 * _W + x1) * 4
    for k in range(3):
        if m.data[i + k] != m.data[j + k]:
            return False
    return True


def test_cpu_clips() raises -> None:
    var frames = _all[RenderBackend.CPU]()
    for scene in range(_SCENES):
        _check(scene, frames[scene])


def test_gpu_clips_like_the_cpu() raises -> None:
    var gpu: List[MemorySurface]
    try:
        gpu = _all[RenderBackend.GPU]()
    except e:
        print("SKIP — no GL context:", e)
        return
    var cpu = _all[RenderBackend.CPU]()
    for scene in range(_SCENES):
        _check(scene, gpu[scene])
        if scene == _PAINTS:
            # Glyph coverage and gradient dither differ within a level
            # inside; `_check` has already seen every pixel outside.
            continue
        # Interiors must agree; edges may not. The GPU multisamples a clip's
        # edge like a shape's, where the CPU keeps it hard, so only pixels
        # whose CPU neighbourhood is one colour — away from every edge — are
        # compared. The allowance is for the shapes' own edges, where the two
        # rasterisers already part (see `test_gl_parity.mojo`).
        var differing = 0
        for y in range(1, _H - 1):
            for x in range(1, _W - 1):
                if not _flat(cpu[scene], x, y):
                    continue
                if not _same_rgb(cpu[scene], gpu[scene], x, y):
                    differing += 1
        assert_true(
            differing <= 80,
            "scene "
            + String(scene)
            + ": "
            + String(differing)
            + " pixels differ",
        )


def test_rows_merge_invert_and_intersect() raises -> None:
    # Row 0: two overlapping runs and one apart; row 1: nothing. The fourth
    # of each is the paint key, which a clip ignores.
    var runs: List[Int] = [0, 5, 9, 0, 0, 2, 6, 0, 0, 12, 14, 0]
    var rows = _ClipRows(runs, 16, 2, invert=False)
    assert_equal(rows.starts, [0, 2, 2])
    assert_equal(rows.spans, [2, 9, 12, 14])

    var holes = _ClipRows(runs, 16, 2, invert=True)
    assert_equal(holes.starts, [0, 3, 4])
    assert_equal(holes.spans, [0, 2, 9, 12, 14, 16, 0, 16])

    var both = rows.intersect(
        _ClipRows([0, 4, 13, 0, 1, 0, 3, 0], 16, 2, False)
    )
    assert_equal(both.starts, [0, 2, 2])
    assert_equal(both.spans, [4, 9, 12, 13])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
