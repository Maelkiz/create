"""The Create logo, built up on screen.

First the Sierpinski triangle appears in points, by the chaos game: start at a
corner, then keep moving halfway towards a randomly picked corner. Then the
logo's small triangles grow in place over it, one after another, each on its
own easing curve. The animation is recorded to `out/logo.gif`.
"""

from std.os import makedirs

from create import *


comptime _SIDE = 640.0
comptime _PAPER = Color(253, 253, 250)

comptime _POINTS_PER_FRAME = 1000
comptime _MAX_POINTS = 240_000
"""Where the points stop."""
comptime _GROW_POINTS = 40_000
"""Where the triangles start to grow, while the points carry on."""
comptime _DURATION = 2.5
"""Seconds each triangle takes to grow to its full size."""
comptime _STAGGER = 0.25
"""Seconds between one triangle starting to grow and the next."""
comptime _HOLD_SECONDS = 2.5
"""How long the recording keeps the finished logo on screen."""


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
    """One small triangle and its growth."""

    var shape: Triangle
    """The triangle around its own centre, placed by the transform."""
    var home: Point2D
    """Where its centre sits, and what it grows from."""
    var color: Color
    var tween: Tween
    var delay: Float64
    """Seconds after the start before it starts to grow."""


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
    """Seconds since the triangles started to grow."""
    var shown: Float64
    """Seconds the finished logo has been on screen."""

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
            var curve = curves[i % len(curves)]
            var duration = _DURATION
            # The last, bottom-right triangle would bounce; let it ease in,
            # and quicker, so the logo doesn't wait on it.
            if i == len(triangles) - 1:
                curve = Easing.OUT_SINE
                duration = _DURATION * 0.6
            pieces.append(
                _Piece(
                    shape=triangles[i].translate(-Vector2D(home)),
                    home=home,
                    color=triangle_colors[i],
                    tween=Tween(duration, curve),
                    delay=Float64(i) * _STAGGER,
                )
            )
        var layer = Canvas(
            canvas.width(), canvas.height(), antialiasing=Antialiasing.OFF
        )
        var picture = layer.snapshot()
        # Saving into a folder that isn't there fails, so make it first.
        makedirs(source_path("out"), exist_ok=True)
        canvas.start_recording(source_path("out/logo.gif"))
        return Logo(
            pieces=pieces^,
            random=Random(),
            point=_corner(0, 0),
            layer=layer^,
            picture=picture^,
            count=0,
            elapsed=0.0,
            shown=0.0,
        )

    def random_corner(mut self) -> Point2D:
        var pick = self.random.int(0, 3)
        if pick == 0:
            return _corner(0, 0)
        if pick == 1:
            return _corner(4, 0)
        return _corner(4, 4)

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
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
        if self.count >= _GROW_POINTS:
            self.elapsed += context.time.delta

        var landed = True
        for ref piece in self.pieces:
            if (
                self.count >= _GROW_POINTS
                and self.elapsed >= piece.delay
                and not piece.tween.is_playing()
                and not piece.tween.is_finished()
            ):
                piece.tween.play()
            piece.tween.update(context.time.delta)
            landed = landed and piece.tween.is_finished()
        if landed:
            self.shown += context.time.delta
            if canvas.recording() and self.shown >= _HOLD_SECONDS:
                canvas.stop_recording()

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
            # grows a little too big and shrinks back; IN_OUT_BACK dips below
            # 0 first, which would turn it inside out, so hold it at nothing.
            var size = max(piece.tween.value(), 0.0)
            with canvas.transform(
                translate(Vector2D(piece.home)) @ scale(size)
            ):
                canvas.fill(piece.color)
                canvas.draw(piece.shape)


def main() raises:
    # Hard edges, pixel for pixel like the points'.
    run[Logo]("Logo", width=1280, height=720, antialiasing=Antialiasing.OFF)
