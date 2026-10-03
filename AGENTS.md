# AGENTS.md — Create

## Purpose

Create is a creative coding library for interactive graphics in Mojo: Processing's ergonomics,
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
| root | `src/create/__init__.mojo` | The preamble: star-imports all six subpackages below |
| `core` | `src/create/core/` | `Program`, the run state (`Context`, `Time`, `Input`, `Key`, `MouseButton`, `Gamepad`, `GamepadButton`), the run loops (windowed, GPU, headless), `step`, event-to-`Input` translation, `WindowMode`, `source_path`, `DateTime` |
| `render` | `src/create/render/` | `Canvas`, `Camera`, `Antialiasing`, font/style, the command buffer, both backends (CPU rasteriser, GL 3.3) |
| `color` | `src/create/color/` | `Color`, `Gradient` (with the ramp and dither both backends share), `BlendMode` |
| `math` | `src/create/math/` | `Point2D`, `Vector2D`/`Vector3D`, `Matrix`, geometry shapes (`Rectangle`, `Circle`, `Triangle`, `Sector`, `Polygon`, `Line`, `Arc`), `Bezier`, `Spline`, `Random`, `Noise`, easing and `Tween`, util functions |
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
pixi run benchmark frame                  # benchmarks/, same form; frame cpu for the CPU backend
pixi run test                             # whole suite, concurrent
pixi run test render                      # subpackage, file name sans test_, or path; several allowed
pixi run test -j 4 canvas tween           # pin worker count (default nproc, max 8)
pixi run precompile                       # type-check the library, output in build/
pixi run format                           # 80 columns, enforced by pre-commit
pixi run setup                            # once per clone: git hooks + blame ignore-revs
```

There is no CI. Two git hooks, active after `pixi run setup`, are the only automated checks:

| Hook | Runs |
|---|---|
| `pre-commit` | Formatting check on staged `.mojo` files, then builds `tests/core/test_smoke.mojo`. Constant cost |
| `pre-push` | `mojo precompile`, every example and benchmark, the test suite |

Both skip entirely when every staged or pushed path is inert (`*.md`, `LICENSE`, agent/editor
config) — the allowlist is in `.githooks/_inert.sh`.

`--no-verify` is only for WIP on a scratch branch that gets squashed, never on `main`.

Neither tier subsumes the other: building a consumer program type-checks only the `def` bodies it
reaches (catches API drift, not an uncalled broken function); `mojo precompile` is the reverse.

`mojo format`'s grammar is narrower than the compiler's and will abort a commit: `where` is
reserved (not usable as a name), and `;` statement separators don't parse.

## Code Conventions

### Programs

Implement `Program` (`create(mut context)` + `update(mut self, mut context, mut canvas)`) and pass it
to `run[T]`. Minimum: [tests/core/test_smoke.mojo](tests/core/test_smoke.mojo); full shape:
[examples/sidescroller/src/main.mojo](examples/sidescroller/src/main.mojo).

`create` gets no `Canvas` — none exists before the loop — so rendering or reading geometry there is a
compile error. Input arrives as `context.input`; there are no event callbacks. A `Canvas` is built
fresh each frame; nothing may hold one across frames.

**Multiple screens:** a root `Program` holds each screen as a plain field (not implementing
`Program`) and switches with an int field and `if`/`elif`. A scene's `update` takes only what it uses
(`context` to read input or time, `canvas` to draw); a one-shot reset is a plain `enter(...)` method the parent calls before
switching, taking whatever that transition carries. No trait: it would force one `update`/`enter`
signature on every scene, and those must vary. See [examples/scenes/src/main.mojo](examples/scenes/src/main.mojo).
(Mojo 1.1 has no dynamic trait dispatch; heterogeneous storage is `Variant` from `std.utils`, with
`isa[T]()` to dispatch.)

**Parameter vs. field:** what the loop hands the program every frame (`Context`, `Canvas`) is a
parameter: `Context` is the run's state and outlives the frame, `Canvas` is where this frame is
drawn. What the program drives on its own schedule (`Sprite`, `Font`, `Sound`, `Audio`,
`SpriteAnimator`, `Camera`, `Tween`, `Noise`) is a field it constructs in `create` — so adding one touches
neither `Program` nor the run loop. `Time` and `Input` live on `Context`: the loop ticks
`context.time` and folds events into `context.input` before `update`. Read them, don't write them —
the loop carries both into the next frame.

**Per-frame obligations**, not enforced by anything:
- `audio.update()` — otherwise looping streams stall and one-shot voice slots leak.
- `animator.update(context.time.delta)` / `tween.update(context.time.delta)` — otherwise the playhead
  never moves.

Shared assets (`SpriteAnimation`, `Sound`) are held as `ArcPointer` fields. Read
[`SpriteAnimator.use`](src/create/sprite/animator.mojo) before driving an animator.

### Printing

A public value type implements `Writable` and prints as it would be written in source:
`Point2D(1.0, 2.0)` positionally for the small math types and `Color`; `Easing.OUT_BOUNCE` for an
`Int`-wrapping enum (an unnamed value falls back to `Easing(99)`); keyword form otherwise, labelled
by the constructor's keywords where it has them (`Circle(position=Point2D(0.0, 0.0), r=5.0)`) and by
public field names where it doesn't (`Time`, `Tween`). Private fields are left out. Resource handles
(`Font`, `Sprite`, `Sound`, `Audio`) and shared assets (`SpriteAnimation`) are not printable.

### Imports and public surface

A program writes `from create import *`. Otherwise import by name from the owning package
(`from create.math import overlaps`); a single subpackage star is not a preamble.

- The root has no names of its own — it star-imports the six subpackages. Never add a name there;
  add it to the owning subpackage.
- A subpackage exports only what it owns, never a lower layer's symbol.
- Public surface is exactly what an `__init__.mojo` lists. A new declaration is internal unless it is
  added to one in the same change: `_module.mojo` for a wholly internal file, `_name` for an internal
  declaration in a public module. Tests reach internals by explicit path.

### Layering

- **`render` never imports `core`** (it would be a cycle). `render` depends only on `math`, `color`,
  `sprite` and `_bytes`, so it works without a run loop. So `Canvas` takes `Context`'s dials as plain values;
  `context._set_viewport(state, …)` and `context._new_canvas(state^)` in `core` pass them in.
- **`color`** depends only on `math`; `sprite` and `render` both import it. It sits below `sprite` so
  that `Sprite.pixel` can return a `Color` without a `render`↔`sprite` cycle.
- **`_bytes`** is a leaf imported by `sprite` and `render`, re-exported by nothing.
- **`_window`** imports nothing from `create`; `core` is its only consumer; nothing re-exports it.
- **`render`→`sprite` is nominal:** only `canvas.sprite`'s overloads and `canvas.snapshot` name
  `Sprite`/`SpriteAnimator`.
  A `render` function that needs pixels takes a pointer plus width/height, not an image type.

### Style and clear

`Style()` defaults are not blank: **outline `BLACK`, on, 1 unit**; fill `WHITE`, off; `BLACK`
text. Every frame opens with a clear to gray 200 so those defaults are visible;
`canvas.background()` is the only way to choose the colour.
- An opaque `canvas.background()` replaces that clear rather than painting a second time; a
  translucent one blends over it.
- `context.autoclear(enabled)` is read at frame construction, so call it in `create`. Off lets ink
  accumulate (CPU backend only — GPU swaps buffers).

`fill`, `outline` and `text_color` set three independent colours; `fill_enabled(False)` does not
hide text. Text is hidden by a zero-alpha `text_color`. `fill_enabled`/`outline_enabled` switch
off without losing the colour; `fill(...)`/`outline(...)`/`shadow(...)` switch back on, and with
no arguments keep every part, so `fill()` alone paints the default white.

**Three ways to style**, all additive:

| Form | Effect |
|---|---|
| `canvas.fill(Color.RED)` (any setter) | Rest of the frame |
| `with canvas.style(fill=Color.RED):` | Only the named fields, for the block (each goes through its setter) |
| `with canvas.style(heading):` | A whole `Style` value, for the block — unset fields are `Style()` defaults, not the previous style |

`Style(...)` takes the setters' names as keywords and, like them, naming any part of the fill,
outline or shadow switches it on unless its `*_enabled` keyword says otherwise. A reusable style is
a field built in `create`.
The font is not part of a style: it lives on `PersistentCanvasState` and outlives the frame.

**Gradients** fill regions and backgrounds: `canvas.fill(gradient)` and `canvas.background(gradient)`
are overloads beside the colour ones, and the `Style`/`canvas.style` keyword is `fill_gradient=`,
not `fill=` — one keyword can't take both types, and an `Optional[Paint]` wrapper would need two
implicit conversions from a bare `Color`, which Mojo won't chain.
- While set, the gradient fills and `fill_color` is kept: `fill(color)` clears the gradient,
  `fill()`/`fill_enabled(...)` keep it. Given `fill=` and `fill_gradient=` together, the gradient
  wins.
- Fills only: outlines, lines, curves and text ignore it, and a shadow stays the silhouette in
  `shadow_color` (a fill fading to transparent still casts a full shadow).
- `background(gradient)` spans the screen (`left()`…`top()`), ignoring the camera; it replaces the
  autoclear only if every stop is opaque.
- Build one in `create` and keep it as a field (or in a `Style`): construction samples its ramp, and
  the GPU uploads one ramp per distinct set of stops.

**Shadows** are part of `Style`, **off by default**: `canvas.shadow(color=, offset=, blur=, spread=,
inset=)` switches one on (unset parts keep their values, so `shadow()` alone switches the current
one on; `blur`/`spread` default to a NaN "keep" sentinel, so `blur=12` works),
`shadow_enabled(False)` switches it off, and `canvas.style(...)` takes the same parts as `shadow*`
keywords.
- **One silhouette, like CSS `drop-shadow`:** fill plus outline cast together (outline only casts
  a ring); lines and arcs cast their stroke, text its glyphs, sprites their alpha. A translucent fill shows
  its own shadow through it. Clear, background and letterbox never cast.
- **`blur` is the CSS radius** (σ = blur / 2); `blur` and `spread` are world units, scaled like
  coordinates. Blur 0 is hard.
- **`shadow_inset`** paints inside the shape instead, after it, clipped to the interior within the
  outline. Rectangles, circles and triangles only — sectors, polygons, lines, arcs, text and
  sprites cast nothing while it is set.
- **The offset is screen-fixed** by default (`(4, -4)`, down-right): rotation doesn't turn it, but
  camera zoom and autoscale scale it. `shadow_follows_transform(True)` turns it with the shape.
- Shadows use the command's own opacity and blend mode.

**Opacity and blend modes reach every render call** (sprites included, `background()` never), and
every shape composites once: fill and outline never overlap, so a translucent shape is evenly
translucent.

**Scope with the guards.** `canvas.transform(m)`, `canvas.style(...)`, `canvas.overlay()` and
`canvas.clip(...)` return `with`-block guards that unwind on exit. Bare style mutators straight from `update` are fine (style,
transform and camera reset every frame); a *helper* that sets style wraps it in `canvas.style()` so it
can't leak into the caller's next render.

### Antialiasing

`run(..., antialiasing=Antialiasing.MEDIUM)` is the default; `OFF`, `LOW` and `HIGH` are the
others. One setting for both backends, each reaching it its own way: the GPU multisamples its
window, the CPU samples each shape on a finer grid (`LOW` 2x2, `MEDIUM` 4x4, `HIGH` 8x8 per pixel).
Shapes only — text and sprites are smooth already, clips stay hard. A shape's fill and outline
composite together, so no seam shows between them; two separate shapes meeting inside a pixel can
show a faint one. `run_headless` defaults to `MEDIUM` too, so a test asserting an edge pixel's exact
colour passes `antialiasing=Antialiasing.OFF`.

### Clipping

`with canvas.clip(region):` renders only inside `region` for the block; `invert=True` keeps only
what is outside it (fog, a spotlight). `region` is a `Rectangle`, `Circle`, `Triangle`, `Sector` or
`Polygon` — the region types of `contains`/`overlaps`. Guard-only: there is no bare clip to forget
to undo. See [examples/clipping.mojo](examples/clipping.mojo).
- **Frozen at the call**, like a render call: placed by the transform and camera current then. A
  `transform` or `overlay` inside the block moves what is drawn, not the clip.
- **Nested clips intersect.** On exit the enclosing clip is current again.
- **Everything is clipped** — shapes, sprites, text, shadows, and `background()`, which then paints
  only the clipped area (and never replaces the autoclear). The letterbox is not.
- **Hard-edged**, whatever the antialiasing: the clip covers the pixels a fill of the same shape
  would without it, on both backends.
  Soft masks (a gradient or a sprite's alpha) are not implemented yet.

### Reading pixels

`canvas.pixel(position) -> Color` and `canvas.snapshot([region], scale=1.0) -> Sprite` read what the
frame has drawn **so far**. They are a CPU replay of the commands recorded up to the call, like
`save_image`, so both backends read the same pixels and the GPU is never stalled. See
[examples/pixels.mojo](examples/pixels.mojo).
- **Screen space**, not world: the transform and camera don't apply. `canvas.pixel(context.input.mouse)`
  picks under the mouse as it is, and a snapshot region is always upright. Off the screen reads
  transparent.
- **Design resolution × `scale`**, without the letterbox. `snapshot()` drawn back with
  `canvas.sprite(shot, (0, 0), canvas.width, canvas.height)` lines up exactly;
  `scale=canvas.scale` gives window pixels.
- **One replay per drawing**: reads are cached until something more is recorded, so many `pixel`
  calls in a row cost one. A full-frame replay costs about a CPU frame. Fine for picking, a
  capture, or a feedback effect; read once rather than per object.
- **With `context.autoclear(False)`** a read starts from the last frame's pixels, as the frame did,
  from the frame after the first read on. The first read sees only its own frame. CPU backend
  only, the one that accumulates.

`Sprite.pixel(x, y)`/`set_pixel(x, y, color)` read and edit a sprite in **image coordinates** (top-left
origin, y down); off the image, reads are transparent and writes do nothing. The buffer is private:
every write goes through `set_pixel`, which versions the sprite so a render after the edit draws the
new pixels and one before it keeps the old ones. A sprite not drawn for `IMAGE_KEEP_FRAMES` (120)
frames is dropped from the backends' caches, so a fresh snapshot every frame costs bounded memory.

### Coordinates, camera, autoscale

**Not Processing's coordinates.** Origin at the screen centre, **y up**; `x ∈ [-w/2, w/2]`,
`y ∈ [-h/2, h/2]`. So `rotate` is counter-clockwise, gravity is negative `y`, and `canvas.left()`/
`bottom()` are negative — use the edge methods, not `width`/`height` arithmetic. Glyphs and sprites
are not flipped. **All shapes are centre-positioned**, including `Rectangle.position`.

**Camera:** `canvas.camera(cam)` maps world space onto screen space for every later render call and
nested transform, reset every frame. `canvas.overlay()` suspends it for HUD content.
`context.input.mouse` is in screen space; use `cam.to_world(context.input.mouse)` for picking.

```mojo
canvas.camera(self.cam)
canvas.sprite(self.player.sprite, self.player.position)     # world space
with canvas.overlay():
    canvas.text("Score: " + String(self.score), (0, canvas.top() - 20))  # screen space
