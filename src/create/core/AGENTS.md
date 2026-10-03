# AGENTS.md — `create.core`

Internals of the run loops. The root [AGENTS.md](../../../AGENTS.md) covers the consumer API and the
layering rules; the render side is in [../render/AGENTS.md](../render/AGENTS.md).

## Files

| File | Role |
|---|---|
| `run.mojo`, `_run_gl.mojo` | Windowed loops: CPU, and GPU (`backend == RenderBackend.GPU`) |
| `headless.mojo`, `_headless_gl.mojo` | `run_headless` over an owned buffer, CPU and GPU |
| `_step.mojo` | `step` — one frame's body |
| `_window_loop.mojo` | `_finish_frame` — rumble and frame-rate cap, shared by both windowed loops over `NativeWindow` |
| `_events.mojo` | `apply_events` — the one `Event`-to-`Input` fold, into `context.input` |
| `context.mojo`, `time.mojo`, `input.mojo`, `key.mojo`, `mouse_button.mojo`, `gamepad.mojo`, `gamepad_button.mojo` | The run state the loop owns and the program reads: `Context` and its `time` and `input` readings |
| `editable_text.mojo` | `EditableText`, a caret-editing line fed from `Input`. Not run state: the program owns one per field |
| `date_time.mojo` | `DateTime`, the wall clock via libc `clock_gettime` + `localtime_r`. Not run state: nothing in the loop touches it |

## Rules

Every loop runs its frame through `step`, and both windowed loops fold events through
`apply_events`, so they cannot drift in what a frame is or how input is read. Loops differ only in
how a frame starts (events and a clock, or a counter) and where the pixels go.

The loop owns one `Context` for the whole run and writes the frame's readings into it:
`context._advance_frame` (clock tick and frame count) before each `step`, `apply_events` into `context.input`. There is no separate
`Input` or clock in a loop, and `step` takes only `(program, context, state)`. Every frame's
`Canvas` comes from `context._new_canvas(state^)` and every remap from `context._set_viewport`, so
the dials reach `render` in one place.

`Input._set_mouse(x, y)` is the only writer of `mouse`/`mouse_x`/`mouse_y`; every event arm that
carries a position calls it and adds only what is its own.

**Gamepads are opened in `_window`, read in `core`.** SDL sends no axis or button events for a pad
until it is opened, so `_SDLWindow.events()` — the one event pump both windows own — tries
`translate_gamepad_device` before `translate_event`: it opens a pad on added (reading its name, which needs the open pad) and closes
it on removed, and a pad that fails to open is never announced. `apply_events` only assigns slots by
SDL's id. The gamepad subsystem is best-effort: `SDL.init_subsystems` raises only if video fails, and
a refused gamepad subsystem just means no gamepad events.

**Rumble flows the other way.** `context.rumble` queues a request addressed by SDL's id; both
windowed loops send the queue after presenting (`_finish_frame`), and `_advance_frame` empties it, which is also how
the headless loop drops it.

**Take the CPU `Surface` after event processing**, sized from the window, never the viewport:
`Window._resize` reallocates the buffer during events, and a stale extent defeats every raster loop's
clipping — memory corruption, not a crooked frame.

**Size `glViewport` from `drawable_size()`, never `width()`/`height()`** — those are logical sizes
and differ under HiDPI. Re-read after event processing, for the same reason.

**A window's first reported size can be wrong.** Fullscreen fires a bogus `(1, 1)` resize first,
which `_wait_for_dimensions` pumps past; on Wayland frame 1 reports the requested size and frame 2
the display's. The loop re-reads dimensions every frame.

`run_gl` creates its `GLWindow` before constructing `GL()`, which needs a current context.

**Antialiasing is the GL window's multisampling**, chosen at context creation: `_open_window` halves
the requested `Antialiasing` sample count until the driver accepts one, down to none. The CPU loop
ignores it, and the headless GPU loop renders into a single-sampled `_GLTarget`, so no test sees it.
