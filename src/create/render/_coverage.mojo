"""Antialiasing on the CPU: a shape's coverage from its own rasteriser.

The replay draws an antialiased shape onto a *recording* surface `grid`
times finer along each axis, so the shape's own code decides which samples
it covers — the same pixel-centre rules, now at sample centres — and no
rasteriser knows antialiasing exists. `composite_coverage` then counts, for
each pixel, how many of its `grid * grid` samples each paint covered, and
composites the pixel once.

Once matters. A shape's fill and outline never overlap, at any resolution,
so where both cross a pixel their coverages add up and the pixel is mixed
from both before it is blended: there is no seam of background between the
two, and a translucent shape stays evenly translucent. Two separate shapes
meeting inside a pixel each blend their own share, so a seam can show where
they meet off a pixel boundary; on a boundary, both cover whole pixels.

Fully covered stretches of a row go through `fill_span` together, so a
shape's interior costs what it did without antialiasing; the cost is in
rasterising `grid` times the rows and in the edge pixels.
"""

from std.math import max, min, sqrt

from create.color.color import Color
from ._raster import FillPaint, GRADIENT_KEY, _key_color, blend, fill_span
from .surface import Surface


struct CoverageScratch(Movable):
    """The buffers `composite_coverage` works in, kept between shapes so a
    frame of them allocates once."""

    var keys: List[Int]
    var paints: List[FillPaint]
    var starts: List[Int]
    var order: List[Int]
    var changes: List[Int]
    var stamps: List[Int]
    var touched: List[Int]
    var coverage: List[Int]

    def __init__(out self):
        self.keys = List[Int]()
        self.paints = List[FillPaint]()
        self.starts = List[Int]()
        self.order = List[Int]()
        self.changes = List[Int]()
        self.stamps = List[Int]()
        self.touched = List[Int]()
        self.coverage = List[Int]()


def _paint_at(paint: FillPaint, x: Int, y: Int) -> Color:
    """The colour `paint` gives pixel `(x, y)`, sampled at its centre as
    `fill_span` would."""
    if not paint.shader:
        return paint.color
    ref shader = paint.shader.value()
    ref m = shader.mapping
    var xc = Float64(x) + 0.5
    var yc = Float64(y) + 0.5
    var u = m.u[0] * xc + m.u[1] * yc + m.u[2]
    var v = m.v[0] * xc + m.v[1] * yc + m.v[2]
    var t = sqrt(u * u + v * v) if m.radial else u
    return shader.gradient._sample(t, x, y)


