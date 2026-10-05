"""Clip state shared by both replays: what a `canvas.clip` recorded, and the
CPU replay's per-row form of it.

A clip is a region recorded as an ordinary `RenderCommand` (a solid white
fill, nothing else), so each replay rasterises it with exactly the code that
renders the same shape: the CPU through its own rasteriser in span-recording
mode, on the antialiasing grid, the GPU through the fill emitters into the
multisampled stencil buffer. A clip and a `canvas.rectangle` of the same
`Rectangle` cover the same pixels, edges included.
"""

from std.math import max, min

from ._command import RenderCommand
from create.color.color import Color
from .style import Style


def clip_style() -> Style:
    """The style a clip region is recorded in: an opaque solid fill and
    nothing else, so its rasterisation covers exactly the shape's interior.
    """
    var s = Style()
    s.fill_color = Color.WHITE
    s.fill_enabled = True
    s.outline_enabled = False
    return s


struct _Clip(Copyable, Movable):
    """One level of the clip stack, as `canvas.clip` recorded it.

    `region` is local geometry plus the transform current at the `clip`
    call, so the clip is frozen there like any command. `parent` is the id of
    the clip it was nested in (0 for none); every command records the id of
    the innermost clip it was rendered under, and the replay intersects the
    chain.
    """

    var region: RenderCommand
    var invert: Bool
    """Keep what lies outside `region` instead of inside it."""
    var parent: Int

    def __init__(
        out self, var region: RenderCommand, invert: Bool, parent: Int
    ):
        self.region = region^
        self.invert = invert
        self.parent = parent


