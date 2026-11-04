"""The Create logo: a black triangle cut into four rows of smaller ones, with
the six pointing down in colour and the middle one left white.

The logo is Pascal's triangle, rows 0 to 3, by parity: the triangles
pointing up are its entries, black where the entry is odd and white where it
is even. Pascal's triangle by parity, carried on forever, is the Sierpinski
triangle, so that is drawn first, in points, with the chaos game: start at a
corner, then over and over move halfway towards a corner picked at random.

Then each small triangle of the logo flies in over it from off screen,
spinning, one after another, and each on a different easing curve. Press any
key to play it again.
"""

from create import *


comptime _SIDE = 640.0
comptime _PAPER = Color(253, 253, 250)

comptime _POINTS_PER_FRAME = 2000
comptime _MAX_POINTS = 240_000
"""Where the points stop and the triangles set off."""
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
    var random: Random
    var point: Point2D
    """The chaos game's current position."""
    var layer: Canvas
    """The points so far, transparent between them."""
    var picture: Image
    """`layer` as last read."""
    var count: Int
    var elapsed: Float64
    """Seconds since the points stopped and the triangles set off."""

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
        var layer = Canvas(
            canvas.width(), canvas.height(), antialiasing=Antialiasing.OFF
        )
        var picture = layer.snapshot()
        return Logo(
            pieces=pieces^,
            random=Random(),
            point=_corner(0, 0),
            layer=layer^,
            picture=picture^,
            count=0,
            elapsed=0.0,
        )

    def random_corner(mut self) -> Point2D:
        var pick = self.random.int(0, 3)
        if pick == 0:
            return _corner(0, 0)
        if pick == 1:
            return _corner(4, 0)
        return _corner(4, 4)

    def restart(mut self) raises:
        self.layer.clear()
        self.picture = self.layer.snapshot()
        self.point = _corner(0, 0)
        self.count = 0
        self.elapsed = 0.0
        for ref piece in self.pieces:
            piece.tween.stop()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # `key` is the last key pressed, and pressed only in the frame it
        # went down: so this is any key, this frame.
        if context.input.key_pressed(context.input.key):
            self.restart()

        if self.count < _MAX_POINTS:
            # A point on the logo's edge would stick half a pixel out past
            # it, and nothing drawn later covers the outside: clip to it.
            var outline = Triangle(_corner(0, 0), _corner(4, 0), _corner(4, 4))
            with self.layer.clip(outline):
                with self.layer.style(fill=Color.BLACK, outline_enabled=False):
                    for _ in range(_POINTS_PER_FRAME):
                        self.point = self.point.lerp(self.random_corner(), 0.5)
                        self.layer.rectangle(self.point, 1, 1)
            self.count += _POINTS_PER_FRAME
            self.picture = self.layer.snapshot()
        else:
            self.elapsed += context.time.delta

        var landed = True
        for ref piece in self.pieces:
            if (
                self.count >= _MAX_POINTS
                and self.elapsed >= piece.delay
                and not piece.tween.is_playing()
                and not piece.tween.is_finished()
            ):
                piece.tween.play()
            piece.tween.update(context.time.delta)
            landed = landed and piece.tween.is_finished()

        canvas.background(_PAPER)
        canvas.image(self.picture, (0, 0), canvas.width(), canvas.height())
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
    # Hard edges, pixel for pixel like the points'.
    run[Logo]("Logo", width=800, height=800, antialiasing=Antialiasing.OFF)
