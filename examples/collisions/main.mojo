"""Collision tests against a circle that follows the mouse.

The four regions light up while they `overlap` it, and the two curves, a
`Line` and an `Arc`, while they `intersect` it: a curve has no inside, so it
is crossed rather than overlapped. A thin line runs from the mouse to each
shape's `closest_point`, which inside a region is the mouse itself.
"""

from create import *

comptime _BACKGROUND = Color(40, 42, 56)
comptime _SHAPE = Color(90, 170, 255)
comptime _HIT = Color(120, 210, 140)
comptime _GUIDE = Color(120, 124, 150)
comptime _TEXT = Color(200, 200, 212)


def _reach[S: Shape](mut canvas: Canvas, shape: S, mouse: Point2D):
    """A line from the mouse to the nearest point of `shape`, and a dot
    there. Any shape answers `closest_point`, so one function serves all."""
    var nearest = shape.closest_point(mouse)
    with canvas.style(outline=_GUIDE, outline_thickness=2):
        canvas.line(mouse, nearest)
    with canvas.style(fill=_GUIDE, outline_enabled=False):
        canvas.circle(nearest, 5)


@fieldwise_init
struct Collisions(Program):
    var probe: Circle
    """The circle that follows the mouse."""
    var rectangle: Rectangle
    var circle: Circle
    var triangle: Triangle
    var star: Polygon
    var line: Line
    var arc: Arc

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Collisions:
        return Collisions(
            probe=Circle((0, 0), 45),
            rectangle=Rectangle((-420, 110), 200, 140, corner_radius=16),
            circle=Circle((-140, 110), 80),
            triangle=Triangle((80, 40), (240, 40), (160, 190)),
            star=Polygon.star((440, 110), 95, 42, 5),
            line=Line((-520, -140), (-160, -280)),
            arc=Arc((180, -250), 130, 0.3, 2.5),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        var mouse = context.input.mouse
        self.probe = self.probe.move_to(mouse)

        canvas.background(_BACKGROUND)

        # Regions: filled, lit while they overlap the probe.
        with canvas.style(outline_enabled=False):
            canvas.fill(
                _HIT if overlaps(self.rectangle, self.probe) else _SHAPE
            )
            canvas.draw(self.rectangle)
            canvas.fill(_HIT if overlaps(self.circle, self.probe) else _SHAPE)
            canvas.draw(self.circle)
            canvas.fill(_HIT if overlaps(self.triangle, self.probe) else _SHAPE)
            canvas.draw(self.triangle)
            canvas.fill(_HIT if overlaps(self.star, self.probe) else _SHAPE)
            canvas.draw(self.star)

        # Curves: stroked, lit while they cross the probe.
        with canvas.style(outline_thickness=8):
            canvas.outline(_HIT if self.line.intersects(self.probe) else _SHAPE)
            canvas.draw(self.line)
            canvas.outline(_HIT if self.arc.intersects(self.probe) else _SHAPE)
            canvas.draw(self.arc)

        with canvas.style(
            fill=Color(200, 200, 212, 60), outline=_TEXT, outline_thickness=2
        ):
            canvas.draw(self.probe)

        _reach(canvas, self.rectangle, mouse)
        _reach(canvas, self.circle, mouse)
        _reach(canvas, self.triangle, mouse)
        _reach(canvas, self.star, mouse)
        _reach(canvas, self.line, mouse)
        _reach(canvas, self.arc, mouse)

        with canvas.style(text_color=_TEXT, font_size=30, text_align=Align.TOP):
            canvas.text("Collisions", (0, 362))
        with canvas.style(text_color=_TEXT, font_size=18, text_align=Align.TOP):
            canvas.text(
                "Regions light up as they overlap the circle, curves as they"
                + " cross it; lines run to each shape's closest point",
                (0, 322),
            )


def main() raises:
    run[Collisions]("Collisions", width=1280, height=800)