```

**Design resolution** is the `width`/`height` passed to `run` (or `context.design_resolution()` from
`create`): the space the program is authored in, not a window size. Fullscreen/maximized scale the
design onto the display. `context.autoscale(mode)` takes `FIT` (default), `EXTEND` or `OFF`; `OFF` makes
coordinates the window's own pixels. Under `EXTEND` the reported size grows with the window, so
anchor layout to the edges. Font size, outline thickness and sprite size scale by `canvas.scale`. See
[examples/autoscale.mojo](examples/autoscale.mojo).

`Context` dials are methods (`context.autoclear(False)`, like the canvas style setters); its only
fields are the readings `time` and `input`. Dials are read at frame construction, so a change
mid-`update` applies next frame — except `max_frame_rate()`, `quit()` and `rumble()`, read after `update` returns.

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

5. **An uncalled overload is type-checked by nothing.** [tests/render/test_canvas.mojo](tests/render/test_canvas.mojo)
   renders through all of `canvas.sprite`'s animator overloads for this reason — extend it when adding
   one.

## Terminology

| Term | Meaning |
|---|---|
| Screen space | Origin-centred, y-up, camera-independent. `canvas.left()`…`top()` and `context.input.mouse` live here |
| World space | What render calls use once a `Camera` is set; identical to screen space without one. `canvas.to_world`/`to_local` convert a `Point2D` between world space and the current transform |
| Asset vs. playhead | `SpriteAnimation`/`Sound` are shared immutable assets; `SpriteAnimator`/an `Audio` voice are one entity's position in one. `fps` belongs to the asset |
| `Easing` / `Tween` | An `Easing` is a stateless curve over a 0-to-1 fraction (`ease(curve, t)`); a `Tween` walks that fraction over a duration. Each entity owns its own `Tween` |
| `Time` / `DateTime` | `context.time` is the run's clock: ticked by the loop, zero at the first frame, synthetic in headless runs. `DateTime.now()` is the computer's local wall clock, read once into consistent fields (`year` … `millisecond`) — take one reading per frame rather than calling it per field |
| `Random` / `Noise` | Both seeded, both in `[0, 1]`. `Random` is stateful (`mut`, `Movable`): each call is an independent sample. `Noise` is immutable (`Copyable`): `at(...)` is a pure function of its input, and nearby inputs give nearby values. `feature_size` divides space only; `at(position, time)` leaves `time` for the caller to scale. Averaged octaves cluster around 0.5 — stretch with `smoothstep` for contrast |
| `Gradient` | Stops (0..1 positions, each a `Color`) across a fill or the background. **Placed by the shape's local bounding box**, before the transform, so it moves and turns with the shape and one `Style` suits every entity. `linear` runs along `direction` (a `Vector2D`, default `DOWN`, any length; its extreme corners land on 0 and 1, as in CSS); `radial` runs from `center` in the box's unit space (-1..1, y up) out to its edges, an ellipse on a long box. A sector's box is its whole circle. A zero `direction` or a zero-size box paints the first stop. Blends premultiplied (a fade to `TRANSPARENT` stays clean) and is dithered on both backends |
| `Point2D` / `Vector2D` | Chosen by role. A location is a `Point2D` (`canvas.circle(position, r)`, `context.input.mouse`); a displacement is a `Vector2D` (`translate(delta)`, velocities); an extent is a scalar (`w`, `h`, `r`). `Point2D` deliberately lacks `mag`, `normalize`, `dot`, scalar `*`, unary `-` and `Point2D + Point2D`. Only `Point2D` takes a bare tuple implicitly; a vector literal names its type (`p + Vector2D(1, 2)`), and `p - (1, 2)` is the displacement from `(1, 2)`, not a move. Named vectors are `comptime` constants: `Vector2D.ZERO`, `ONE`, `UP`, `DOWN`, `LEFT`, `RIGHT` (y up, so `DOWN` is `(0, -1)`) |
| Down / pressed / released | Input state for keys, mouse and gamepad buttons alike. *Down* is held right now, true every frame (`key_down`, `mouse_down`, `pad.button_down`); *pressed*/*released* are edges, true only in the frame it went down or came up (`key_pressed`, `mouse_released`). Unlike Processing's `mousePressed`, *pressed* never means held |
| `Gamepad` | `context.input.gamepad(i)`, a copy of player `i`'s pad (default 0). A pad takes the lowest free slot as it connects and keeps it until it disconnects; an empty slot reads `connected` False and all zero, so no check is needed first. Sticks are `Vector2D`s, **y up**, inside the unit circle, with a rescaled radial dead zone (`Gamepad.STICK_DEAD_ZONE`, 0.2) so a resting stick reads exactly zero; triggers 0..1. Face buttons are positional (`GamepadButton.SOUTH` is Xbox A and PlayStation Cross). `connected_this_frame`/`disconnected_this_frame` are the edges of `connected`, and `name` survives the frame a pad leaves in. `context.rumble(seconds, low_frequency=, high_frequency=, player=)` shakes a pad (both motors full by default; a new rumble replaces the running one); it is an output, so it lives on `Context`, not on the `Gamepad` copy. See [examples/gamepad.mojo](examples/gamepad.mojo) |
| Typed / `text` | Text entry. `key_typed` is pressed or auto-repeated while held, for editing keys (Backspace, arrows); `context.input.text` is this frame's typed characters, UTF-8, with shift, layout and IME applied — append it, don't rebuild it from keycodes. Both reset every frame. `EditableText` does the editing: fed `context.input` each frame, it keeps `text` and a caret, whole characters at a time; `canvas.text_width(field.before_caret())` places the caret. See [examples/typing.mojo](examples/typing.mojo) |
| `overlaps` / `intersects` / `contains` | `overlaps(a, b)`: free, symmetric, regions only (`Rectangle`/`Circle`/`Triangle`/`Sector`/`Polygon`). `curve.intersects(x)`: `Line` and `Arc` only, since a curve has no interior. `region.contains(x)`: asymmetric, every region against every region and `Line`. A `Line` or `Arc` is never a region |
| Sweep | `Arc` and `Sector` share `position` (the circle's centre), `r`, `start_angle` and a **signed** `sweep_angle`, in radians from +x: positive is counter-clockwise (y is up), negative clockwise, and \|sweep\| ≥ tau is the whole circle. Stored as given, so `==` and printing round-trip; `end_angle()` is `start_angle + sweep_angle` |
| `Arc` | A curve, like `Line`: no interior, never in `overlaps`. Constant speed, so `at_distance(d)` is exact. `beziers()` splits it into Béziers of at most 45°; `canvas.arc` strokes those as one chain, like `canvas.spline` |
| `Sector` | A pie slice, a region: its tip at `position`, fanned out to its arc. Wider than a half turn it is not convex — the missing wedge is outside it, for `contains` and `overlaps` alike. `center()` is `position`, like `Circle`'s, not the centroid. `canvas.sector` insets its outline as a circle's; no `corner_radius`, no inset shadow |
| `Polygon` | Any `vertices`, in order, closed back to the first: concave or crossing itself, a region. Inside by the **nonzero rule** (a pentagram of five crossing vertices is solid through its middle), vertex order irrelevant, boundary inside. `Polygon.regular(position, r, sides)` and `Polygon.star(position, r, inner_r, tips)` start at `start_angle`, straight up by default. `center()` is the area centroid and `area()` the shoelace area, both meaningful only for a simple polygon. `canvas.polygon` insets its outline along the outside but centres it on an edge running through the inside (a pentagram's inner pentagon), so every edge is stroked as thick; no `corner_radius`, no inset shadow. Outlined, a 5-tip star costs ~115 µs a frame, a pentagram ~195 µs, a 40-tip star ~2.4 ms |
| `Bezier` | A cubic Bézier: `start`, `control1`, `control2`, `end`; passes through the endpoints only. A curve, not a region: `canvas.bezier` strokes it in the outline style and draws nothing with the outline off. `at(t)` is uneven in speed; `at_distance(d)` moves along it at constant speed |
| `Spline` | A smooth curve through every one of `points`, in order (Catmull-Rom); `closed` runs it on back to the first. `alpha` spaces its knots: 0 uniform (can loop where points bunch), 0.5 centripetal (default, never does), 1 chordal. Same sampling methods as `Bezier`, `t` split evenly per stretch. `beziers()` converts it exactly; `canvas.spline` draws it as one stroke of those Béziers |

## Do

- Use `@fieldwise_init` on program structs.
- Run only the tests a change can reach (`pixi run test render`); pre-push runs the whole suite.
- Make `canvas.background(...)` the first render call in `update`. With `context.autoclear` off,
  call it on the first frame only.
- Use `Point2D` for new locations, `Vector2D` for displacements and scalars for extents;
  `canvas.rectangle(position: Point2D, w: Float64, h: Float64)` is the shape to copy.

## Don't

- Don't use `alias` — deprecated for `comptime`.
- Don't use `UnsafePointer` — deprecated for `Pointer`.
- Don't use `fn` — removed; use `def`.
- Don't hold a raw `Pointer` to `Canvas` outside the guards; use origin-tracked references.
- Don't name a test file without the `test_` prefix; the runner won't find it.
- Don't take a location as separate `x, y` scalars, not even as a convenience overload beside the
  `Point2D` one: a bare tuple already fills a `Point2D` parameter, and `(x, y)` keeps the pairs
  readable where a run of numbers doesn't.
- Don't give any type but `Point2D` an `@implicit` tuple constructor: a second one makes every
  overload pair taking the two types ambiguous for a bare tuple, and locations are the literals worth
  the shorthand. Don't add `Point2D.__add__(Point2D)` either — the type exists to refuse it.
