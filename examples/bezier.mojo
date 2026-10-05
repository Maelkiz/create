from create import *

comptime _GRAB_RADIUS = 18.0
"""How close, in design units, a press must land to pick up a handle."""

comptime _SPEED = 260.0
"""How fast the dot travels along the curve, in design units per second."""


@fieldwise_init
struct App(Program):
    var handles: List[Point2D]
    """`start`, `control1`, `control2`, `end`, in the order `Bezier`
    takes them."""

    var dragging: Int
    """The handle being dragged, or -1."""

    var travelled: Float64
    """How far along the curve the dot is."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> App:
        # Authored against the 1280x800 passed to run(): the origin is the
        # centre of the window and y grows upward.
        return App(
            handles=[
                (-420.0, -180.0),
                (-260.0, 260.0),
                (260.0, -260.0),
                (420.0, 180.0),
            ],
            dragging=-1,
            travelled=0.0,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # No camera, so the mouse is already in the space the handles are in.
        var mouse = context.input.mouse
        if context.input.mouse_pressed():
            for i in range(len(self.handles)):
                if (mouse - self.handles[i]).mag() <= _GRAB_RADIUS:
                    self.dragging = i
        if context.input.mouse_released():
            self.dragging = -1
        if self.dragging >= 0:
            self.handles[self.dragging] = mouse

        var curve = Bezier(
            self.handles[0], self.handles[1], self.handles[2], self.handles[3]
        )

        # `at` would bunch the dot up wherever the controls pull the curve
        # tight; `at_distance` moves it the same distance every second.
        var length = curve.length()
        self.travelled += _SPEED * context.time.delta
        if self.travelled > length:
            self.travelled = 0.0
        var dot = curve.at_distance(self.travelled)

        canvas.background(Color(18, 18, 24))

        # The control polygon: each control's pull on its endpoint.
        canvas.outline(Color(70, 70, 90), thickness=2)
        canvas.line(self.handles[0], self.handles[1])
        canvas.line(self.handles[3], self.handles[2])

        # The curve itself, with a soft shadow. A curve has no interior, so
        # only the outline draws and casts.
        with canvas.style(
            outline=Color(90, 170, 255),
            outline_thickness=12,
            shadow=Color(0, 0, 0, 160),
            shadow_offset=Vector2D(6, -10),
            shadow_blur=18,
        ):
            canvas.bezier(curve)

        canvas.outline_enabled(False)
        canvas.fill(Color(235, 120, 70))
        canvas.circle(dot, 13)

        for i in range(len(self.handles)):
            var endpoint = i == 0 or i == 3
            if i == self.dragging:
                canvas.fill(Color(255, 255, 255))
            elif endpoint:
                canvas.fill(Color(200, 200, 212))
            else:
                canvas.fill(Color(120, 120, 140))
            canvas.circle(self.handles[i], 10 if endpoint else 8)

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Cubic Bézier", (0, 362))
        canvas.font_size(18)
        canvas.text("drag the handles to reshape the curve", (0, 322))


def main() raises:
    run[App]("Cubic Bézier", width=1280, height=800)
