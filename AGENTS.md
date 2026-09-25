# AGENTS.md — Mojo Create

## Purpose

Mojo Create is a creative coding library for interactive graphics in Mojo: Processing's ergonomics,
clean separation of concerns, Mojo's performance — scaling from sketch to full application.

**Early development, no public release, no external consumers.** Breaking changes are fine. Doc
churn and rewriting examples or tests are not reasons to reject an idea; judge a change on whether
it makes the library better.

## Design Ethos

- **API intuitiveness first.** No non-obvious abbreviations; clarity over brevity in names.
- **Consumer ergonomics over a minimal API surface.**
- **Keep the common path simple.** A sketch needs minimal ceremony.
- **Modular architecture.** Separate concerns, minimise coupling.
- **Consistency.** Similar concepts behave and are named alike.
- **Good performance by default**, without internals knowledge or specialised APIs.

## Module Layout

| Module | Path | Responsibility |
|---|---|---|
| root | `src/create/__init__.mojo` | The preamble: star-imports all five subpackages below |
| `core` | `src/create/core/` | `Program`, the run loops (windowed, GPU, headless), `step`, event-to-`Input` translation, `WindowMode`, `source_path` |
| `render` | `src/create/render/` | `Frame`, `Options`, `Time`, `Input`, `Camera`, `Viewport`, colour/font/style, the command buffer, both backends (CPU rasteriser, GL 3.3) |
| `math` | `src/create/math/` | `Point2D`, `Vector2D`/`Vector3D`, `Matrix`, geometry shapes, `Random`, easing and `Tween`, util functions |
| `sprite` | `src/create/sprite/` | `Sprite` (BMP/PNG/JPEG), `SpriteAnimation`, `SpriteAnimator` |
| `audio` | `src/create/audio/` | `Sound` (WAV/OGG/FLAC/MP3), `Audio` playback |
| `_bytes` | `src/create/_bytes.mojo` | Internal leaf: little-endian integer decoding |
| `_window` | `src/create/_window/` | Internal platform layer: `Window`, `GLWindow`, typed `Event`s, SDL3 video bindings |

