from create import *

comptime _GRAB_RADIUS = 18.0
"""How close, in design units, a click must land to pick up a point."""

comptime _SPEED = 260.0
"""How fast the dot travels along the curve, in design units per second."""


@fieldwise_init
struct App(Program):
    var points: List[Point2D]
    """What the curve passes through, in order."""

    var alpha: Float64
    """0 uniform, 0.5 centripetal, 1 chordal."""

    var closed: Bool

    var dragging: Int
    """The point being dragged, or -1."""

    var travelled: Float64
    """How far along the curve the dot is."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # Authored against the 1280x800 passed to run(): the origin is the
        # centre of the window and y grows upward.
        return App(
            points=[
                (-480.0, -120.0),
                (-300.0, 160.0),
                (-80.0, -40.0),
                (-40.0, 0.0),
                (180.0, 200.0),
                (440.0, -160.0),
            ],
            alpha=0.5,
            closed=False,
            dragging=-1,
            travelled=0.0,
        )

    def _point_under(self, position: Point2D) -> Int:
        for i in range(len(self.points)):
            if (position - self.points[i]).mag() <= _GRAB_RADIUS:
                return i
        return -1

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # No camera, so the mouse is already in the space the points are in.
        var mouse = context.input.mouse
        if context.input.mouse_pressed():
            self.dragging = self._point_under(mouse)
            if self.dragging < 0:
                self.points.append(mouse)
                self.dragging = len(self.points) - 1
        if context.input.mouse_released():
            self.dragging = -1
        if self.dragging >= 0:
            self.points[self.dragging] = mouse
        if context.input.mouse_pressed(MouseButton.RIGHT):
            var i = self._point_under(mouse)
            if i >= 0:
                _ = self.points.pop(i)
        if context.input.key_pressed("c"):
            self.closed = not self.closed
        if context.input.key_pressed("1"):
            self.alpha = 0.0
        if context.input.key_pressed("2"):
            self.alpha = 0.5
        if context.input.key_pressed("3"):
            self.alpha = 1.0

        var spline = Spline(self.points.copy(), self.alpha, self.closed)

        # `at` would move the dot faster along long stretches than short
        # ones; `at_distance` moves it the same distance every second.
        var length = spline.length()
        self.travelled += _SPEED * context.time.delta
        if self.travelled > length:
            self.travelled = 0.0
        var dot = spline.at_distance(self.travelled)

        canvas.background(Color(18, 18, 24))

        # Translucent, so any joint painted twice would show as a brighter
        # seam; there is none, closed or not.
        with canvas.style(
            outline=Color(90, 170, 255, 170),
            outline_thickness=14,
            shadow=Color(0, 0, 0, 160),
            shadow_offset=Vector2D(6, -10),
            shadow_blur=18,
        ):
            canvas.spline(spline)

        canvas.outline_enabled(False)
        if len(self.points) > 0:
            canvas.fill(Color(235, 120, 70))
            canvas.circle(dot, 13)

        for i in range(len(self.points)):
            if i == self.dragging:
                canvas.fill(Color(255, 255, 255))
            else:
                canvas.fill(Color(200, 200, 212))
            canvas.circle(self.points[i], 9)

        var kind: String
        if self.alpha == 0.0:
            kind = "uniform"
        elif self.alpha == 0.5:
            kind = "centripetal"
        else:
            kind = "chordal"
        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text(
            String(
                "Spline, ",
                kind,
                " (alpha ",
                self.alpha,
                ")",
                ", closed" if self.closed else "",
            ),
            (0, 362),
        )
        canvas.font_size(18)
        canvas.text(
            (
                "click to add a point, drag to move, right-click to remove;"
                " C closes, 1 2 3 set alpha"
            ),
            (0, 322),
        )


def main() raises:
    run[App]("Spline", width=1280, height=800)
