"""The Create logo: a black triangle cut into four rows of smaller ones, with
the six pointing down in colour and the middle one left white.

Each small triangle flies in from off screen, spinning, one after another,
and each on a different easing curve. Press any key to play it again.

`sierpinski.mojo` builds the same logo out of points.
"""

from create import *


comptime _SIDE = 640.0
comptime _PAPER = Color(253, 253, 250)

comptime _DURATION = 1.2
"""Seconds each triangle takes to fly in."""
comptime _STAGGER = 0.25
"""Seconds between one triangle setting off and the next."""
comptime _DISTANCE = 900.0
"""How far out each triangle starts: past the corner of the 800x800 screen."""


def _corner(row: Int, index: Int) -> Point2D:
    """Corner `index` along grid line `row`, counting rows down from the apex
    (0) to the base (4)."""
    var step = _SIDE / 4.0
    var height = _SIDE * sqrt(3.0) / 2.0
    return Point2D(
        (Float64(index) - Float64(row) / 2.0) * step,
        height / 2.0 - Float64(row) * height / 4.0,
    )


@fieldwise_init
struct _Piece(Copyable):
    """One small triangle and its flight."""

    var shape: Triangle
    """The triangle around its own centre, placed by the transform."""
    var home: Point2D
    """Where its centre lands."""
    var start: Point2D
    var spin: Float64
    """The turn it makes on the way, in radians."""
    var color: Color
    var tween: Tween
    var delay: Float64
    """Seconds after the start before it sets off."""


@fieldwise_init
struct Logo(Program):
    var pieces: List[_Piece]
    var elapsed: Float64

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Logo:
        var curves: List[Easing] = [
            Easing.OUT_BACK,
            Easing.OUT_ELASTIC,
            Easing.OUT_BOUNCE,
            Easing.OUT_EXPO,
            Easing.OUT_CUBIC,
            Easing.IN_OUT_BACK,
        ]
        var colors: List[Color] = [
            Color.RED,
            Color.YELLOW,
            Color.MAGENTA,
            Color.GREEN,
            Color.CYAN,
            Color.BLUE,
        ]
        # Row by row from the apex, left to right, each pointing-down
        # triangle between the two pointing up on either side of it.
        var triangles = List[Triangle]()
        var triangle_colors = List[Color]()
        var next_color = 0
        for row in range(4):
            for index in range(row + 1):
                if index > 0:
                    triangles.append(
                        Triangle(
                            _corner(row, index - 1),
                            _corner(row, index),
                            _corner(row + 1, index),
                        )
                    )
                    triangle_colors.append(colors[next_color])
                    next_color += 1
                # The middle of row 2 is the logo's white gap.
                if row == 2 and index == 1:
                    continue
                triangles.append(
                    Triangle(
                        _corner(row, index),
                        _corner(row + 1, index),
                        _corner(row + 1, index + 1),
                    )
                )
                triangle_colors.append(Color.BLACK)

        var pieces = List[_Piece]()
        for i in range(len(triangles)):
            var home = triangles[i].center()
            var outward = Vector2D(home).normalize()
            pieces.append(
                _Piece(
                    shape=triangles[i].translate(-Vector2D(home)),
                    home=home,
                    start=home + outward * _DISTANCE,
                    spin=PI if i % 2 == 0 else -PI,
                    color=triangle_colors[i],
                    tween=Tween(_DURATION, curves[i % len(curves)]),
                    delay=Float64(i) * _STAGGER,
                )
            )
        return Logo(pieces=pieces^, elapsed=0.0)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # `key` is the last key pressed, and pressed only in the frame it
        # went down: so this is any key, this frame.
        if context.input.key_pressed(context.input.key):
            self.elapsed = 0.0
            for ref piece in self.pieces:
                piece.tween.stop()

        self.elapsed += context.time.delta
        var landed = True
        for ref piece in self.pieces:
            if (
                self.elapsed >= piece.delay
                and not piece.tween.is_playing()
                and not piece.tween.is_finished()
            ):
                piece.tween.play()
            piece.tween.update(context.time.delta)
            landed = landed and piece.tween.is_finished()

        canvas.background(_PAPER)
        canvas.outline_enabled(False)
        if landed:
            # Under the landed pieces, so no seam shows where two meet.
            canvas.fill(Color.BLACK)
            canvas.triangle(_corner(0, 0), _corner(4, 0), _corner(4, 4))
            canvas.fill(_PAPER)
            canvas.triangle(_corner(2, 1), _corner(3, 1), _corner(3, 2))
        for piece in self.pieces:
            if not piece.tween.is_playing() and not piece.tween.is_finished():
                continue
            # Eased curves like OUT_BACK run past 1 on the way, so the piece
            # overshoots its home and turns back a little.
            var t = piece.tween.value()
            var position = piece.start.lerp(piece.home, t)
            var angle = piece.spin * (1.0 - t)
            with canvas.transform(
                translate(Vector2D(position)) @ rotate(angle)
            ):
                canvas.fill(piece.color)
                canvas.draw(piece.shape)


def main() raises:
    run[Logo]("Logo", width=800, height=800)