Files worth knowing by name (each type's own surface is in its docstring):

| File | Role |
|---|---|
| `core/_step.mojo` | `step` — one frame's body, shared by every loop so they cannot drift |
| `core/_events.mojo` | `apply_events` — the one SDL-event-to-`Input` fold, shared by both windowed loops |
| `core/_run_gl.mojo`, `core/_headless_gl.mojo` | GPU counterparts of `run` and `run_headless` |
| `render/frame.mojo` | `Frame` (records commands, touches no pixels), `PersistentFrameState`, the guards |
| `render/_command.mojo` | `RenderCommand` and its kind constants |
| `render/_backend.mojo` | `Backend` — fonts, glyph cache, interned images; replays commands via `present` (CPU) or `present_gpu` |
| `render/_raster.mojo` | CPU rasteriser over a `Surface`; called only from `_backend.mojo` |
| `render/_gl.mojo` | GL entry points resolved at runtime; the only file that talks to the driver |
| `render/_gl_backend.mojo` | `GLRenderer` — shader, vertex buffer, glyph atlas, sprite textures, batching |
| `render/_tessellate.mojo` | `RenderCommand` to triangles for the GPU |
| `render/_transform.mojo`, `render/_image.mojo`, `render/_fillet.mojo` | Shared by both replay paths (split out to avoid an import cycle, or so both agree on the numbers) |
| `render/_gl_target.mojo` | Offscreen FBO of an exact size, for the parity test and headless GPU |
| `_window/_sdl.mojo` | Raw SDL3 video bindings; the only file in `_window` that touches SDL |

## Build & Test

```bash
mojo run -I src examples/sketch.mojo      # -I src is required, see Gotcha 1
pixi run example sketch                   # by name; no argument lists them
pixi run test                             # whole suite, concurrent
pixi run test render                      # subpackage, file name sans test_, or path; several allowed
pixi run test -j 4 frame tween            # pin worker count (default nproc, max 8)
pixi run precompile                       # type-check the library, output in build/
pixi run format                           # 80 columns, enforced by pre-commit
pixi run setup                            # once per clone: git hooks + blame ignore-revs
```

There is no CI. Two git hooks, active after `pixi run setup`, are the only automated checks:

| Hook | Runs |
|---|---|
| `pre-commit` | Formatting check on staged `.mojo` files, then builds `tests/core/test_smoke.mojo`. Constant cost |
| `pre-push` | `mojo precompile`, every example, the test suite. Skipped when every pushed path is inert (`*.md`, `LICENSE`, agent/editor config) |

`--no-verify` is only for WIP on a scratch branch that gets squashed, never on `main`.

Neither tier subsumes the other: building a consumer program type-checks only the `def` bodies it
reaches (catches API drift, not an uncalled broken function); `mojo precompile` is the reverse.

`mojo format`'s grammar is narrower than the compiler's and will abort a commit: `where` is
reserved (not usable as a name), and `;` statement separators don't parse.

## Testing

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
`tests/core/test_step.mojo` scripts an `Input` and calls `step` directly for input-driven behaviour.

**GPU coverage, two tiers:**
- `test_gl_parity.mojo` renders one shape kind per frame through both backends and compares
  structurally (bounding box, centroid, ink coverage within tolerance, interior colour), not pixel by
  pixel — rasterisers may legitimately differ at edges, and exactness would forbid GPU antialiasing.
- `run_headless(..., backend=RenderBackend.GPU)` for what parity can't see across several commands
  in one frame: batch breaks and buffer growth (`test_gl_batching.mojo`), and the GPU capture paths
  (`test_gl_capture.mojo`).

GL tests skip without a context. `pixi run test` uses SDL's offscreen driver when no display is set
(`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` all unset), which gives a software GL 3.3 context —
enough for library-logic bugs, blind to driver-specific ones. Window tests that open a window pin
`SDL_VIDEODRIVER=dummy` in their own `main`.

`tests/core/test_smoke.mojo` is built on every commit and run by the suite. Its uncalled
`_windowed_entry_point` still gets type-checked, which gates the windowed path. Keep it minimal.

## Code Conventions

### Programs

Implement `Program` (`create(mut options)` + `update(mut self, mut options, mut frame)`) and pass it
to `run[T]`. Minimum: [tests/core/test_smoke.mojo](tests/core/test_smoke.mojo); full shape:
[examples/sidescroller/src/main.mojo](examples/sidescroller/src/main.mojo).

`create` gets no `Frame` — none exists before the loop — so rendering or reading geometry there is a
compile error. Input arrives as `frame.input`; there are no event callbacks.

**Multiple screens:** a root `Program` holds each screen as a plain field (not implementing
`Program`) and switches with an int field and `if`/`elif`. A scene's `update` takes only what it uses
(often just `frame`); a one-shot reset is a plain `enter(...)` method the parent calls before
switching, taking whatever that transition carries. No trait: it would force one `update`/`enter`
signature on every scene, and those must vary. See [examples/scenes/src/main.mojo](examples/scenes/src/main.mojo).
(Mojo 1.1 has no dynamic trait dispatch; heterogeneous storage is `Variant` from `std.utils`, with
`isa[T]()` to dispatch.)

**Parameter vs. field:** what the loop hands the program every frame (`Options`, `Frame`) is a
parameter. What the program drives on its own schedule (`Sprite`, `Font`, `Sound`, `Audio`,
`SpriteAnimator`, `Camera`, `Tween`) is a field it constructs in `create` — so adding one touches
neither `Program` nor the run loop. `Time` and `Input` ride on `Frame`; `frame.input` is a per-frame
copy, so writing to it reaches nothing that outlives the frame.

**Per-frame obligations**, not enforced by anything:
- `audio.update()` — otherwise looping streams stall and one-shot voice slots leak.
- `animator.update(frame.time.delta)` / `tween.update(frame.time.delta)` — otherwise the playhead
  never moves.

Shared assets (`SpriteAnimation`, `Sound`) are held as `ArcPointer` fields. Read
[`SpriteAnimator.use`](src/create/sprite/animator.mojo) before driving an animator.

### Imports and public surface

A program writes `from create import *`. Otherwise import by name from the owning package
(`from create.math import overlaps`); a single subpackage star is not a preamble.

- The root has no names of its own — it star-imports the five subpackages. Never add a name there;
  add it to the owning subpackage.
- A subpackage exports only what it owns, never a lower layer's symbol.
- Public surface is exactly what an `__init__.mojo` lists. A new declaration is internal unless it is
  added to one in the same change: `_module.mojo` for a wholly internal file, `_name` for an internal
  declaration in a public module. Tests reach internals by explicit path.

### Layering

- **`render` never imports `core`** (it would be a cycle). `render` depends only on `math`, `sprite`
  and `_bytes`, so it works without a run loop.
- **`_bytes`** is a leaf imported by `sprite` and `render`, re-exported by nothing.
- **`_window`** imports nothing from `create`; `core` is its only consumer; nothing re-exports it.
- **`render`→`sprite` is nominal:** only `frame.sprite`'s overloads name `Sprite`/`SpriteAnimator`.
  A `render` function that needs pixels takes a pointer plus width/height, not an image type.
- **`render` reaches GL without `_window`:** `_gl.mojo` `dlopen`s SDL itself and resolves through
  `SDL_GL_GetProcAddress`. A GL context must be current before `GL()` is constructed.

### Frame, commands and backends

A `Frame` render call **records, never paints**: it appends a `RenderCommand` (local geometry,
transform at record time, style resolved now) to the `Backend`. Nothing rasterises until
`present`/`present_gpu` replays the frame, so later style calls can't reach back. Sprites are interned
into the backend at record time (the command carries an id); text is recorded as an owned `String`
and laid out at replay. Add a shape by extending `_command.mojo`'s kinds and `_backend.mojo`'s replay
(plus `_tessellate.mojo`), never by calling `_raster.mojo` from `Frame`.

`Frame` is built fresh each frame and dropped before presenting; nothing may hold one across frames.
It holds no `Surface` and takes its geometry from the `Viewport` alone — don't add a `Surface` field
or parameter, and don't import `_window` from `frame.mojo`. What survives the frame boundary:
`PersistentFrameState` (the `Backend`, `Viewport`, clock — moved in and back out by `_release`) and
`Options` (owned by the loop). The transform stack, style and camera reset every frame by design.

`Backend.kind` selects the replay (`RenderBackend.CPU` onto a `Surface`, `GPU` through `GLRenderer`);
a field rather than a trait because Mojo has no dynamic dispatch. Users pick with
`run[T](..., backend=RenderBackend.GPU)`.

The CPU `Surface` passed to `present` must be taken **after** event processing, with its size from
the window, never the viewport: `Window._resize` reallocates the buffer during events, and a stale
extent defeats every raster loop's clipping (memory corruption, not just a crooked frame).

**Captures** are requests filed on the `Backend` and serviced inside `present`/`present_gpu`, the only
place holding both the finished framebuffer and the unconsumed command buffer; a failed write raises
from there.
- `frame.save_image(path, scale, transparent)` — what the program drew: design resolution × `scale`,
  no letterbox, CPU-replayed from the commands under **both** backends (glyph cache and images live
  on `Backend`, not `GLRenderer`). Reproducible across machines.
- `frame.save_screenshot(path)` — what the user saw: drawable resolution, bars included. On GPU this
  is a `glReadPixels` stall — fine on a keypress, not per frame.

See [examples/screenshot/src/main.mojo](examples/screenshot/src/main.mojo).

### CPU rasteriser

Compute each row's covered run analytically and hand `(start, count)` to `fill_span` once — never
test every pixel in a bounding box. `fill_span` owns the opaque-store and vectorised compositing.
`blend` is only for genuinely per-pixel alpha (glyph coverage, sprite texels).

### GPU path (OpenGL 3.3)

`_tessellate.mojo` bakes each command's transform into its vertices (9 × `Float32`: `x, y, u, v, r,
g, b, a, mode`; `mode` picks solid/glyph/texture in the shader), so everything accumulates into one
buffer and flushes as one `glBufferData` + `glDrawArrays`. A batch breaks only on an opaque
`CMD_CLEAR`, a second distinct sprite texture, or frame end — glyph atlas on texture unit 0, sprites
on unit 1. Per frame, only the viewport is written, and only on resize.

Before optimising: `examples/gl_bench.mojo` runs ~1.1 ms/frame; the vertex list stops reallocating
after frame 1; orphan-then-`glBufferSubData` measured identical to the current single `glBufferData`.
`examples/cpu_bench.mojo` measures CPU rasterisation headless.

**FFI rules for `_gl.mojo`** (calls go through bitcast `thin abi("C")` pointers; this works):
1. A `String` whose pointer goes to C must outlive the call — put `_ = s` after it. Check every
   resolved address against 0.
2. Read C out-parameters from heap memory (`List`), not a local `InlineArray` — the optimizer may
   serve the local stale.
3. Keep the GL context owner alive past the last GL call (`_ = win^` in tests and spikes).

### Style, clear and outlines

`Style()` defaults are not blank: **outline `BLACK`, enabled, 1 unit**; transparent fill; `BLACK`
text. Every frame opens with a recorded `CMD_CLEAR` to `options.clear_color` (gray 200) so those
defaults are visible.
- An opaque `frame.background()` replaces that clear (`Backend.record_clear`); a translucent one
  blends over it.
- `options.autoclear` is read at frame construction, so set it in `create`. Off lets ink accumulate
  (CPU backend only — GPU swaps buffers).

`fill`, `outline` and `text_color` set three independent colours; `fill(enabled=False)` does not
hide text. Text is hidden by a zero-alpha `text_color`.

Outlines mean different things per shape, and `corner_radius` must preserve that: a rectangle's is
an **inset ring** inside the fill; a triangle's is **centred device-space bands**. Spelled out in
`emit_triangle`'s docstring in [_tessellate.mojo](src/create/render/_tessellate.mojo).

**Scope with the guards.** `frame.transform(m)`, `frame.style()` and `frame.overlay()` return
`with`-block guards that unwind on exit. Bare style mutators straight from `update` are fine (style
resets next frame); a *helper* that sets style wraps it in `frame.style()` so it can't leak into the
caller's next render.

### Coordinates, camera, autoscale

**Not Processing's coordinates.** Origin at the screen centre, **y up**; `x ∈ [-w/2, w/2]`,
`y ∈ [-h/2, h/2]`. So `rotate` is counter-clockwise, gravity is negative `y`, and `frame.left()`/
`bottom()` are negative — use the edge methods, not `width`/`height` arithmetic. Glyphs and sprites
are not flipped. **All shapes are centre-positioned**, including `Rectangle.x/y`.

**Camera:** `frame.camera(cam)` maps world space onto screen space for every later render call and
nested transform, reset every frame. `frame.overlay()` suspends it for HUD content.
`frame.input.mouse` is in screen space; use `cam.to_world(frame.input.mouse)` for picking. Nothing
below `Frame` knows about cameras — it's folded into `RenderCommand.transform`.

```mojo
frame.camera(self.cam)
frame.sprite(self.player.sprite, self.player.pos)     # world space
with frame.overlay():
    frame.text("Score: " + String(self.score), (0, frame.top() - 20))  # screen space
```

**Design resolution** is the `width`/`height` passed to `run` (or `options.design_resolution()` from
`create`): the space the program is authored in, not a window size. Fullscreen/maximized scale the
design onto the display. `options.autoscale` is `FIT` (default), `EXTEND` or `OFF`; `OFF` makes
coordinates the window's own pixels. Under `EXTEND` the reported size grows with the window, so
anchor layout to the edges. Font size, outline thickness and sprite size scale by `frame.scale`. See
[examples/autoscale.mojo](examples/autoscale.mojo).

`Options` dials are read at frame construction, so a change mid-`update` applies next frame —
except `frame_cap()` and `quit()`, read after `update` returns.

`Input._set_mouse(x, y)` is the only writer of `mouse`/`mouse_x`/`mouse_y`; every positional event arm
in [core/_events.mojo](src/create/core/_events.mojo) calls it.

## Critical Gotchas

1. **`-I src` is required for every `mojo run`**, or `from create import *` fails. Pixi tasks add it.

2. **Resolve asset paths with `source_path(...)`**, not bare relative paths (those resolve against
   the CWD). It resolves against the calling source file, baked in at compile time. A `mojo build`
   binary only resolves from another directory if built with absolute paths, and only while the
   source exists. Tests assume the repo root as CWD, which `pixi run test` guarantees.

3. **A window's first reported size can be wrong.** Fullscreen fires a bogus `(1, 1)` resize first
   (`_wait_for_dimensions` pumps past it), and on Wayland frame 1 reports the requested size, the
   display size from frame 2. The loop refreshes every frame; don't cache pixel dimensions from
   `create` or the first frame.

4. **No function can return a reference to a `List` element** in this Mojo version, so
   `SpriteAnimation` has no `frame()` accessor. Index inline at the use site. Don't retry it.

5. **An uncalled overload is type-checked by nothing.** [tests/render/test_frame.mojo](tests/render/test_frame.mojo)
   renders through all of `frame.sprite`'s animator overloads for this reason — extend it when adding
   one.

6. **Size `glViewport` from `drawable_size()`, never `width()`/`height()`** — those are logical sizes
   and differ under HiDPI. Re-read after event processing, like the CPU `Surface`.

## Terminology

| Term | Meaning |
|---|---|
| Screen space | Origin-centred, y-up, camera-independent. `frame.left()`…`top()` and `frame.input.mouse` live here |
| World space | What render calls use once a `Camera` is set; identical to screen space without one. `frame.to_world`/`to_local` convert between world space and the current transform (two `Float64` in, a tuple out) |
| Asset vs. playhead | `SpriteAnimation`/`Sound` are shared immutable assets; `SpriteAnimator`/an `Audio` voice are one entity's position in one. `fps` belongs to the asset |
| `Easing` / `Tween` | An `Easing` is a stateless curve over a 0-to-1 fraction (`ease(curve, t)`); a `Tween` walks that fraction over a duration. Each entity owns its own `Tween` |
| `Point2D` / `Vector2D` | Chosen by role. A location is a `Point2D` (`frame.circle(pos, r)`, `frame.input.mouse`); an extent or displacement is a `Vector2D` (`Rectangle.size()`, velocities). `Point2D` deliberately lacks `mag`, `normalize`, `dot`, scalar `*`, unary `-` and `Point2D + Point2D`. Both take a bare tuple implicitly |
| `overlaps` / `intersects` / `contains` | `overlaps(a, b)`: free, symmetric, regions only (`Rectangle`/`Circle`/`Triangle`). `line.intersects(x)`: `Line` only, since a line has no interior. `region.contains(x)`: asymmetric. A `Line` is never a region |

## Do

- Use `@fieldwise_init` on program structs.
- Run only the tests a change can reach (`pixi run test render`); pre-push runs the whole suite.
- Make `frame.background(...)` the first render call in `update`, or set `options.clear_color` in
  `create` if the colour never changes.
- Use `Point2D` for new locations and `Vector2D` for extents/deltas;
  `frame.rectangle(pos: Point2D, size: Vector2D)` is the shape to copy.

## Don't

- Don't use `alias` — deprecated for `comptime`.
- Don't use `UnsafePointer` — deprecated for `Pointer`.
- Don't use `fn` — removed; use `def`.
- Don't hold a raw `Pointer` to `Frame` outside the guards; use origin-tracked references.
- Don't name a test file without the `test_` prefix; the runner won't find it.
- Don't add a `Point2D` overload beside a `Vector2D` one: both have `@implicit` tuple constructors,
  so `frame.circle((0, 0), 20)` becomes ambiguous. Change the parameter's type instead. That's also why
  `p - Vector2D(1, 2)` must name the type while `p + (1, 2)` need not. Don't "fix" that by adding
  `Point2D.__add__(Point2D)` — the type exists to refuse it.