def _mixed(
    paints: List[FillPaint],
    coverage: List[Int],
    full: Int,
    x: Int,
    y: Int,
) -> Color:
    """Pixel `(x, y)` partly covered by each paint as `coverage` says: the
    paints mixed by their share of the samples, premultiplied, and as
    opaque as the share they cover together."""
    if len(paints) == 1:
        var c = _paint_at(paints[0], x, y)
        return Color(c.r, c.g, c.b, UInt8(Int(c.a) * coverage[0] // full))
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var weight = 0.0
    for k in range(len(paints)):
        var samples = coverage[k]
        if samples <= 0:
            continue
        var c = _paint_at(paints[k], x, y)
        var w = Float64(samples) * Float64(c.a)
        red += w * Float64(c.r)
        green += w * Float64(c.g)
        blue += w * Float64(c.b)
        weight += w
    if weight <= 0.0:
        return Color.TRANSPARENT
    return Color(
        UInt8(Int(red / weight + 0.5)),
        UInt8(Int(green / weight + 0.5)),
        UInt8(Int(blue / weight + 0.5)),
        UInt8(Int(min(weight / Float64(full), 255.0) + 0.5)),
    )


def _ensure(mut list: List[Int], length: Int):
    """`list` at least `length` long, so it can be written through its
    pointer."""
    while len(list) < length:
        list.append(0)


def composite_coverage[
    o: Origin[mut=True]
](
    s: Surface[o],
    mut runs: List[Int],
    grid: Int,
    fill: FillPaint,
    mut scratch: CoverageScratch,
):
    """Composite the shape recorded in `runs` onto `s`, antialiased.

    `runs` holds `(row, lo, hi, key)` quadruples from a recording surface
    `grid` times the size of `s` along each axis — `grid` a power of two —
    a key naming each run's paint (`fill` for `GRADIENT_KEY`); the keys are
    overwritten. A pixel's coverage by a paint is the samples of its
    `grid * grid` that the paint's runs cover.

    Each run adds to its pixel row where its coverage changes: up by its
    partial samples at its first pixel, to `grid` from the next, and back
    down at its last — into a difference array per paint, noting each
    column it touches. Sorted, the touched columns split the row into
    stretches of constant coverage, so a stretch costs one `fill_span`
    whatever its length — the interior in one run, a long shallow edge in a
    few — and only a gradient's partial stretches go pixel by pixel. Reading
    a column back clears it, ready for the next row.

    The loops index through pointers, as the raster loops do: bounds-checked
    `List` access cost as much as the compositing.
    """
    var count = len(runs) // 4
    if count == 0:
        return
    var full = grid * grid
    var shift = 0
    while (1 << shift) < grid:
        shift += 1
    var mask = grid - 1
    var run = runs.unsafe_ptr()

    # Each run's paint as an index into `paints`, and the bounds.
    scratch.keys.clear()
    scratch.paints.clear()
    var y_lo = run[unsafe_offset=0]
    var y_hi = y_lo
    var x_lo = run[unsafe_offset=1]
    var x_hi = run[unsafe_offset=2]
    var last_key = run[unsafe_offset=3] + 1
    var last_index = 0
    for i in range(count):
        var b = 4 * i
        var sub_row = run[unsafe_offset=b]
        y_lo = min(y_lo, sub_row)
        y_hi = max(y_hi, sub_row)
        x_lo = min(x_lo, run[unsafe_offset=b + 1])
        x_hi = max(x_hi, run[unsafe_offset=b + 2])
        var key = run[unsafe_offset=b + 3]
        if key != last_key:
            var k = 0
            while k < len(scratch.keys) and scratch.keys[k] != key:
                k += 1
            if k == len(scratch.keys):
                scratch.keys.append(key)
                if key == GRADIENT_KEY:
                    scratch.paints.append(fill)
                else:
                    scratch.paints.append(FillPaint(_key_color(key)))
            last_key = key
            last_index = k
        run[unsafe_offset=b + 3] = last_index
    var key_count = len(scratch.paints)
    var shaded = -1
    for k in range(key_count):
        if scratch.paints[k].shader:
            shaded = k
    var row0 = y_lo >> shift
    var rows = (y_hi >> shift) + 1 - row0
    var col0 = x_lo >> shift
    var stride = ((x_hi - 1) >> shift) + 2 - col0
    var x_shift = col0 << shift

    _ensure(scratch.starts, rows + 2)
    _ensure(scratch.order, count)
    _ensure(scratch.changes, key_count * stride)
    _ensure(scratch.stamps, stride)
    _ensure(scratch.touched, stride)
    _ensure(scratch.coverage, key_count)
    var starts = scratch.starts.unsafe_ptr()
    var order = scratch.order.unsafe_ptr()
    var changes = scratch.changes.unsafe_ptr()
    var stamps = scratch.stamps.unsafe_ptr()
    var touched = scratch.touched.unsafe_ptr()
    var coverage = scratch.coverage.unsafe_ptr()
    for i in range(key_count * stride):
        changes[unsafe_offset=i] = 0
    for i in range(stride):
        stamps[unsafe_offset=i] = -1
    for k in range(key_count):
        coverage[unsafe_offset=k] = 0

    # Bucket the runs by pixel row, counting first so one pass places them.
    for r in range(rows + 2):
        starts[unsafe_offset=r] = 0
    for i in range(count):
        starts[
            unsafe_offset=(run[unsafe_offset=4 * i] >> shift) - row0 + 2
        ] += 1
    for r in range(rows):
        starts[unsafe_offset=r + 2] += starts[unsafe_offset=r + 1]
    for i in range(count):
        var r = (run[unsafe_offset=4 * i] >> shift) - row0 + 1
        order[unsafe_offset=starts[unsafe_offset=r]] = i
        starts[unsafe_offset=r] += 1

    for r in range(rows):
        var touches = 0

        @always_inline
        def change(column: Int, key: Int, delta: Int) capturing:
            if delta == 0:
                return
            changes[unsafe_offset=key * stride + column] += delta
            if stamps[unsafe_offset=column] != r:
                stamps[unsafe_offset=column] = r
                touched[unsafe_offset=touches] = column
                touches += 1

        for j in range(starts[unsafe_offset=r], starts[unsafe_offset=r + 1]):
            var b = 4 * order[unsafe_offset=j]
            var k = run[unsafe_offset=b + 3]
            var lo = run[unsafe_offset=b + 1] - x_shift
            var hi = run[unsafe_offset=b + 2] - x_shift
            var first = lo >> shift
            var last = (hi - 1) >> shift
            if first == last:
                change(first, k, hi - lo)
                change(first + 1, k, lo - hi)
                continue
            var head = grid - (lo & mask)
            var tail = hi - (last << shift)
            change(first, k, head)
            change(first + 1, k, grid - head)
            change(last, k, tail - grid)
            change(last + 1, k, -tail)
        # Insertion sort: a row touches a few columns per edge it crosses.
        for i in range(1, touches):
            var column = touched[unsafe_offset=i]
            var j = i - 1
            while j >= 0 and touched[unsafe_offset=j] > column:
                touched[unsafe_offset=j + 1] = touched[unsafe_offset=j]
                j -= 1
            touched[unsafe_offset=j + 1] = column

        var y = row0 + r
        var row_off = y * s.width + col0
        for i in range(touches):
            var x = touched[unsafe_offset=i]
            var any = False
            var covering = -1
            for k in range(key_count):
                coverage[unsafe_offset=k] += changes[
                    unsafe_offset=k * stride + x
                ]
                changes[unsafe_offset=k * stride + x] = 0
                var samples = coverage[unsafe_offset=k]
                if samples >= full:
                    covering = k
                if samples > 0:
                    any = True
            if i + 1 == touches or not any:
                continue
            var end = touched[unsafe_offset=i + 1]
            var off = (row_off + x) * 4
            if covering >= 0:
                fill_span(s, off, end - x, scratch.paints[covering])
            elif shaded < 0 or coverage[unsafe_offset=shaded] == 0:
                var mixed = _mixed(scratch.paints, scratch.coverage, full, 0, 0)
                if end - x == 1:
                    blend(s, off, mixed)
                else:
                    fill_span(s, off, end - x, mixed)
            else:
                for px in range(x, end):
                    blend(
                        s,
                        off + (px - x) * 4,
                        _mixed(
                            scratch.paints,
                            scratch.coverage,
                            full,
                            col0 + px,
                            y,
                        ),
                    )