struct _ClipRows(Movable):
    """A clip as half-open column runs per device row, each with how much of
    its pixels the clip keeps: row `y` keeps `[spans[2k], spans[2k + 1])` by
    `covers[k]` (1 to 255, 255 whole) for `k` in `starts[y] ..< starts[y +
    1]`, sorted and disjoint.

    What the CPU raster loops test against: a row's runs are found by index,
    a `fill_span` is cut into one call per run it overlaps, and a partly
    kept run scales the alpha it paints — the clip's antialiased edge.
    """

    var starts: List[Int]
    var spans: List[Int]
    var covers: List[Int]

    def __init__(out self, height: Int):
        """No runs on any row: everything clipped away."""
        self.starts = List[Int](length=height + 1, fill=0)
        self.spans = List[Int]()
        self.covers = List[Int]()

    def __init__(
        out self,
        recorded: List[Int],
        width: Int,
        height: Int,
        invert: Bool,
        grid: Int = 1,
    ):
        """The runs a region's rasterisation recorded, as `(row, lo, hi,
        key)` quadruples in any order, possibly overlapping, on a surface
        `grid` times finer along each axis: merged, each pixel kept by the
        share of its `grid * grid` samples they cover, and complemented
        within `[0, width)` if `invert`. The paint key is ignored."""
        var fine = _ClipRows._merged(recorded, height * grid)
        var full = grid * grid
        # Coverage changes per column, as `composite_coverage` keeps them.
        var changes = List[Int](length=width + 2, fill=0)
        var stamps = List[Int](length=width + 2, fill=-1)
        var touched = List[Int]()

        self.starts = List[Int](capacity=height + 1)
        self.spans = List[Int]()
        self.covers = List[Int]()
        for y in range(height):
            self.starts.append(len(self.covers))
            touched.clear()

            @always_inline
            def change(column: Int, delta: Int) capturing:
                if delta == 0:
                    return
                changes[column] += delta
                if stamps[column] != y:
                    stamps[column] = y
                    touched.append(column)

            for sub in range(y * grid, (y + 1) * grid):
                for k in range(fine.starts[sub], fine.starts[sub + 1]):
                    var lo = fine.spans[2 * k]
                    var hi = fine.spans[2 * k + 1]
                    var first = lo // grid
                    var last = (hi - 1) // grid
                    if first == last:
                        change(first, hi - lo)
                        change(first + 1, lo - hi)
                        continue
                    var head = (first + 1) * grid - lo
                    var tail = hi - last * grid
                    change(first, head)
                    change(first + 1, grid - head)
                    change(last, tail - grid)
                    change(last + 1, -tail)
            sort(touched)
            var samples = 0
            var cursor = 0
            for i in range(len(touched)):
                var x = touched[i]
                samples += changes[x]
                changes[x] = 0
                var end = touched[i + 1] if i + 1 < len(touched) else x
                if samples <= 0 or end <= x:
                    continue
                var cover = samples * 255 // full
                if invert:
                    if x > cursor:
                        self._append(cursor, x, 255)
                    if cover < 255:
                        self._append(x, end, 255 - cover)
                    cursor = end
                else:
                    self._append(x, end, cover)
            if invert and cursor < width:
                self._append(cursor, width, 255)
        self.starts.append(len(self.covers))

    @staticmethod
    def _merged(recorded: List[Int], height: Int) -> _ClipRows:
        """`recorded`'s runs bucketed by row, sorted and merged where they
        touch, all kept whole."""
        # Bucket the runs by row, counting first so one pass places them.
        var counts = List[Int](length=height + 1, fill=0)
        for i in range(0, len(recorded), 4):
            counts[recorded[i] + 1] += 1
        for y in range(height):
            counts[y + 1] += counts[y]
        var by_row = List[Int](length=len(recorded) // 4 * 2, fill=0)
        var fill_at = counts.copy()
        for i in range(0, len(recorded), 4):
            var at = fill_at[recorded[i]]
            by_row[2 * at] = recorded[i + 1]
            by_row[2 * at + 1] = recorded[i + 2]
            fill_at[recorded[i]] = at + 1

        var out = _ClipRows(0)
        out.starts = List[Int](capacity=height + 1)
        out.spans = List[Int](capacity=len(by_row))
        for y in range(height):
            out.starts.append(len(out.covers))
            var first = counts[y]
            var end = counts[y + 1]
            # Insertion sort by `lo`: a row of a shape holds a handful.
            for i in range(first + 1, end):
                var lo = by_row[2 * i]
                var hi = by_row[2 * i + 1]
                var j = i - 1
                while j >= first and by_row[2 * j] > lo:
                    by_row[2 * j + 2] = by_row[2 * j]
                    by_row[2 * j + 3] = by_row[2 * j + 1]
                    j -= 1
                by_row[2 * j + 2] = lo
                by_row[2 * j + 3] = hi
            var i = first
            while i < end:
                var lo = by_row[2 * i]
                var hi = by_row[2 * i + 1]
                i += 1
                while i < end and by_row[2 * i] <= hi:
                    hi = max(hi, by_row[2 * i + 1])
                    i += 1
                out._append(lo, hi, 255)
        out.starts.append(len(out.covers))
        return out^

    def _append(mut self, lo: Int, hi: Int, cover: Int):
        """Add a run to the row being built, joining the one before it when
        they touch and keep alike."""
        var n = len(self.covers)
        if (
            n > self.starts[len(self.starts) - 1]
            and self.spans[2 * n - 1] == lo
            and self.covers[n - 1] == cover
        ):
            self.spans[2 * n - 1] = hi
            return
        self.spans.append(lo)
        self.spans.append(hi)
        self.covers.append(cover)

    def intersect(self, other: _ClipRows) -> _ClipRows:
        """The runs inside both, row by row, kept by the product of both
        covers — a nested clip."""
        var height = len(self.starts) - 1
        var out = _ClipRows(height)
        out.starts.clear()
        for y in range(height):
            out.starts.append(len(out.covers))
            var a = self.starts[y]
            var a_end = self.starts[y + 1]
            var b = other.starts[y]
            var b_end = other.starts[y + 1]
            while a < a_end and b < b_end:
                var lo = max(self.spans[2 * a], other.spans[2 * b])
                var a_hi = self.spans[2 * a + 1]
                var b_hi = other.spans[2 * b + 1]
                var hi = min(a_hi, b_hi)
                var cover = (self.covers[a] * other.covers[b] + 127) // 255
                if hi > lo and cover > 0:
                    out._append(lo, hi, cover)
                if a_hi < b_hi:
                    a += 1
                else:
                    b += 1
        out.starts.append(len(out.covers))
        return out^
