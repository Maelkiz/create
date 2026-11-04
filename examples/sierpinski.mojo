"""The Create logo, drawn in points with the chaos game: Pascal's triangle
by parity, the Sierpinski triangle. `logo.mojo` draws it plainly.

The logo is Pascal's triangle, rows 0 to 3, laid out as a triangle of
sixteen small triangles: the ten pointing up are its entries, black where
the entry is odd and white where it is even (the 2 in row 2), and the six
pointing down between them are the coloured gaps. Each of the sixteen is a
`Triangle` value, and a point's colour is that of the one which `contains`
it.

The chaos game moves a point halfway towards a corner picked at random, and
each move shrinks the whole logo by half into that corner. Here every point
starts somewhere random in the logo, takes the colour there, then makes two
moves: each odd entry of the big triangle ends up holding the whole logo in
miniature, and the even entry and the gaps stay empty, as in Pascal's
triangle taken one level deeper.

Random points cover the last few specks only slowly, so once most of the
logo is drawn the miniature triangles fade in as solid shapes to finish it.

Press any key to draw it again.
"""

from create import *


comptime _SIDE = 640.0
"""The logo's side, in design units."""
comptime _ROWS = 4
comptime _STEPS = 2
"""Halfway moves per point: each one shrinks the logo by half into a corner,
so 2 puts a quarter-size logo in every odd entry."""
comptime _POINTS_PER_FRAME = 4000
comptime _MAX_POINTS = 400_000
"""Where the points stop and the shapes take over: about 98% of the logo is
covered by then."""
comptime _FADE_SECONDS = 0.6
"""How long the shapes take to fade in over the points."""

comptime _PAPER = Color(253, 253, 250)
"""The logo's background, and the colour of its even entry."""


def _corner(row: Int, index: Int) -> Point2D:
    """Corner `index` of the grid line `row`, counted down from the apex."""
    var height = _SIDE * sqrt(3.0) / 2.0
    var step = _SIDE / Float64(_ROWS)
    return Point2D(
        (Float64(index) - Float64(row) / 2.0) * step,
        height / 2.0 - Float64(row) * height / Float64(_ROWS),
    )


def _is_odd_binomial(n: Int, k: Int) -> Bool:
    """Whether `n` choose `k` is odd (Lucas' theorem: every bit of `k` is set
    in `n`)."""
    return (n & k) == k


def _halfway(t: Triangle, corner: Point2D) -> Triangle:
    """`t` moved halfway towards `corner`, as a point of the chaos game is."""
    return Triangle(
        t.a.lerp(corner, 0.5), t.b.lerp(corner, 0.5), t.c.lerp(corner, 0.5)
    )


@fieldwise_init
struct Sierpinski(Program):
    var outline: Triangle
    """The whole logo; the chaos game's corners are its corners."""
    var cells: List[Triangle]
    """The sixteen triangles, each paired with its colour in `colors`."""
    var colors: List[Color]
    var pieces: List[Triangle]
    """Every cell after the `_STEPS` moves, by every route: the miniature
    logos, as shapes. Piece `i` is cell `i % len(cells)`."""
    var random: Random
    var layer: Canvas
    """The points so far, transparent between them."""
    var picture: Image
    """`layer` as last read."""
    var count: Int
    var fade: Float64
    """How far the shapes have faded in, 0 to 1."""

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Sierpinski:
        var cells = List[Triangle]()
        var colors = List[Color]()
        # Pascal's entries, pointing up: black when odd, white when even.
        for row in range(_ROWS):
            for index in range(row + 1):
                cells.append(
                    Triangle(
                        _corner(row, index),
                        _corner(row + 1, index),
                        _corner(row + 1, index + 1),
                    )
                )
                var odd = _is_odd_binomial(row, index)
                colors.append(Color.BLACK if odd else _PAPER)
        # The gaps between them, pointing down, coloured row by row.
        var gap_colors: List[Color] = [
            Color.RED,
            Color.YELLOW,
            Color.MAGENTA,
            Color.GREEN,
            Color.CYAN,
            Color.BLUE,
        ]
        var next_color = 0
        for row in range(1, _ROWS):
            for index in range(row):
                cells.append(
                    Triangle(
                        _corner(row, index),
                        _corner(row, index + 1),
                        _corner(row + 1, index + 1),
                    )
                )
                colors.append(gap_colors[next_color])
                next_color += 1

        var outline = Triangle(
            _corner(0, 0), _corner(_ROWS, 0), _corner(_ROWS, _ROWS)
        )
        # Each move sends the logo into every corner at once, so the pieces
        # triple per move, the sixteen cells repeating in order.
        var pieces = cells.copy()
        for _ in range(_STEPS):
            var moved = List[Triangle]()
            for corner in [outline.a, outline.b, outline.c]:
                for piece in pieces:
                    moved.append(_halfway(piece, corner))
            pieces = moved^

        var layer = Canvas(
            canvas.width(), canvas.height(), antialiasing=Antialiasing.OFF
        )
        var picture = layer.snapshot()
        return Sierpinski(
            outline=outline,
            cells=cells^,
            colors=colors^,
            pieces=pieces^,
            random=Random(),
            layer=layer^,
            picture=picture^,
            count=0,
            fade=0.0,
        )

    def cell_at(self, p: Point2D) -> Int:
        """The index of the cell that contains `p`, or -1 outside the logo."""
        for i in range(len(self.cells)):
            if self.cells[i].contains(p):
                return i
        return -1

    def random_corner(mut self) -> Point2D:
        var pick = self.random.int(0, 3)
        if pick == 0:
            return self.outline.a
        if pick == 1:
            return self.outline.b
        return self.outline.c

    def random_point(mut self) -> Point2D:
        """A point anywhere in the logo, every spot equally likely."""
        var u = self.random.float()
        var v = self.random.float()
        if u + v > 1.0:
            # Outside the triangle: fold back across its diagonal.
            u = 1.0 - u
            v = 1.0 - v
        var a = self.outline.a
        return a + (self.outline.b - a) * u + (self.outline.c - a) * v

    def restart(mut self) raises:
        self.layer.clear()
        self.picture = self.layer.snapshot()
        self.count = 0
        self.fade = 0.0

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # `key` is the last key pressed, and pressed only in the frame it
        # went down: so this is any key, this frame.
        if context.input.key_pressed(context.input.key):
            self.restart()

        if self.count < _MAX_POINTS:
            self.layer.outline_enabled(False)
            for _ in range(_POINTS_PER_FRAME):
                var p = self.random_point()
                var cell = self.cell_at(p)
                for _ in range(_STEPS):
                    p = p.lerp(self.random_corner(), 0.5)
                if cell >= 0:
                    self.layer.fill(self.colors[cell])
                    self.layer.rectangle(p, 1, 1)
            self.count += _POINTS_PER_FRAME
            self.picture = self.layer.snapshot()
        else:
            self.fade = min(self.fade + context.time.delta / _FADE_SECONDS, 1.0)

        canvas.background(_PAPER)
        canvas.image(self.picture, (0, 0), canvas.width(), canvas.height())
        if self.fade > 0.0:
            # Over the points, in their own colours: only the specks they
            # missed change.
            with canvas.style(outline_enabled=False, opacity=self.fade):
                for i in range(len(self.pieces)):
                    canvas.fill(self.colors[i % len(self.cells)])
                    canvas.draw(self.pieces[i])


def main() raises:
    run[Sierpinski]("Sierpinski", width=800, height=800)
