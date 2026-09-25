# AGENTS.md — `create.core`

Internals of the run loops. The root [AGENTS.md](../../../AGENTS.md) covers the consumer API and the
layering rules; the render side is in [../render/AGENTS.md](../render/AGENTS.md).

## Files

| File | Role |
|---|---|
| `run.mojo`, `_run_gl.mojo` | Windowed loops: CPU, and GPU (`backend == RenderBackend.GPU`) |
| `headless.mojo`, `_headless_gl.mojo` | `run_headless` over an owned buffer, CPU and GPU |
| `_step.mojo` | `step` — one frame's body |
| `_events.mojo` | `apply_events` — the one `Event`-to-`Input` fold, into `context.input` |

## Rules

Every loop runs its frame through `step`, and both windowed loops fold events through
`apply_events`, so they cannot drift in what a frame is or how input is read. Loops differ only in
how a frame starts (events and a clock, or a counter) and where the pixels go.

The loop owns one `Context` for the whole run and writes the frame's readings into it:
`context.time._tick` before each `step`, `apply_events` into `context.input`. There is no separate
`Input` or clock in a loop, and `step` takes only `(program, context, state)`.

`Input._set_mouse(x, y)` is the only writer of `mouse`/`mouse_x`/`mouse_y`; every event arm that
carries a position calls it and adds only what is its own.

**Take the CPU `Surface` after event processing**, sized from the window, never the viewport:
`Window._resize` reallocates the buffer during events, and a stale extent defeats every raster loop's
clipping — memory corruption, not a crooked frame.

**Size `glViewport` from `drawable_size()`, never `width()`/`height()`** — those are logical sizes
and differ under HiDPI. Re-read after event processing, for the same reason.

**A window's first reported size can be wrong.** Fullscreen fires a bogus `(1, 1)` resize first,
which `_wait_for_dimensions` pumps past; on Wayland frame 1 reports the requested size and frame 2
the display's. The loop re-reads dimensions every frame.

`run_gl` creates its `GLWindow` before constructing `GL()`, which needs a current context.
