"""Clip state shared by both replays: what a `canvas.clip` recorded, and the
CPU replay's per-row form of it.

A clip is a region recorded as an ordinary `RenderCommand` (a solid white
fill, nothing else), so each replay rasterises it with exactly the code that
renders the same shape: the CPU through its own rasteriser in span-recording
mode, the GPU through the fill emitters into the stencil buffer. A clip and a
`canvas.rectangle` of the same `Rectangle` cover the same pixels.
"""

from std.math import max, min

from ._command import RenderCommand
from .color import Color
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
    """A hard clip as half-open column runs per device row: row `y` keeps
    `[spans[2k], spans[2k + 1])` for `k` in `starts[y] ..< starts[y + 1]`,
    sorted and disjoint.

    What the CPU raster loops test against: a row's runs are found by index,
    and a `fill_span` is cut into one call per run it overlaps.
    """

    var starts: List[Int]
    var spans: List[Int]

    def __init__(out self, height: Int):
        """No runs on any row: everything clipped away."""
        self.starts = List[Int](length=height + 1, fill=0)
        self.spans = List[Int]()

    def __init__(
        out self,
        recorded: List[Int],
        width: Int,
        height: Int,
        invert: Bool,
    ):
        """The runs a region's rasterisation recorded, as `(row, lo, hi)`
        triples in any order, possibly overlapping: sorted, merged, and
        complemented within `[0, width)` if `invert`."""
        # Bucket the triples by row, counting first so one pass places them.
        var counts = List[Int](length=height + 1, fill=0)
        for i in range(0, len(recorded), 3):
            counts[recorded[i] + 1] += 1
        for y in range(height):
            counts[y + 1] += counts[y]
        var by_row = List[Int](length=len(recorded) // 3 * 2, fill=0)
        var fill_at = counts.copy()
        for i in range(0, len(recorded), 3):
            var at = fill_at[recorded[i]]
            by_row[2 * at] = recorded[i + 1]
            by_row[2 * at + 1] = recorded[i + 2]
            fill_at[recorded[i]] = at + 1

        self.starts = List[Int](capacity=height + 1)
        self.spans = List[Int](capacity=len(by_row))
        for y in range(height):
            self.starts.append(len(self.spans) // 2)
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
            # Merge touching runs, complementing as they are emitted.
            var cursor = 0
            var i = first
            while i < end:
                var lo = by_row[2 * i]
                var hi = by_row[2 * i + 1]
                i += 1
                while i < end and by_row[2 * i] <= hi:
                    hi = max(hi, by_row[2 * i + 1])
                    i += 1
                if invert:
                    if lo > cursor:
                        self._append(cursor, lo)
                    cursor = max(cursor, hi)
                else:
                    self._append(lo, hi)
            if invert and cursor < width:
                self._append(cursor, width)
        self.starts.append(len(self.spans) // 2)

    def _append(mut self, lo: Int, hi: Int):
        self.spans.append(lo)
        self.spans.append(hi)

    def intersect(self, other: _ClipRows) -> _ClipRows:
        """The runs inside both, row by row — a nested clip."""
        var height = len(self.starts) - 1
        var out = _ClipRows(height)
        out.starts.clear()
        for y in range(height):
            out.starts.append(len(out.spans) // 2)
            var a = self.starts[y]
            var a_end = self.starts[y + 1]
            var b = other.starts[y]
            var b_end = other.starts[y + 1]
            while a < a_end and b < b_end:
                var lo = max(self.spans[2 * a], other.spans[2 * b])
                var a_hi = self.spans[2 * a + 1]
                var b_hi = other.spans[2 * b + 1]
                var hi = min(a_hi, b_hi)
                if hi > lo:
                    out._append(lo, hi)
                if a_hi < b_hi:
                    a += 1
                else:
                    b += 1
        out.starts.append(len(out.spans) // 2)
        return out^
