from std.math import cos, pi, sin, tau

from create import *

comptime _BACKGROUND = Color(40, 42, 56)
"""Light enough for the pac-man's shadow to show against it."""

comptime _PIE = Point2D(0.0, -20.0)
comptime _PIE_RADIUS = 170.0
comptime _POP = 16.0
"""How far the slice under the mouse slides out, in design units."""

comptime _CHEW = 4.0
"""How fast the pac-man's mouth works; it shuts every pi / _CHEW seconds."""

comptime _BALL_HOME = Point2D(420.0, -250.0)
comptime _RESPAWN = 3.0
"""Seconds an eaten ball stays gone before it is back at `_BALL_HOME`."""


def _shares() -> List[Float64]:
    """The pie chart's slices, as fractions of the whole."""
    return [0.38, 0.24, 0.17, 0.13, 0.08]


def _slice_color(i: Int) -> Color:
    var colors: List[Color] = [
        Color(90, 170, 255),
        Color(235, 120, 70),
        Color(120, 210, 140),
        Color(240, 200, 80),
        Color(190, 130, 230),
    ]
    return colors[i % len(colors)]


@fieldwise_init
struct App(Program):
    var progress: Tween
    """Walks both rings from empty to full."""

    var ball: Circle
    """Dragged over the pac-man to test the overlap."""

    var respawn_in: Float64
    """Seconds until the eaten ball comes back; 0 while it is out."""

    var dragging: Bool

    var bites: Int
    """How many times the mouth has shut."""

    @staticmethod
    def create(mut context: Context) raises -> App:
        var progress = Tween(3.0, Easing.IN_OUT_CUBIC)
        progress.loop()
        return App(
            progress=progress,
            ball=Circle(_BALL_HOME, 40),
            respawn_in=0.0,
            dragging=False,
            bites=0,
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.progress.update(context.time.delta)

        # No camera, so the mouse is already in the space the shapes are in.
        var mouse = context.input.mouse

        # A pac-man wider than a half turn: its mouth is the missing wedge,
        # outside it, so the mouse there touches nothing. The mouth is a
        # sector of its own, the rest of the turn.
        var chew = context.time.elapsed * _CHEW
        var gape = 0.4 + 0.35 * abs(sin(chew))
        var pacman = Sector((420, 60), 150, gape, tau - 2.0 * gape)
        var mouth = Sector(pacman.position, pacman.r, -gape, 2.0 * gape)

        if self.respawn_in > 0.0:
            self.respawn_in -= context.time.delta
            if self.respawn_in <= 0.0:
                self.respawn_in = 0.0
                self.ball.move_to(_BALL_HOME)
        var eaten = self.respawn_in > 0.0

        if not eaten:
            if context.input.mouse_pressed() and self.ball.contains(mouse):
                self.dragging = True
            if context.input.mouse_released():
                self.dragging = False
            if self.dragging:
                self.ball.move_to(mouse)

        # The mouth is most shut where the sine crosses zero, once per bite:
        # a ball let go in it then is swallowed; one still held is safe.
        var bites = Int(chew / pi)
        if bites != self.bites:
            self.bites = bites
            if (
                not eaten
                and not self.dragging
                and mouth.contains(self.ball.center())
            ):
                self.respawn_in = _RESPAWN

        canvas.background(_BACKGROUND)
        canvas.fill_enabled(False)

        # Two progress rings off one tween. Angles count counter-clockwise
        # from +x because y is up, so the clockwise ring (blue, like a
        # clock's hand) starts at the top and sweeps negatively.
        var sweep = tau * self.progress.value
        var ring = Point2D(-440.0, 120.0)
        canvas.outline(Color(62, 64, 82), thickness=14)
        canvas.arc(ring, 90, 0.0, tau)
        canvas.arc(ring + Vector2D(0, -270), 90, 0.0, tau)
        canvas.outline(Color(90, 170, 255), thickness=14)
        canvas.arc(ring, 90, pi / 2.0, -sweep)
        canvas.outline(Color(235, 120, 70))
        canvas.arc(ring + Vector2D(0, -270), 90, pi / 2.0, sweep)

        # A pie chart: slices laid clockwise from the top. The one under the
        # mouse slides out along the middle of its sweep.
        canvas.outline(_BACKGROUND, thickness=3)
        var shares = _shares()
        var start = pi / 2.0
        for i in range(len(shares)):
            var slice = Sector(_PIE, _PIE_RADIUS, start, -tau * shares[i])
            if slice.contains(mouse):
                var middle = start - pi * shares[i]
                slice.translate(Vector2D(cos(middle), sin(middle)) * _POP)
            canvas.fill(_slice_color(i))
            canvas.sector(slice)
            start = slice.end_angle()

        var body = Color(250, 200, 40)
        if pacman.contains(mouse):
            body = Color(255, 255, 255)
        var hit = self.respawn_in == 0.0 and overlaps(pacman, self.ball)
        with canvas.style(
            fill=body,
            outline=Color(235, 120, 70) if hit else _BACKGROUND,
            outline_thickness=6,
            shadow=Color(0, 0, 0, 170),
            shadow_offset=Vector2D(8, -12),
            shadow_blur=20,
        ):
            canvas.sector(pacman)

        if self.respawn_in == 0.0:
            canvas.outline_enabled(False)
            canvas.fill(Color(90, 170, 255))
            canvas.circle(self.ball)

        canvas.text_color(Color(200, 200, 212))
        canvas.font_size(30)
        canvas.text_align(Align.TOP)
        canvas.text("Arcs and Sectors", (0, 362))
        canvas.font_size(18)
        canvas.text(
            "hover the pie and the pac-man; feed it the blue ball.",
            (0, 322),
        )


def main() raises:
    run[App]("Arcs and Sectors", width=1280, height=800)
