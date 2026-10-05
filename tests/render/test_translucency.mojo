"""Every kind of render call composites once, so a translucent one is as
translucent everywhere — fill and outline included — and opacity reaches
images like everything else.

Each scene draws one shape in red at opacity 0.5 over black with a 6-pixel
outline where it has one: every inked pixel must come out half red (127),
never 191 (two layers) or more. Run through both backends; the GPU half
skips with no GL context.
"""

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from create.core.headless import run_headless
from create.render.render_backend import RenderBackend

comptime _KINDS = 18


def _name(kind: Int) -> String:
    var names: List[String] = [
        "rectangle",
        "rounded rectangle",
        "rotated rectangle",
        "rotated rounded rectangle",
        "stretched rounded rectangle",
        "gradient rectangle",
        "circle",
        "ellipse",
        "triangle",
        "outline-only triangle",
        "needle triangle",
        "rounded triangle",
        "thickly outlined rounded triangle",
        "sheared triangle",
        "sector",
        "polygon",
        "text",
        "image",
    ]
    return names[kind]


def _draw(mut canvas: Canvas, kind: Int) raises:
    if kind == 0:
        canvas.rectangle((0, 0), 40, 40)
    elif kind == 1:
        canvas.corner_radius(8)
        canvas.rectangle((0, 0), 40, 40)
    elif kind == 2:
        with canvas.transform(rotate(0.4)):
            canvas.rectangle((0, 0), 40, 40)
    elif kind == 3:
        canvas.corner_radius(8)
        with canvas.transform(rotate(0.4)):
            canvas.rectangle((0, 0), 40, 40)
    elif kind == 4:
        canvas.corner_radius(8)
        with canvas.transform(scale(2.0, 1.0)):
            canvas.rectangle((0, 0), 30, 40)
    elif kind == 5:
        canvas.fill(Gradient.linear(Color.RED, Color.RED))
        canvas.rectangle((0, 0), 40, 40)
    elif kind == 6:
        canvas.circle((0, 0), 20)
    elif kind == 7:
        with canvas.transform(scale(2.0, 1.0)):
            canvas.circle((0, 0), 20)
    elif kind == 8:
        canvas.triangle((-20, -20), (20, -20), (0, 20))
    elif kind == 9:
        canvas.fill_enabled(False)
        canvas.outline(Color.RED, 10)
        canvas.triangle((-30, -25), (30, -25), (0, 25))
    elif kind == 10:
        # Corners far past the miter limit: bevelled.
        canvas.triangle((-40, -6), (40, -6), (40, 6))
    elif kind == 11:
        canvas.corner_radius(6)
        canvas.triangle((-25, -20), (25, -20), (0, 25))
    elif kind == 12:
        canvas.corner_radius(3)
        canvas.outline(Color.RED, 10)
        canvas.triangle((-30, -25), (30, -25), (0, 25))
    elif kind == 13:
        var shear = identity[3]()
        shear[0, 1] = 0.6
        with canvas.transform(shear):
            canvas.triangle((-20, -20), (20, -20), (0, 20))
    elif kind == 14:
        canvas.sector((0, 0), 30, 0.0, 2.0)
    elif kind == 15:
        canvas.polygon((-20, -20), (20, -20), (20, 20), (-20, 20))
    elif kind == 16:
        canvas.font_size(40)
        canvas.text("WM", (0, 0))
    else:
        canvas.image(Image.solid(30, 30, 255, 0, 0), (0, 0))


@fieldwise_init
struct HalfRed[kind: Int](Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> HalfRed[Self.kind]:
        return HalfRed[Self.kind](0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.fill(Color.RED)
        canvas.outline(Color.RED, 6)
        canvas.text_color(Color.RED)
        canvas.opacity(0.5)
        _draw(canvas, Self.kind)


def _check(kind: Int, backend: String, m: MemorySurface) raises:
    var inked = 0
    var deepest = 0
    for y in range(m.height):
        for x in range(m.width):
            var r = Int(m.pixel(x, y).r)
            if r > 0:
                inked += 1
            deepest = max(deepest, r)
    var name = _name(kind) + " on " + backend
    assert_true(inked > 100, name + ": nothing drawn")
    # Antialiased glyph edges may be lighter; nothing may be deeper.
    assert_true(
        deepest >= 120 and deepest <= 136,
        name + ": deepest red " + String(deepest) + ", expected 127",
    )


def _all(backend: RenderBackend, label: String) raises:
    comptime for kind in range(_KINDS):
        _check(
            kind, label, run_headless[HalfRed[kind]](200, 100, backend=backend)
        )


def test_every_kind_composites_once_on_the_cpu() raises -> None:
    _all(RenderBackend.CPU, "CPU")


def test_every_kind_composites_once_on_the_gpu() raises -> None:
    try:
        _ = run_headless[HalfRed[0]](8, 8, backend=RenderBackend.GPU)
    except e:
        print("SKIP — no GL context:", e)
        return
    _all(RenderBackend.GPU, "GPU")


@fieldwise_init
struct WideRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> WideRect:
        return WideRect(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.outline_enabled(False)
        canvas.fill(Color.RED)
        canvas.corner_radius(4)
        # Stretched, so the general path; 20 units wide is 40 pixels.
        with canvas.transform(scale(2.0, 1.0)):
            canvas.rectangle((0, 0), 20, 20)


def test_a_transformed_rectangle_covers_its_pixels_by_their_centres() raises -> (
    None
):
    # Screen x -20..20 is pixel columns 80..119: column 120 must stay clear,
    # which sampling pixel corners instead of centres once got wrong.
    var m = run_headless[WideRect](200, 100)
    assert_equal(m.pixel(80, 50), Color.RED)
    assert_equal(m.pixel(119, 50), Color.RED)
    assert_equal(m.pixel(79, 50), Color.BLACK)
    assert_equal(m.pixel(120, 50), Color.BLACK)


@fieldwise_init
struct FadedImageShadow(Program):
    var _unused: Int

    @staticmethod
    def create(
        mut context: Context, mut canvas: Canvas
    ) raises -> FadedImageShadow:
        return FadedImageShadow(0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.BLACK)
        canvas.opacity(0.5)
        canvas.shadow(color=Color.GREEN, offset=Vector2D(40, 0), blur=0)
        canvas.image(Image.solid(20, 20, 255, 0, 0), (0, 0))


def test_opacity_fades_a_image_and_its_shadow_once_each() raises -> None:
    var m = run_headless[FadedImageShadow](200, 100)
    assert_equal(m.pixel(100, 50), Color(127, 0, 0), "the image")
    assert_equal(m.pixel(140, 50), Color(0, 127, 0), "its shadow")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
