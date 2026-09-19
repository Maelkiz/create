"""Per-primitive timings for the CPU raster path, headless.

    pixi run create examples/cpu_bench.mojo

No window: this drives `_raster.mojo` and `Backend` (CPU kind) directly over a
`MemorySurface`, so it measures rasterisation alone — no SDL present, no event
pump. `examples/gl_bench.mojo cpu` is the other half of the picture: the same
sketch through the real window loop, which is what a program actually pays.

Every case reseeds `Random(1234)` per repetition, so every run — and every
future run, after a change to `_raster.mojo` or `_backend.mojo` — measures the
identical geometry. Times are ms/frame, mean over `_REPS` repetitions.

Baseline recorded 2026-09-13 on a Ryzen 5 2600X, before the CPU render backend
performance work (span-based rasterisation, incremental affine mapping, SIMD
blend) landed, next to the same cases after every phase of that work was
committed:

    case                              before    after
    fill_all opaque                   ~1.1 ms   ~0.4 ms
    fill_all alpha                     ~1.8 ms   ~0.8 ms   (2.07M px)
    fill_pixels opaque                ~1.0 ms   ~0.3 ms
    fill_pixels alpha                  ~7.3 ms   ~0.8 ms   (same 2.07M px as fill_all)
    2000 rects, alpha                  ~3.4 ms   ~3.1 ms
    2000 rects, opaque                ~1.2 ms   ~0.5 ms
    2000 rects, rotated, alpha        ~19.7 ms   ~9.3 ms
    2000 circles, alpha                ~7.2 ms   ~4.2 ms
    2000 circles, opaque              ~4.1 ms   ~1.5 ms
    2000 triangles, alpha             ~22.8 ms   ~8.5 ms
    2000 triangles, opaque            ~14.8 ms   ~3.2 ms
    2000 thick alpha lines            (n/a — new case)   ~0.9 ms
    20 text lines                      ~0.3 ms   ~0.2 ms
    gl_bench frame (record+present)   ~12.5 ms   ~3.5 ms

The rects/alpha case improved least: `fill_span`'s own per-call overhead and
`Backend`'s per-shape bookkeeping dominate at that shape count and size, not
the inner loop the other phases targeted. Sprite and glyph blits (added in a
later phase, not part of the original baseline table) aren't listed above for
that reason; see the phase's own commit for their before/after.
"""

from std.time import perf_counter_ns

from create import *
from create.render._backend import Backend
from create.render._command import (
    clear_command,
    rect_command,
    circle_command,
    triangle_command,
    text_command,
)
from create.render._raster import (
    fill_all,
    fill_pixels,
    blit_sprite,
    line_pixels,
)
from create.render._style import Style
from create.math.matrix import identity

comptime _W = 1920
comptime _H = 1080
comptime _REPS = 20
comptime _SHAPES = 2000


def _round(v: Float64) -> String:
    return String(Float64(Int(v * 1000.0 + 0.5)) / 1000.0)


def _report(label: String, t0: Int, t1: Int, reps: Int = _REPS):
    var per = Float64(t1 - t0) / 1.0e6 / Float64(reps)
    print(label + _round(per) + " ms")


def _base_matrix() -> Matrix[3, 3]:
    """The base mapping: y-up world space to top-down device pixels."""
    var m = identity[3]()
    m[0, 0] = 1.0
    m[1, 1] = -1.0
    m[0, 2] = Float64(_W) / 2.0
    m[1, 2] = Float64(_H) / 2.0
    return m^


def _rotated_matrix() -> Matrix[3, 3]:
    """A 45-degree rotation, so shapes fall onto the non-uniform replay path."""
    var m = identity[3]()
    m[0, 0] = 0.7071
    m[0, 1] = -0.7071
    m[1, 0] = 0.7071
    m[1, 1] = 0.7071
    m[0, 2] = Float64(_W) / 2.0
    m[1, 2] = Float64(_H) / 2.0
    return m^


def _fill_bench():
    var mem = MemorySurface(_W, _H)

    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        fill_all(s, Color(10, 20, 30))
    var t1 = perf_counter_ns()
    _report("fill_all opaque              ", t0, t1)

    t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        fill_all(s, Color(10, 20, 30, 192))
    t1 = perf_counter_ns()
    _report("fill_all alpha               ", t0, t1)

    t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        fill_pixels(s, 0, 0, _W, _H, Color(10, 20, 30))
    t1 = perf_counter_ns()
    _report("fill_pixels opaque           ", t0, t1)

    t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        fill_pixels(s, 0, 0, _W, _H, Color(10, 20, 30, 192))
    t1 = perf_counter_ns()
    _report("fill_pixels alpha            ", t0, t1)


def _shape_style(alpha: Bool) -> Style:
    var st = Style()
    st.fill_enabled = True
    st.outline_enabled = False
    st.fill = Color(200, 60, 60, 192) if alpha else Color(200, 60, 60)
    return st^


