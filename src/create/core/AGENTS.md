# AGENTS.md — `create.core`

Internals of the run loops. The root [AGENTS.md](../../../AGENTS.md) covers the consumer API and the
layering rules; the render side is in [../render/AGENTS.md](../render/AGENTS.md).

## Files

| File | Role |
|---|---|
| `run.mojo`, `_run_gl.mojo` | Windowed loops: CPU, and GPU (`backend == RenderBackend.GPU`) |
| `headless.mojo`, `_headless_gl.mojo` | `run_headless` over an owned buffer, CPU and GPU |
| `_step.mojo` | `first_step` — frame 1, drawn by `create` — and `step`, every later frame's body |
| `_window_loop.mojo` | Shared by both windowed loops over `NativeWindow`: `_apply_window_dials` (title, resizable — before presenting), `_apply_window_mode` (after presenting), `_finish_frame` (rumble, frame-rate cap) |
| `_events.mojo` | `apply_events` — the one `Event`-to-`Input` fold, into `context.input` |
| `context.mojo`, `time.mojo`, `input.mojo`, `key.mojo`, `mouse_button.mojo`, `gamepad.mojo`, `gamepad_button.mojo` | The run state the loop owns and the program reads: `Context` and its `time` and `input` readings |
| `editable_text.mojo` | `EditableText`, a caret-editing line fed from `Input`. Not run state: the program owns one per field |
| `date_time.mojo` | `DateTime`, the wall clock via libc `clock_gettime` + `localtime_r`. Not run state: nothing in the loop touches it |

## Rules

Every loop runs frame 1 through `first_step` and every later frame through `step`, and both
windowed loops fold events through `apply_events`, so they cannot drift in what a frame is or how
input is read. Loops differ only in how a frame starts (events and a clock, or a counter) and where
the pixels go.

**Order at startup:** seed `Context` from `run`'s arguments, derive the viewport
(`_wait_for_dimensions`, or `_set_viewport` headless), then `first_step` — `create` draws frame 1
under that mapping, with `context._count_frame()` and no clock tick — present it, start the clock,
enter the loop. Headless loops re-derive the viewport at the top of every frame, as the windowed
ones do.

**Window dials** (`title`, `resizable`, `window_mode`) are sent only when they changed:
`_AppliedWindow` remembers what the window was last told, seeded from `run`'s arguments. Title and
resizability go before presenting, so they show with their frame; the mode goes after, since the
frame just presented was laid out for the old size. `set_mode` in `_window` leaves the current mode
before entering the next; restore and maximize are requests a window manager may refuse, so they
never raise.

The loop owns one `Context` for the whole run and writes the frame's readings into it:
`context._advance_frame` (clock tick and frame count) before each `step`, `apply_events` into `context.input`. There is no separate
`Input` or clock in a loop, and `step` takes only `(program, context, state)`. Every frame's
`Canvas` comes from `context._new_canvas(state^)` and every remap from `context._set_viewport`, so
the mapping dials reach `render` in one place.

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

**Antialiasing is a `Backend` field the loops seed** from `run`'s argument
(`state.backend.antialiasing`) and `canvas.antialiasing` changes; the CPU replay, every pixel read
and the GL renderer read it at present. GL windows open single-sampled: the renderer multisamples
offscreen (see [../render/AGENTS.md](../render/AGENTS.md)), headless included.
