from std.math import tau

from create import *

comptime _BACKGROUND = Color(40, 42, 56)
"""Light enough for the U's shadow to show against it."""

comptime _SPIN = 0.6
"""How fast the stars turn, in radians per second."""

comptime _PENTAGRAM_HOME = Point2D(520.0, -80.0)


def _side_color(sides: Int) -> Color:
    var colors: List[Color] = [
        Color(90, 170, 255),
        Color(235, 120, 70),
        Color(120, 210, 140),
        Color(240, 200, 80),
        Color(190, 130, 230),
        Color(80, 200, 210),
    ]
    return colors[(sides - 3) % len(colors)]


def _pentagram(position: Point2D, r: Float64) -> Polygon:
    """Five vertices joined every second one, so the edges cross; under the
    nonzero rule the middle, wound twice, is still inside."""
    var tips = Polygon.regular(position, r, 5).vertices.copy()
    return Polygon(tips[0], tips[2], tips[4], tips[1], tips[3])


@fieldwise_init
struct App(Program):
    var inner_ratio: Float64
    """The stars' inner radius as a fraction of the outer; up and down."""

    var pentagram: Polygon
    """Dragged onto the U to test the overlap."""

    var dragging: Bool

    var grab: Vector2D
    """From the mouse to the pentagram's first vertex, while dragging."""

    @staticmethod
    def create(mut context: Context) raises -> App:
        return App(
            inner_ratio=0.45,
            pentagram=_pentagram(_PENTAGRAM_HOME, 55),
            dragging=False,
            grab=Vector2D(0, 0),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # No camera, so the mouse is already in the space the shapes are in.
        var mouse = context.input.mouse

        if context.input.key_down("up"):
            self.inner_ratio = min(self.inner_ratio + context.time.delta, 1.0)
        if context.input.key_down("down"):
            self.inner_ratio = max(self.inner_ratio - context.time.delta, 0.1)

        # Held where it was grabbed, so the pentagram doesn't jump to put
        # its middle under the cursor.
        var first = self.pentagram.vertices[0]
        if context.input.mouse_pressed() and self.pentagram.contains(mouse):
            self.dragging = True
            self.grab = first - mouse
        if context.input.mouse_released():
            self.dragging = False
        if self.dragging:
            self.pentagram.translate(mouse + self.grab - first)

        canvas.background(_BACKGROUND)
        canvas.outline_enabled(False)

        # Regular polygons, three sides to eight; the one under the mouse
        # lights up.
        for sides in range(3, 9):
            var x = -500.0 + 200.0 * Float64(sides - 3)
            var shape = Polygon.regular((x, 170), 70, sides)
            if shape.contains(mouse):
                canvas.fill(Color.WHITE)
            else:
                canvas.fill(_side_color(sides))
            canvas.polygon(shape)

        # Stars turning either way. Every star's first tip points up at
        # rest; `start_angle` turns it.
        var turn = context.time.elapsed * _SPIN
        for i in range(3):
            var tips = 5 + i
            var direction = 1.0 if i % 2 == 0 else -1.0
            var star = Polygon.star(
                (-480.0 + 170.0 * Float64(i), -150.0),
                75,
                75 * self.inner_ratio,
                tips,
                start_angle=tau / 4.0 + direction * turn,
            )
            if star.contains(mouse):
                canvas.fill(Color.WHITE)
            else:
                canvas.fill(Color(240, 200, 80))
            canvas.polygon(star)

        # A concave U from literal vertices, translucent and shadowed. Its
        # notch is outside it: hovering there lights nothing, and the
        # pentagram dropped in the notch overlaps nothing.
        var u = Polygon(
            (60, -300),
            (360, -300),
            (360, 20),
            (270, 20),
            (270, -190),
            (150, -190),
            (150, 20),
            (60, 20),
        )
        var hit = overlaps(u, self.pentagram)
        var fill = Color(90, 170, 255, 150)
        if u.contains(mouse):
            fill = Color(255, 255, 255, 190)
        with canvas.style(
            fill=fill,
            outline=Color(235, 120, 70) if hit else Color(200, 200, 212),
            outline_thickness=6,
            shadow=Color(0, 0, 0, 170),
            shadow_offset=Vector2D(10, -14),
            shadow_blur=24,
        ):
            canvas.polygon(u)

        # Translucent, so the outline shows every edge, the crossing ones
        # through the middle too, while the middle is filled just once.
        with canvas.style(
            fill=Color(120, 210, 140, 90),
            outline=Color(120, 210, 140),
            outline_thickness=3,
        ):
            canvas.polygon(self.pentagram)

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Polygons", (0, 362))
        canvas.font_size(18)
        canvas.text(
            "hover the shapes; up and down change the stars' inner radius"
            + " ("
            + String(Int(self.inner_ratio * 100.0 + 0.5))
            + "%); drag the pentagram onto the U.",
            (0, 322),
        )


def main() raises:
    run[App]("Polygons", width=1280, height=800)
