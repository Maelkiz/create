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

Package internals are documented in scoped files: [src/create/render/AGENTS.md](src/create/render/AGENTS.md),
[src/create/core/AGENTS.md](src/create/core/AGENTS.md), [tests/AGENTS.md](tests/AGENTS.md).

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
| `pre-push` | `mojo precompile`, every example, the test suite |

Both skip entirely when every staged or pushed path is inert (`*.md`, `LICENSE`, agent/editor
config) — the allowlist is in `.githooks/_inert.sh`.

`--no-verify` is only for WIP on a scratch branch that gets squashed, never on `main`.

Neither tier subsumes the other: building a consumer program type-checks only the `def` bodies it
reaches (catches API drift, not an uncalled broken function); `mojo precompile` is the reverse.

`mojo format`'s grammar is narrower than the compiler's and will abort a commit: `where` is
reserved (not usable as a name), and `;` statement separators don't parse.

## Code Conventions

### Programs

Implement `Program` (`create(mut options)` + `update(mut self, mut options, mut frame)`) and pass it
to `run[T]`. Minimum: [tests/core/test_smoke.mojo](tests/core/test_smoke.mojo); full shape:
[examples/sidescroller/src/main.mojo](examples/sidescroller/src/main.mojo).

`create` gets no `Frame` — none exists before the loop — so rendering or reading geometry there is a
compile error. Input arrives as `frame.input`; there are no event callbacks. A `Frame` is built fresh
each frame; nothing may hold one across frames.

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

### Style and clear

`Style()` defaults are not blank: **outline `BLACK`, enabled, 1 unit**; transparent fill; `BLACK`
text. Every frame opens with a clear to `options.clear_color` (gray 200) so those defaults are
visible.
- An opaque `frame.background()` replaces that clear rather than painting a second time; a
  translucent one blends over it.
- `options.autoclear` is read at frame construction, so set it in `create`. Off lets ink accumulate
  (CPU backend only — GPU swaps buffers).

`fill`, `outline` and `text_color` set three independent colours; `fill(enabled=False)` does not
hide text. Text is hidden by a zero-alpha `text_color`.

**Scope with the guards.** `frame.transform(m)`, `frame.style()` and `frame.overlay()` return
`with`-block guards that unwind on exit. Bare style mutators straight from `update` are fine (style,
transform and camera reset every frame); a *helper* that sets style wraps it in `frame.style()` so it
can't leak into the caller's next render.

### Coordinates, camera, autoscale

**Not Processing's coordinates.** Origin at the screen centre, **y up**; `x ∈ [-w/2, w/2]`,
`y ∈ [-h/2, h/2]`. So `rotate` is counter-clockwise, gravity is negative `y`, and `frame.left()`/
`bottom()` are negative — use the edge methods, not `width`/`height` arithmetic. Glyphs and sprites
are not flipped. **All shapes are centre-positioned**, including `Rectangle.x/y`.

**Camera:** `frame.camera(cam)` maps world space onto screen space for every later render call and
nested transform, reset every frame. `frame.overlay()` suspends it for HUD content.
`frame.input.mouse` is in screen space; use `cam.to_world(frame.input.mouse)` for picking.

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

## Critical Gotchas

1. **`-I src` is required for every `mojo run`**, or `from create import *` fails. Pixi tasks add it.

2. **Resolve asset paths with `source_path(...)`**, not bare relative paths (those resolve against
   the CWD). It resolves against the calling source file, baked in at compile time. A `mojo build`
   binary only resolves from another directory if built with absolute paths, and only while the
   source exists. Tests assume the repo root as CWD, which `pixi run test` guarantees.

3. **Don't cache pixel dimensions from `create` or the first frame.** A window's first reported size
   can be wrong (fullscreen, Wayland); the loop corrects it from the next frame on.

4. **No function can return a reference to a `List` element** in this Mojo version, so
   `SpriteAnimation` has no `frame()` accessor. Index inline at the use site. Don't retry it.

5. **An uncalled overload is type-checked by nothing.** [tests/render/test_frame.mojo](tests/render/test_frame.mojo)
   renders through all of `frame.sprite`'s animator overloads for this reason — extend it when adding
   one.

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
