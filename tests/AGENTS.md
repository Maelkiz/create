# AGENTS.md — tests

Tests use `std.testing.TestSuite`; each `tests/**/test_*.mojo` is a program:

```mojo
from std.testing import TestSuite, assert_equal

def test_thing_does_what_it_says() raises -> None:
    assert_equal(actual, expected)

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
```

`pixi run test` runs files concurrently, prints a failing file's full output and one `PASS` line per
passing file. Each file is its own process; namespace any scratch path under `/tmp` per file.

**Rendering is tested for real.** `run_headless` returns the `MemorySurface`, and
`MemorySurface.pixel(x, y)` reads it back — assert on pixels, don't eyeball.
`core/test_step.mojo` scripts `context.input` and calls `step` directly for input-driven behaviour.

**GPU coverage, two tiers:**
- `render/test_gl_parity.mojo` renders one shape kind per frame through both backends and compares
  structurally (bounding box, centroid, ink coverage within tolerance, interior colour), not pixel by
  pixel — rasterisers may legitimately differ at edges, and exactness would forbid GPU antialiasing.
- `run_headless(..., backend=RenderBackend.GPU)` for what parity can't see across several commands
  in one frame: batch breaks and buffer growth (`render/test_gl_batching.mojo`), and the GPU capture
  paths (`render/test_gl_capture.mojo`).

GL tests skip without a context. `pixi run test` uses SDL's offscreen driver when no display is set
(`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` all unset), which gives a software GL 3.3 context —
enough for library-logic bugs, blind to driver-specific ones. Window tests that open a window pin
`SDL_VIDEODRIVER=dummy` in their own `main`.

`core/test_smoke.mojo` is built on every commit and run by the suite. Its uncalled
`_windowed_entry_point` still gets type-checked, which gates the windowed path. Keep it minimal.
