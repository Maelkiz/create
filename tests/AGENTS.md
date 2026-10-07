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
passing file, with any `SKIP` lines it printed indented beneath. Each file is its own process;
namespace any scratch path under `/tmp` per file.

**Rendering is tested for real.** `run_headless` returns the `MemorySurface`, and
`MemorySurface.pixel(x, y)` reads it back — assert on pixels, don't eyeball. It antialiases at
`MEDIUM` like `run`: a test pinning an edge pixel's exact colour passes `antialiasing=Antialiasing.OFF`.
`core/test_step.mojo` scripts `context.input` and calls `step` directly for input-driven behaviour.

**GPU coverage, three tiers:**
- `render/test_gl_parity.mojo` renders one shape kind per frame through both backends and compares
  structurally (bounding box, centroid, ink coverage within tolerance, interior colour), not pixel by
  pixel — rasterisers may legitimately differ at edges, and exactness would forbid GPU antialiasing.
- `run_headless(..., backend=RenderBackend.GPU)` for what parity can't see across several commands
  in one frame: batch breaks, buffer growth and per-frame texture cleanup
  (`render/test_gl_batching.mojo`), and the GPU capture paths (`render/test_gl_capture.mojo`).
- Per pixel, where both backends are meant to compute the same colour: `render/test_gradient_fill.mojo`
  renders each gradient scene through both and compares every pixel at least two pixels from an
  edge, within one level per channel.

GL tests skip without a context. Their windows are `GLWindow(..., offscreen=True)` (as is
`run_headless`'s GPU path): SDL's offscreen driver, never shown and needing no display, with its
context from EGL — the host's GPU driver where there is one, Mesa's software GL elsewhere, which is
enough for library-logic bugs but blind to driver-specific ones. macOS has no EGL, so there the
window is a hidden Cocoa one instead: still never shown, but it needs a logged-in desktop session (a
Mac reached only over SSH may skip). If GL tests skip on a machine with a
working driver, suspect the environment's libraries shadowing the host driver's:
`scripts/activate.sh` preloads the system libdrm for that reason. Window tests that open a window
pin `SDL_VIDEODRIVER=dummy` in their own `main`.

`core/test_smoke.mojo` is built on every commit and run by the suite. Its uncalled
`_windowed_entry_point` still gets type-checked, which gates the windowed path. Keep it minimal.