def _shapes_bench(
    m: Matrix[3, 3], mut be: Backend, mut mem: MemorySurface
) raises:
    for kind in range(3):
        for alpha in range(2):
            var st = _shape_style(alpha == 1)
            var t0 = perf_counter_ns()
            for _ in range(_REPS):
                var rng = Random(1234)
                for _i in range(_SHAPES):
                    var x = rng.float(-900.0, 900.0)
                    var y = rng.float(-500.0, 500.0)
                    var size = rng.float(8.0, 34.0)
                    if kind == 0:
                        be.record(rect_command(m, st, x, y, size, size * 0.7))
                    elif kind == 1:
                        be.record(circle_command(m, st, x, y, size * 0.5))
                    else:
                        be.record(
                            triangle_command(
                                m,
                                st,
                                x,
                                y + size,
                                x - size,
                                y - size,
                                x + size,
                                y - size,
                            )
                        )
                var s = mem.surface()
                be.present(s, 1.0)
            var t1 = perf_counter_ns()
            var name = "rects    " if kind == 0 else (
                "circles  " if kind == 1 else "triangles"
            )
            var mode = "alpha " if alpha == 1 else "opaque"
            _report("2000 " + name + " " + mode + "        ", t0, t1)


def _rotated_bench(
    rot: Matrix[3, 3], mut be: Backend, mut mem: MemorySurface
) raises:
    var st = _shape_style(True)
    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        var rng = Random(1234)
        for _i in range(_SHAPES):
            var x = rng.float(-400.0, 400.0)
            var y = rng.float(-300.0, 300.0)
            var size = rng.float(8.0, 34.0)
            be.record(rect_command(rot, st, x, y, size, size * 0.7))
        var s = mem.surface()
        be.present(s, 1.0)
    var t1 = perf_counter_ns()
    _report("2000 rects, rotated, alpha    ", t0, t1)


def _sprite_bench():
    comptime SW = 64
    comptime SH = 64
    var src = List[UInt8](length=SW * SH * 4, fill=0)
    var sp = src.unsafe_ptr()
    for i in range(SW * SH):
        sp[unsafe_offset=i * 4] = 200
        sp[unsafe_offset=i * 4 + 1] = 80
        sp[unsafe_offset=i * 4 + 2] = 80
        sp[unsafe_offset=i * 4 + 3] = 255

    var mem = MemorySurface(_W, _H)

    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        for row in range(0, _H, 260):
            for col in range(0, _W, 260):
                blit_sprite(s, sp, SW, SH, col, row, 256, 256)
    var t1 = perf_counter_ns()
    _report("sprite blit, upscaled 4x      ", t0, t1)

    t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        for row in range(0, _H, 20):
            for col in range(0, _W, 20):
                blit_sprite(s, sp, SW, SH, col, row, 16, 16)
    t1 = perf_counter_ns()
    _report("sprite blit, downscaled 4x    ", t0, t1)


def _line_bench():
    var mem = MemorySurface(_W, _H)
    var c = Color(200, 60, 60, 192)

    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        var s = mem.surface()
        var rng = Random(1234)
        for _i in range(_SHAPES):
            var x = rng.float(-900.0, 900.0)
            var y = rng.float(-500.0, 500.0)
            var len = rng.float(20.0, 80.0)
            line_pixels(s, x, y, x + len, y + len * 0.3, c, 6)
    var t1 = perf_counter_ns()
    _report("2000 thick alpha lines        ", t0, t1)


def _text_bench(
    m: Matrix[3, 3], mut be: Backend, mut mem: MemorySurface
) raises:
    var st = _shape_style(False)
    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        for _i in range(20):
            be.record(
                text_command(
                    m,
                    st,
                    -800.0,
                    400.0,
                    String("2000 shapes, two sprites, this line"),
                )
            )
        var s = mem.surface()
        be.present(s, 1.0)
    var t1 = perf_counter_ns()
    _report("20 text lines                 ", t0, t1)


def _frame_bench(
    m: Matrix[3, 3], mut be: Backend, mut mem: MemorySurface
) raises:
    """One `gl_bench`-shaped frame: a clear plus 2000 mixed shapes."""
    var st = _shape_style(True)
    var t0 = perf_counter_ns()
    for _ in range(_REPS):
        var rng = Random(1234)
        be.record(clear_command(Color(0x10, 0x12, 0x18)))
        for i in range(_SHAPES):
            var x = rng.float(-900.0, 900.0)
            var y = rng.float(-500.0, 500.0)
            var size = rng.float(8.0, 34.0)
            var kind = i % 3
            if kind == 0:
                be.record(rect_command(m, st, x, y, size, size * 0.7))
            elif kind == 1:
                be.record(circle_command(m, st, x, y, size * 0.5))
            else:
                be.record(
                    triangle_command(
                        m,
                        st,
                        x,
                        y + size,
                        x - size,
                        y - size,
                        x + size,
                        y - size,
                    )
                )
        var s = mem.surface()
        be.present(s, 1.0)
    var t1 = perf_counter_ns()
    _report("gl_bench frame (record+present)", t0, t1)


def main() raises:
    print(String(_W) + "x" + String(_H) + ", " + String(_REPS) + " reps")
    _fill_bench()

    var mem = MemorySurface(_W, _H)
    var be = Backend()
    var m = _base_matrix()
    var rot = _rotated_matrix()

    _shapes_bench(m, be, mem)
    _rotated_bench(rot, be, mem)
    _sprite_bench()
    _line_bench()
    _text_bench(m, be, mem)
    _frame_bench(m, be, mem)
