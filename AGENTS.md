# AGENTS.md — Mojo Create

## Purpose

Mojo Create is a creative coding library for rapid prototyping and interactive graphics, inspired by Processing but built to scale — from sketch to game, prototype to full application. It provides a clean, modular API while taking full advantage of Mojo's performance and language features.

**The library is in early development.** No public release exists yet and no external consumers depend
on the current API, so breaking changes are expected and should not be avoided for their own sake. 
Thereby follows that documentation churn and examples or tests needing to be rewritten are not by 
themselves reasons to reject a new idea. Weigh a change on whether it makes the library better, not on 
how much of the repo it touches.

## Design Ethos

Mojo Create follows these principles:

- **Prioritize API intuitiveness.** Avoid non-obvious abbreviations and refer clarity over brevity when naming.
- **Prioritize consumer ergonomics.** Do not sacrifice usability merely to minimize the API surface.
- **Keep the common path simple.** Simple sketches should require minimal ceremony.
- **Keep the architecture modular.** Separate concerns appropriately and minimise coupling between components.
- **Consistency is key.** Similar concepts should behave and be named consistently throughout the API.
- **Make good performance the default.** Users should not need to understand the library's internals or use specialised APIs to get good performance.

The goal is **Processing's ergonomics + clean separation of concerns + Mojo's performance**.

## Module Layout

| Module | Path | Responsibility |
|---|---|---|
| root | `src/create/__init__.mojo` | The preamble — `from create import *`, the union of every subpackage below |
| `core` | `src/create/core/` | Program trait, run loops, Input, Key, script_dir |
| `render` | `src/create/render/` | Frame, Time, DrawCommand, Backend, Surface, Viewport, AutoScale, Style, Color, Font, text layout, raster primitives, the GL renderer |
| `math` | `src/create/math/` | Point2D, Vector2D, Vector3D, Matrix, geometry shapes, random, util, easing curves and tweens |
| `sprite` | `src/create/sprite/` | Sprite — BMP/PNG/JPEG loading and raw pixel buffer; SpriteAnimation, SpriteAnimator — frame-based animation |
| `audio` | `src/create/audio/` | Sound, Audio — WAV/OGG/FLAC/MP3 loading and playback |
| `_bytes` | `src/create/_bytes.mojo` | Internal leaf — little-endian integer decoding. Imports nothing, re-exported by nothing |

## Key Files

| File | Purpose |
|---|---|
| `src/create/core/program.mojo` | Defines the `Program` trait |
| `src/create/core/run.mojo` | `run[T](title, mode, width, height, backend, resizable)` — the windowed entry point; `mode` and `backend` are the typed selectors `WindowMode`/`RenderBackend`, which is what lets `mode` precede the size without a keyword; `width`/`height` are the design resolution, not a window size (see its docstring); dispatches to the GPU loop when `backend == RenderBackend.GPU` |
| `src/create/core/_step.mojo` | `step[P]` — one frame: build the `Frame` from the state and the program's `Options`, update, letterbox, release. The one copy, shared by both loops |
| `src/create/core/headless.mojo` | `run_headless[T](width, height, frames, pixel_width, pixel_height, backend)` — same loop, owned buffer, no window; dispatches to `_headless_gl.mojo` when `backend == RenderBackend.GPU` |
| `src/create/core/_headless_gl.mojo` | `_run_headless_gl[T]` — `run_headless`'s GPU counterpart: the same frames through the GL backend into an offscreen `_GLTarget`, read back once at the end |
| `src/create/render/time.mojo` | `Time` — frame delta, frame count, elapsed seconds. In `render` because `Frame` carries it, and `render` may not import `core` |
| `src/create/core/input.mojo` | `Input` — keyboard state, mouse position/buttons |
| `src/create/core/key.mojo` | `Key` — named keycodes for the `Int` overloads |
| `src/create/core/path.mojo` | `script_dir()` — the directory of the running program, for asset paths |
| `src/create/render/frame.mojo` | `Frame` — the one per-frame object: geometry (`width`/`height`/`left`/`right`/`bottom`/`top`), the clock, and the drawing API. Records `DrawCommand`s; touches no pixels. Also `PersistentFrameState`, what survives the frame boundary |
| `src/create/render/options.mojo` | `Options` — the dials that outlive a frame: `autoscale`, `autoclear`, `clear_color`, `letterbox`, `quit_on_escape`, `design_resolution()`, `frame_cap()`, `quit()`. Handed to `create` on its own, and to `update` alongside the `Frame` |
| `src/create/render/_command.mojo` | `DrawCommand` — one recorded draw, local geometry + transform + resolved `Style`; the per-kind constructor helpers |
| `src/create/render/render_backend.mojo` | `RenderBackend` — the `CPU`/`GPU` backend-selector constants |
| `src/create/render/_backend.mojo` | `Backend` — owns the fonts, glyph cache and interned sprite images; replays a frame's `DrawCommand`s onto a `Surface` (`present`) or through GL (`present_gpu`) |
| `src/create/render/surface.mojo` | `Surface` — a borrowed RGBA framebuffer; `MemorySurface` — one backed by owned memory. The CPU backend's replay target, not `Frame`'s |
| `src/create/render/_png.mojo` | `write_png` — an RGBA buffer out to a PNG file through libpng's simplified API. Knows nothing about what the pixels mean, so both capture kinds use it |
| `src/create/render/_raster.mojo` | Free functions over a `Surface`: `blend`, `fill_span` and every fill/line/triangle/blit built on it. Called only from `_backend.mojo` |
| `src/create/render/_gl.mojo` | The GL 3.3 entry points, resolved at runtime through SDL's loader and held as bitcast function pointers. The only file that talks to the driver |
| `src/create/render/_gl_target.mojo` | `_GLTarget` — an offscreen framebuffer object sized exactly to a requested resolution, for the parity test and the headless GPU path, neither of which can trust a window's own drawable to be the size they asked for |
| `src/create/render/_tessellate.mojo` | `DrawCommand` to triangles: the CPU-side geometry the GPU replays, transform baked per-vertex |
| `src/create/render/_fillet.mojo` | Corner-radius geometry shared by both backends: `rect_corner_radius`/`triangle_corner_radius` clamp a requested radius to what a shape can hold, `corner_fillet` returns one vertex's fillet centre, tangent points and arc angles — no shape-specific special-casing, so `_backend.mojo` and `_tessellate.mojo` round rectangles and triangles from the same numbers |
| `src/create/render/_gl_backend.mojo` | `GLRenderer` — the shader, the vertex buffer, the glyph atlas and sprite textures, and the batching that replays a frame in one draw call where it can |
| `src/create/core/_run_gl.mojo` | `run_gl[T]` — the GPU run loop: a `GLWindow`, the same `step`, `present_gpu` plus a buffer swap |
| `src/create/render/viewport.mojo` | `Viewport` — the design-space-to-pixel mapping, autoscale arithmetic, base matrix |
| `src/create/render/camera.mojo` | `Camera` — position and zoom mapping world space onto screen space; `frame.camera()`/`frame.overlay()` are its `Frame`-side surface |
| `src/create/render/autoscale.mojo` | `AutoScale` — the `FIT`/`EXTEND`/`OFF` mode constants |
| `src/create/render/_style.mojo` | `Style` — fill, outline, font settings; rebuilt fresh each frame, scoped by `frame.style()` |
| `src/create/render/_text.mojo` | `TextRenderer` — font loading, glyph cache, text layout |
| `src/create/render/font.mojo` | `Font`, `FontWeight`, and the paths of the two packaged Noto faces |
| `src/create/render/align.mojo` | `Align` — the nine points of a box (`TOP_LEFT`/`TOP`/…/`CENTER`/…/`BOTTOM_RIGHT`), one value for both axes |
| `src/create/render/color.mojo` | `Color` — constants, `hex`/`hsv`/`lerp` factories, `over` compositing |
| `src/create/math/point2d.mojo` | `Point2D` — a position: `Point2D - Point2D -> Vector2D`, `Point2D + Vector2D -> Point2D`, `dist`, `lerp`, `xy`/`xyz`, and deliberately nothing else |
| `src/create/math/vector2d.mojo` | `Vector2D` — an extent or a displacement: the full linear surface, `mag`, `normalize`, `dot`, scalar `*`, `zero()`/`one()` |
| `src/create/math/vector3d.mojo` | `Vector3D` — the same surface plus `cross`. Nothing in the library takes one; it is for a program doing its own 3D work |
| `src/create/math/geometry.mojo` | `Rectangle`, `Circle`, `Line`, `Triangle`; the `overlaps`/`intersects`/`contains` relation taxonomy (see Terminology) |
| `src/create/math/matrix.mojo` | Generic `Matrix[rows,cols]` with 2D/3D transform constructors |
| `src/create/math/random.mojo` | `Random` — seeded generator: `float`, `int`, `bool` |
| `src/create/math/easing.mojo` | `Easing` — the named curve constants; `ease(curve, t)` — reshape a 0-to-1 fraction |
| `src/create/math/tween.mojo` | `Tween` — the playhead over one value, `start` to `end` over a duration |
| `src/create/math/util.mojo` | `lerp`, `map`, `norm`, `smoothstep`, `sign`, `fract`, `fmod`, `degrees`, `radians` |
| `src/create/sprite/sprite.mojo` | `Sprite` struct + BMP/PNG/JPEG parsers |
| `src/create/sprite/animation.mojo` | `SpriteAnimation` — frame sequence + fps; `from_sheet`, `from_folder` |
| `src/create/sprite/animator.mojo` | `SpriteAnimator` — the playhead over one animation |
| `src/create/audio/sound.mojo` | `Sound` — decoded PCM + format/channels/freq, `load`/`from_pcm` |
| `src/create/audio/audio.mojo` | `Audio` — playback device, voice lifecycle, `play`/`stop`/`update` |
| `src/create/_bytes.mojo` | `le_uint`, `sign_extend_32` — the one byte-assembly loop, shared by the image decoders and the freetype struct readers |

## Build & Test

```bash
# Run any file
mojo run -I src examples/sketch.mojo

# Pixi shorthand for examples
pixi run create examples/sketch.mojo

# Run all tests — falls back to SDL's offscreen video driver with no display
# (DISPLAY, WAYLAND_DISPLAY and XDG_RUNTIME_DIR all unset), so the GL tests
# still run rather than skip
pixi run test

# Run a single test file
mojo run -I src tests/math/test_vector2d.mojo

# Type-check the whole library without running anything (output goes to build/, gitignored)
pixi run precompile

# Format every source file in place (80 columns, enforced by the pre-commit hook)
pixi run format

# One-time setup (points core.hooksPath at .githooks, ignores reformats in blame)
pixi run setup
```

Two git hooks gate the repo; there is no CI, so these are the only automated checks.

| Hook | Runs | Cost |
|---|---|---|
| `.githooks/pre-commit` | Checks the staged `.mojo` files are formatted, then builds `tests/core/test_smoke.mojo` | Constant — does not grow with the repo |
| `.githooks/pre-push` | `mojo precompile src/create`, all example entrypoints in parallel, then the test suite | Grows with the example and test count |

Neither runs until `pixi run setup` has been done in the clone, which also points
`blame.ignoreRevsFile` at `.git-blame-ignore-revs` so the bulk reformat listed there stays out of
`git blame`. Both block on breakage — breaking
the core API aborts commits; a library type error, a broken example, or a failing test aborts
pushes. `--no-verify` skips them, and is for WIP checkpoints on a scratch branch that get squashed
before landing, never on `main`.

The two tiers catch different things and neither subsumes the other: building a consumer program
type-checks only the `def` bodies it reaches, so it catches API drift but not a broken library
function nothing calls; `mojo precompile` is the reverse.

`mojo format` has no `--check` mode, so the hook formats a copy of the *index* content (`git show
:path`) and diffs it back — an unstaged edit can therefore neither mask nor cause a failure. The
formatter's grammar is narrower than the compiler's in two ways that will abort a commit outright
rather than reformat: `where` is reserved, so it cannot be a parameter or variable name, and `;` as
a statement separator does not parse, so one declaration per line.

## Testing

Tests use `std.testing.TestSuite`. Every `tests/**/test_*.mojo` file is a program whose `main`
discovers and runs the `test_*` functions in its own module:

```mojo
from std.testing import TestSuite, assert_equal, assert_true, assert_false

def test_thing_does_what_it_says() raises -> None:
    assert_equal(actual, expected)

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
```

A file reports PASS/FAIL per test and exits non-zero if any failed. `pixi run test` runs under
`set -e`, so the first failing *file* stops the suite — but within a file every test still runs.

Rendering is tested for real. [`run_headless`](src/create/core/headless.mojo) drives a program over
an owned `MemorySurface` and hands the buffer back; `MemorySurface.pixel(x, y)` reads one pixel out.
So [tests/render/test_frame.mojo](tests/render/test_frame.mojo) asserts on centring, y-up
orientation, alpha compositing, outline scaling, letterbox bars and sprite blits instead of eyeballing
them, and [tests/core/test_step.mojo](tests/core/test_step.mojo) scripts an `Input` and calls `step`
directly to drive click- and key-driven behaviour with no window.

GPU coverage is two tiers, and they catch different things. [tests/render/test_gl_parity.mojo](tests/render/test_gl_parity.mojo)
is what keeps the two backends honest: one shape kind per frame, drawn through `run_headless` and
through a GL framebuffer object, compared structurally rather than pixel by pixel — bounding box,
centroid and ink coverage, each within a tolerance sized for rasteriser disagreement, plus the
interior colour away from every edge. Structural rather than exact because two rasterisers are
entitled to disagree at the edges (integer vs. float coverage, different fill rules) without either
being wrong, and because a pixel-exact comparison would forever forbid antialiasing the GPU path. A
failure names the shape kind rather than a pixel count. It draws one shape kind per frame by design,
so it cannot reach anything that only exists across several draws in one frame.

That's the other tier's job: `run_headless(..., backend=RenderBackend.GPU)`
([tests/render/test_headless_gl.mojo](tests/render/test_headless_gl.mojo)) drives a program through the
GL backend alone, with no CPU frame to compare against, for behaviour that parity is structurally
blind to — [tests/render/test_gl_batching.mojo](tests/render/test_gl_batching.mojo) covers the batch
breaks (an opaque clear, a second sprite texture) and the vertex buffer surviving reuse past its
first-frame capacity; [tests/render/test_gl_capture.mojo](tests/render/test_gl_capture.mojo) covers
the two GPU-only capture paths — `save_screenshot`'s real `glReadPixels` stall and forced opacity,
and `save_image`'s byte-for-byte agreement with the CPU backend's own capture, which holds because
both replay the same recorded commands through the same CPU code regardless of which backend drew
the live frame.

Every GL test skips itself with no GL context, and none needs a display to get one: SDL3's offscreen
video driver gives a working GL 3.3 context headless, and `pixi run test` switches to it whenever
`DISPLAY`, `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` are all unset. Offscreen is likely software
rasterisation (llvmpipe or similar), which is fine for what these tests check — batching, texture
units, buffer growth, the readback path, geometric agreement between backends are all library-logic
bugs a software rasteriser catches as well as any GPU — and blind to bugs specific to a real driver,
which were never in scope. The drawable-versus-logical-size distinction (Gotcha 6) has no offscreen
counterpart: an FBO has one size and no window manager to disagree with it, so that stays a
windowed-only concern.

`tests/core/test_smoke.mojo` is both: the pre-commit hook builds it, and `pixi run test` runs it
through `run_headless`. Its `_windowed_entry_point` is never called — `run[T]` opens a window and
blocks — but an uncalled `def` body is still type-checked, so the windowed path stays gated. Keep the
file minimal: it builds on every commit, and its cost must not grow with the example count.

## Code Conventions

**Defining a program:** implement `Program` (`create` + `update`) and pass it to `run[T]`. See [examples/sidescroller/src/main.mojo](examples/sidescroller/src/main.mojo) for the full shape, or [tests/core/test_smoke.mojo](tests/core/test_smoke.mojo) for the minimum. Both are compile-gated, so neither can go stale.

**Imports: `from create import *` is what a program writes.** It is the whole public surface in one
line. Every example and every test uses it.

Each subpackage exports the names it owns and nothing from a layer below:

- `from create.core import *` — `Program`, `run`, `run_headless`, `Input`, `MouseButton`, `Key`, `script_dir`.
- `from create.render import *` — `Frame`, `Options`, `PersistentFrameState` and the frame guards, `Time`, `Camera`, `Surface`/`MemorySurface`, `Viewport`, `Color`, `Font`/`FontWeight`, `Align`, `AutoScale`, `RenderBackend`.
- `from create.math import *` — `Point2D`, `Vector2D`/`Vector3D`, `Matrix` and its constructors, the geometry shapes and `overlaps`, `Random`, `Easing`/`ease`/`Tween`, the util functions, and a re-export of `std.math` (`sin`, `cos`, `sqrt`, `clamp`, `pi`, `tau`, …).
- `from create.sprite import *` — `Sprite`, `SpriteAnimation`, `SpriteAnimator`.
- `from create.audio import *` — `Sound`, `Audio`.

So there are two shapes and no middle one: take the preamble whole, or name what you import from
the package that defines it (`from create.math import overlaps`, `from create.core import
script_dir`). Star-importing a single subpackage is not a preamble — `from create.core import *`
alone cannot name `Frame`, and is not meant to.

**The root is the union.** [`create/__init__.mojo`](src/create/__init__.mojo) has no signatures of
its own; it star-imports all five subpackages, which is what makes it exactly their union and keeps
it from drifting as they change. Adding a name there is never right — add it to the subpackage that
owns it and the root picks it up. Likewise, a subpackage never re-exports a symbol from a lower one:
`core` names `Frame` and `Rectangle` in its signatures but exports neither, because the root already
carries them and nothing else asks. 

**Public surface is exactly what an `__init__.mojo` re-exports, and the compiler enforces it.** A
star import skips `_`-prefixed top-level declarations and reaches nothing a package's
`__init__.mojo` does not list — `le_uint` and `Style` are unreachable through `from create.render
import *` no matter which module defines them. The underscore marks the rest, at two levels:
`_name` for a declaration internal to an otherwise-public module (`_GlyphInfo` beside the exported
`Font`, `_KeyBits` beside `Key`, `_Voice` beside `Audio`), and `_module.mojo` for a whole internal
file — `_raster.mojo`, `_style.mojo`, `_text.mojo`, `_step.mojo`, `_bytes.mojo`, `_sdl_audio.mojo`,
`_sndfile.mojo` — whose contents then need no individual prefix. Both stay importable by an
explicit path, which is how the tests reach `step`, `blend` and `le_uint` without any of them being
public.

So a new declaration is internal unless it is being added to an `__init__.mojo` in the same breath.
Put it in a `_module.mojo` if the whole file is plumbing; give it a `_name` if it sits in a module
users import from.

**`_bytes` is a leaf, and deliberately outside every package.** It imports nothing, and no
`__init__.mojo` re-exports it. `sprite` and `render` both need to assemble little-endian bytes into
an `Int` and neither may depend on the other, so the one copy of that loop lives at the root where
both can reach it. It is internal plumbing, not public surface — adding it to an `__init__.mojo`
would be wrong, since no user-facing signature names `le_uint` or `sign_extend_32`. `render`
importing it is not a violation of the `render`-never-imports-`core` rule: `_bytes` is not `core`,
and depending on a leaf cannot make a cycle.

**The `render`-to-`sprite` edge is nominal.** `render` names `Sprite` and `SpriteAnimator` only in
`frame.sprite`'s overloads — no `render` code depends on what those types
contain. `raster.blit_sprite` takes a pixel pointer plus its width and height rather than an image type, so
the rasteriser is written against no layout but its own and the BMP/PNG/JPEG decoders stay out of the
render path entirely. Keep it that way: a new `render` function that needs pixels takes the buffer,
not the type that owns it.

**`render` never imports `core`.** Every edge between them runs one way — `program`, `input`,
`run`, `_step` and `headless` reach into `render`, and nothing comes back. That is what lets
`render` be split off at all, and a package boundary now enforces it: an import the other way is a
cycle, not a style violation. `render` depends only on `math` and `sprite`, so the whole drawing
stack is usable without a run loop, which is what `run_headless` already relies on.

**A `Program` can own `Program`s.** Multiple screens are not a distinct feature: a root `Program`
holds each screen as a plain field, with the same `update` shape but *not* implementing the
trait — a trait would force one `update`/`enter` signature across every screen, which is the one
thing that must vary — and switches with an int field and an `if`/`elif`:

```mojo
def update(mut self, mut options: Options, mut frame: Frame, input: Input) raises:
    if self.scene == MENU:
        self.menu.update(frame, input)
    else:
        self.game.update(frame, input)
```

A scene takes only what it uses — the two above touch no dials, so neither takes an `Options`.
Pass it down (`self.menu.update(options, frame, input)`) only for a scene that sets one.

A scene needing a one-shot reset on entry gets a plain method (`enter()`) the parent calls right
before flipping the field; it is not part of `Program` and costs nothing to scenes that don't need
it. See [examples/scenes/src/main.mojo](examples/scenes/src/main.mojo) for a full menu/drawing-surface
pair, including that hook and `options.autoclear = False` so ink accumulates across frames.

That `enter()` is where a transition carries state — it takes whatever arguments the entering scene
needs (`enter(from_door: Int)`), and state shared by *all* scenes is a field on the parent passed
down as a `mut` parameter, alongside `Frame`. Both are lost the moment a trait imposes a uniform
signature, which is the real argument against one; it is not that a trait is impossible. Mojo 1.0
has no dynamic trait dispatch — a trait in type position forms an inert `AnyTrait[T]` that nothing
converts into and no method can be called on — but `Variant` over a closed set of scene types does
give heterogeneous storage, so a scene *stack* (pause over game, modal dialogs) is buildable if one
is ever needed. It buys storage only: dispatch is still a branch at each use site, `s.isa[Menu]()`
in place of `self.scene == MENU`. One active scene needs no stack, so the fields stay plain.

**A draw call records; it never paints.** `frame.rectangle(...)`, `.circle(...)`, `.sprite(...)`,
`.text(...)` and the rest each build a [`DrawCommand`](src/create/render/_command.mojo) — local
geometry, the transform in effect, and the style resolved *now* — and append it to the `Backend`'s
recording. Nothing is rasterised until `Backend.present` replays the whole buffer at the end of the
frame, so a later `frame.fill()` can never reach back and change what an earlier command paints. A
sprite is interned into the backend's image cache at record time (so the command carries an id, not
a borrow of caller-owned pixels); text is deferred whole, as an owned `String` — its layout is
resolved at replay, in the backend that owns the fonts. Add a new shape by extending
`_command.mojo`'s kind constants and `_backend.mojo`'s replay, not by having `Frame` call
`_raster.mojo` directly — `Frame` has no `Surface` to call it against.

**The command buffer exists so a frame can be replayed by either backend, and both now exist.**
`Backend` carries a `kind` — `RenderBackend.CPU` replays onto a `Surface` through `_raster.mojo`,
`RenderBackend.GPU` replays through `GLRenderer` in [_gl_backend.mojo](src/create/render/_gl_backend.mojo)
— and a `kind` rather than a trait object because Mojo 1.0 has no dynamic trait dispatch. Users
select one with `run[T](..., backend=RenderBackend.GPU)`; the default is unchanged.

**A capture is serviced inside `present`/`present_gpu`, never from the run loop.**
`frame.save_image` and `frame.save_screenshot` file a request on the `Backend` and return;
the file is written when the frame is presented. That is not laziness — `present` is the only
place that holds both halves at once: the finished framebuffer (what a screenshot is) and the
frame's command buffer, still unconsumed (what an image is replayed from). Filing a request also
makes the call position-independent: the image holds the whole frame however early in `update` it
was asked for. A failed write raises out of `present`, like a missing font does.

`save_image` re-rasterises **on the CPU under both backends**, through `replay` with the capture's
own pre-matrix (`capture_view.base_matrix() @ frame._base_inv`) and `CMD_LETTERBOX` masked out.
That is possible because the glyph cache and the interned images live on `Backend`, not on
`GLRenderer` — so a GPU frame is captured at a resolution the window never had, with no
`glReadPixels` and no stall. The screenshot is the opposite trade: the CPU path is a `memcpy` of
the `Surface`, and the GPU path is a `GLRenderer.read_frame` readback, which does stall the
pipeline for that one frame. Acceptable on a keypress, not per frame — and the capture doubles the
frame's rasterisation cost on the frame it happens, whichever kind it is.

[examples/screenshot.mojo](examples/screenshot.mojo) demonstrates both, side by side: resize
the window and the screenshot follows it while the image never does.

**A CPU rasteriser computes the covered run per row and hands it to `fill_span`; `blend` is only
for genuinely scattered pixels.** `fill_span` ([_raster.mojo](src/create/render/_raster.mojo)) is
the one place a horizontal run of pixels gets composited — it hoists the opaque-word-store and
alpha-hoisted-test tricks out of the loop and vectorises four pixels at a time, so a call site
never re-open-codes either trick. Every fill, the triangle rasteriser, the rotated/sheared
rect and circle paths, and the vertical-dominant case of `line_pixels` all resolve a row (or
column, for a mostly-horizontal thick line) to a `(start, count)` pair first and then call
`fill_span` once — never per pixel. `blend` stays for pixels that genuinely aren't a run: glyph
coverage and sprite texels, where each pixel's alpha differs from its neighbour's. A new shape
follows the same shape: solve the row's covered interval analytically or by clipping, not by
testing every pixel in a bounding box.

The GPU path is OpenGL 3.3 and works like this. `_tessellate.mojo` turns each `DrawCommand` into
triangles on the CPU, baking that command's transform into every vertex, so the shader needs no
per-draw uniform and consecutive commands can share one buffer. A vertex is nine `Float32` — `x, y,
u, v, r, g, b, a, mode` — and `mode` picks solid, glyph-mask or texture sampling in the fragment
shader. Everything accumulates into one vertex `List` and flushes as a single `glBufferData` plus
`glDrawArrays`. A batch breaks on only three things: an opaque `CMD_CLEAR` (a `glClear` resets the
framebuffer, so whatever was queued before it must have landed first), a *second* distinct sprite texture,
and the end of the frame. Solids, glyphs and one sprite coexist in a batch because the glyph atlas
lives permanently on texture unit 0 and sprites go on unit 1, so neither displaces the other. Per
frame the only GL state written is the viewport pair, and only when the drawable resized — the
program, the VAO and the sampler uniforms are set once at construction.

Measured on `examples/gl_bench.mojo` (2000 animated shapes, 2 sprites, one text line) at 1920x1080
on a Ryzen 5 2600X / RTX 2070, rolling mean over 120 frames with vsync off, GPU backend: **~1.1 ms
per frame**. Both draw the identical frame. Two things to know before optimising the GPU path
further: the vertex `List` reaches its capacity in the first frame and never reallocates again,
and orphan-then-`glBufferSubData` measured identical to the single `glBufferData` now in use —
respecifying the store *is* the orphan, so the pair was doing the same work twice.

The CPU backend went through a dedicated pass (see `examples/cpu_bench.mojo`, which measures
rasterisation alone, headless, with no window present) after an early draft of this file recorded
its per-frame cost as "71 ms" — that number was actually the *fps* reading (71.6 fps, i.e. ~13.9
ms/frame) transcribed as if it were milliseconds. The real starting point was **~12.5 ms** of raster
work for that same 2000-shape frame; after replacing every "test every pixel in a bounding box"
rasteriser with one that computes the covered run per row and hands it to `fill_span` (rects,
circles, triangles, the rotated/sheared path, sprite and glyph blits, and thick lines), the
identical frame now rasterises in **~3.5 ms** headless. The CPU backend's real windowed frame time
also includes SDL's blit of the finished surface to the screen, which this work does not touch and
which is not reflected in that number.

**Three FFI ground rules, and they are the real constraint on `_gl.mojo`.** GL entry points are
resolved at runtime through SDL's loader and called through a bitcast `thin abi("C")` pointer. That
works — under `mojo run` and `mojo build`, 64-bit pointer out-parameters included. (An earlier
version of this file blamed a Mojo codegen bug for a stalled first attempt. **That was wrong and is
retracted**; all three symptoms were the mistakes below.)

1. **A `String` whose pointer is handed to C must outlive the call.** `Int(s.unsafe_ptr())` erases
   the origin, so the optimizer may destroy `s` first; `dlsym` then reads garbage and returns NULL,
   and calling address 0 segfaults. Put `_ = s` after the call, and test every resolved address
   against 0.
2. **Read a C out-parameter back from heap memory, not a local `InlineArray`.** The write lands, but
   `MutUntrackedOrigin` gives the optimizer no aliasing information, so a following `buf[0]` on a
   local array can be served stale from a register. A `List` buffer reads back correctly.
3. **Keep the GL context owner alive past the last GL call.** Destroying a `GLWindow` tears down the
   context and every call after that segfaults. In a run loop the window is alive by construction;
   this bites in tests and spikes, where `_ = win^` at the end is the fix.

**`render` reaches GL without importing `window`.** The layering rule is unchanged, so `_gl.mojo`
cannot take a `GLWindow` or use its `get_proc_address`: it `dlopen`s SDL itself and resolves through
`SDL_GL_GetProcAddress` (refcounted, so a second handle alongside `mojo-window`'s is harmless, and
SDL's loader is used rather than plain `dlsym` because extension entry points need not be in the
process's symbol table). A context must already be current when `GL()` is constructed — `run_gl`
guarantees that by creating its `GLWindow` first.

**`Frame` is a per-frame recorder, not a persistent object, and it holds no `Surface`.** The run
loop builds a fresh one each frame from that frame's `Viewport` and drops it before presenting. A
draw call appends a `DrawCommand` — local geometry, the current transform, the resolved `Style` —
to the `Backend`'s recording; `Frame` never touches a pixel, which is what makes `run_headless`
possible at all and is also why `Frame` needs no framebuffer parameter. Anything that must survive
the frame boundary lives in one of two places: the library's own carry-over in
`PersistentFrameState`, which holds the `Backend` (and, through it, the loaded fonts, glyph cache and
interned sprite images), the `Viewport` and the clock, moved in at construction and back out by
`_release`; and the program's dials in `Options`, which the loop owns outright and passes by
reference to both `create` and `update`. The transform stack and the style deliberately do **not**:
every frame starts unrotated, untranslated and at the default style, so a missing pop or a forgotten
`outline(enabled=False)` cannot leak into the next one. Nothing may hold a `Frame` across frames; hold the
`PersistentFrameState` instead.

Both loops share [_step.mojo](src/create/core/_step.mojo)'s `step` for the frame body, so the windowed
and headless paths cannot drift in what a frame *is*; they differ only in how one gets started (SDL
events and a clock, versus a counter) and in where the `Surface` they hand to `Backend.present` comes
from.

**A `Frame` takes its geometry from the `Viewport` alone — it never sees a `Surface`.** The
`Surface` a frame renders onto is taken later, at `Backend.present`, after `Frame` has already
recorded and been released. That is later than it used to be: `Window._resize` reallocates the pixel
buffer inside `win.events()`, so the `Surface` passed to `present` must still be taken *after* event
processing, and its width and height must come from the window, never from the viewport. A lagging
mapping is one crooked frame; a lying extent is memory corruption, because the extent is baked into
the `Surface` and so defeats the clipping every raster loop otherwise does.

**Scope through the guards, never by hand.** `frame.transform(m)` and `frame.style()` both return
a `with`-block guard that unwinds on exit; `frame._push_transform` is the same push without the pop.
Style is the subtler of the two: the bare mutators (`fill`, `outline`, `font_size`, …) called
straight from `update` are the normal path, since the style resets next frame either way — the guard
is for a *helper* that sets style before drawing, whose `outline(enabled=False)` would otherwise apply to
whatever the caller draws next.

```mojo
with frame.style():
    frame.outline(enabled=False)
    frame.fill(Color(220, 80, 80))
    frame.rectangle(self.pos, 40, 40)
```

**Coordinate system is not Processing's.** The origin is the **middle** of the screen area and **y grows upward**. Screen `x` runs `[-width/2, +width/2]`, `y` runs `[-height/2, +height/2]`; `(0, 0)` is the centre of the screen and negative `y` is below it.

`Frame` exposes `left()`, `right()`, `bottom()`, `top()` as the edges — use those rather than `width`/`height` arithmetic, and note `left()` and `bottom()` are negative. `Rectangle.top()` is `y + h/2`.

Consequences worth internalising:

- `rotate(angle)` turns **counter-clockwise**, the mathematical convention.
- Downward motion is negative: gravity is a negative `vel_y`, a jump is positive. See [examples/sidescroller/src/player.mojo](examples/sidescroller/src/player.mojo).
- Glyphs and sprites are **not** flipped — only their anchor point is mapped.
- `input.mouse` is delivered in screen coordinates, so it can be negative — camera-independent, since `Input` is filled before that frame's `Camera` exists. See Camera below.

**Camera** is what maps world space onto screen space, for content bigger than the screen — a sidescroller, a top-down level, anything that scrolls. `frame.camera(cam)` sets the active one, and it applies to every draw call and every nested `transform()` from there on, exactly like `Style`: reset to identity each frame, so `update` sets it explicitly each frame it wants one. `Camera` is a field the program owns and moves on its own schedule (`self.cam.position = self.player.pos`, or a `Tween` over it for smoothing) — it is not fed by the run loop, so it costs `Program`, `Frame` and `run.mojo` nothing, same reason adding `Audio` did not touch them. `Camera.to_world`/`to_screen` convert a point between the two spaces — `self.cam.to_world(input.mouse)` for picking against world-space entities.

`frame.overlay()` is the escape hatch: a `with` block that suspends the active camera (and any nested transform) so what's drawn inside lands in screen space regardless of where the camera looks — HUD, score, anything that must stay fixed on screen.

```mojo
frame.camera(self.cam)
frame.sprite(self.player.pos, ...)          # world-space coordinates
with frame.overlay():
    frame.text("Score: " + str(self.score), (0, frame.top() - 20))  # screen space
```

Nothing below `Frame` knows a camera exists: `_command.mojo`, `_backend.mojo`, `_tessellate.mojo` and the GL path all just replay `DrawCommand.transform`, which already carries the full composition — camera support cost them nothing.

**All shapes are center-positioned** (unlike Processing). `frame.rectangle((x, y), w, h)` draws a rectangle centered at `(x, y)`, same as `frame.circle()`, `frame.sprite()`, etc. `Rectangle.x/y` is the center, not the top-left corner. Position arguments are `Point2D` and extents are `Vector2D` — a location versus a width/height pair — and both types' tuple constructors are `@implicit`, so a bare tuple works everywhere either is taken.

**Style defaults are not blank:** every frame starts from `Style()`, which has **outline `BLACK`,
enabled, 1 unit thick** — a `rectangle` drawn without `outline(enabled=False)` gets an outline nobody
asked for. `corner_radius` defaults to `0` (sharp corners, unchanged behaviour). The rest of the
defaults are in [_style.mojo](src/create/render/_style.mojo).

**Every frame opens with a clear, and that is what makes those defaults visible.** `Frame.__init__`
records a `CMD_CLEAR` to `clear_color` — gray `200` — unless `autoclear` is off. Without it the
screen is whatever the framebuffer happened to hold, which is a zero-filled buffer at startup and
therefore black; black default outlines and black default text on it are a sketch that draws
nothing. The two defaults have to agree, and the clear is the one of the pair a program sets once
rather than per shape.

It is a recorded command, not a fill behind the command buffer's back, so one mechanism serves
every path: the GPU backend turns it into `glClear` through the batching rule it already had, an
opaque `frame.background()` *replaces* it through `Backend.record_clear` (so the usual first line
of `update` costs one full-framebuffer paint, not two), and a transparent `save_image` drops it
with the mask it already applies to `CMD_CLEAR`. A translucent `background()` does not replace it,
because it blends with what the clear painted.

`options.autoclear` is **deferred** like `options.design_resolution()` — this frame's clear is recorded before `update` runs,
so turning it off applies from the next frame. Set it in `create`. Off is what a program that
accumulates ink across frames wants ([examples/scenes/src/main.mojo](examples/scenes/src/main.mojo))
and what motion trails drawn by fading the previous frame require
([examples/alpha.mojo](examples/alpha.mojo)). Accumulation is a CPU-backend property either way:
the GPU path swaps buffers, so what a frame inherits is two frames old.

**Rounding a corner does not change what "outline" means for that shape.** A rectangle's outline
is an **inset ring** — the stroke sits inside the fill footprint, so rounding just curves the ring's
own inner and outer edges at each corner. A triangle's outline is **centred, device-space bands**
running along and around the shape at a fixed pixel width — rounding replaces each straight band's
corner join with a centred arc band, but the fill footprint itself is unchanged either way. This
distinction predates `corner_radius` and rounding must preserve it exactly, not blur the two
conventions together — currently the only place both are spelled out together is
`emit_triangle`'s docstring in [_tessellate.mojo](src/create/render/_tessellate.mojo).

**Three colours, not two, and glyphs take their own.** `Style` carries `fill_color`,
`outline_color` and `text_color` — the `_color` suffix on all three so a colour field never reads
like the toggle beside it (`fill_enabled`, `outline_enabled`). `frame.fill`/`frame.outline` set
the first two, `frame.text_color` the third (`BLACK` by default, like the outline), and they do
not reach each other: a shape colour and a
label colour can stand at once, and `fill(enabled=False)` no longer silently suppresses text. Text is
gated on its own alpha instead — `text_color(Color(..., 0))` draws nothing.

**Autoscale** keeps the program in its design resolution while the window resizes. `frame.width`/`height`, `input.mouse`, and all frame coordinates stay in that design space; `frame.scale` reports the factor, and font size, outline thickness, and sprite size scale with it. Three modes — `FIT` (default), `EXTEND`, `OFF` — documented in [autoscale.mojo](src/create/render/autoscale.mojo), with the launch-mode matrix on `run`. `options.design_resolution(w, h, mode)` pins the space from inside `create`. See [examples/autoscale.mojo](examples/autoscale.mojo), which cycles all three modes on space.

The design size is a property of the program, not of the display: it is whatever `run` was passed — which is why that argument is a design resolution rather than a window size — unchanged by a resize or by fullscreen. A program that wants the display's own coordinates asks for them with `AutoScale.OFF`, rather than by leaving the size out. Under `EXTEND` the *reported* size grows with the window, so layout must anchor to the origin or to `frame.left()`/`right()`/`bottom()`/`top()` rather than hardcoded design coordinates.

`Input._set_mouse(x, y)` is the single writer of `mouse`, `mouse_x` and `mouse_y`, and every event
arm in `run.mojo` that carries a pointer position goes through it — writing the fields directly
desynchronises the `Point2D` from the `Int` pair. A new event that reports a position calls
`_set_mouse` and adds only what is genuinely its own — `mouse_press_pos` on a press, say.

**Parameter vs. field:** a resource the run loop *feeds* the program every frame (`Options`, `Frame`, `Input`) stays a parameter; a resource the program *drives* on its own schedule (`Sprite`, `Font`, `Sound`, `Audio`, `SpriteAnimator`) is a field the program owns and constructs in `create`. This is why adding audio required zero changes to `Program`, `Frame`, or `run.mojo` — `Audio` is just another field, like `Sprite`.

**What earns its own parameter** is decided by *who writes it*, not by who feeds it — feeding alone doesn't distinguish anything, since `Time` is fed every frame and is a field on `Frame`.

| | Loop writes | Program writes | Shape |
|---|---|---|---|
| `Frame` (and its `Time`) | yes | yes | `mut` parameter |
| `Input` | yes | **no** | read-only parameter |

`Input` is the only one the program never writes, hence a read-only argument rather than a field on the `mut` `Frame` — reasoning in the [`Input` docstring](src/create/core/input.mojo). `frame.time` shows the cost of the alternative: the program never writes it either, but `frame.time.frame_count = 99` compiles.

**Per-frame obligations.** Three fields the program owns need ticking from `update`, and nothing
enforces it:

- `audio.update()` — SDL never reports a finished stream, so skipping it stalls a loop after its
  first buffer drains and leaks one-shot voice slots forever. See
  [audio.mojo](src/create/audio/audio.mojo) and [examples/audio/src/main.mojo](examples/audio/src/main.mojo).
- `animator.update(frame.time.delta)` — the playhead only advances here. See
  [animator.mojo](src/create/sprite/animator.mojo) and [examples/animation/src/main.mojo](examples/animation/src/main.mojo).
- `tween.update(frame.time.delta)` — same shape and same failure: a tween never ticked sits at its
  `start` forever. See [tween.mojo](src/create/math/tween.mojo) and [examples/tween.mojo](examples/tween.mojo),
  which also cycles the easing curves against one shared playhead.

Both an animation and a sound are shared assets, held as `ArcPointer` fields (`from std.memory
import ArcPointer`) so several entities or voices share one buffer by refcount instead of copying
it. The biggest trap in the animation API is documented on
[`SpriteAnimator.use`](src/create/sprite/animator.mojo) — read it before driving an animator.

## Critical Gotchas

1. **`-I src` is required for every `mojo run`.** Without it, `from create import *` fails with a module-not-found error. All pixi tasks include it; bare `mojo run` calls must add it manually.

2. **Paths resolve against the CWD, not the source file.** The packaged font is loaded as the literal
   relative path `defaults/fonts/NotoSans.ttf` ([font.mojo](src/create/render/font.mojo), used by
   `TextRenderer._ensure_font`), so **`frame.text()` only works when the process CWD is the repo
   root.** Run from anywhere else and every text draw raises:

   ```
   FT_New_Face failed — font not found: defaults/fonts/NotoSans.ttf
   ```

   The same applies to your own assets: use `script_dir()` (`from create.core import script_dir`),
   which returns the directory part of `argv[0]` — the `.mojo` file under `mojo run`, the binary
   under `mojo build` —

   ```mojo
   var sprite = Sprite.load(script_dir() + "/../assets/sprite.jpeg", 120, 120)
   var chime = ArcPointer(Sound.load(script_dir() + "/../assets/chime.wav"))
   ```

   Every example does this. Tests reach fixtures both ways — `tests/fixtures/...` relative to the
   root, or `script_dir() + "/../fixtures/"` — so the suite must be run from the root either way,
   which `pixi run test` guarantees.

3. **A window does not report its real size immediately.** In fullscreen SDL fires a bogus `(1, 1)` `Resized` before reporting real dimensions, so `_wait_for_dimensions` pumps events until width > 1 and height > 1. On Wayland the fullscreen transition is asynchronous on top of that: `run[T]("t", WindowMode.FULLSCREEN, width=1000, height=1000)` reports the requested 1000x1000 for frame 1 and the display size from frame 2 on. The run loop refreshes dimensions every frame, so this self-corrects — but don't cache pixel dimensions from `create` or the first frame.

4. **One origin limit in this Mojo version shapes the API.** Nothing can return a reference to a
   `List` element, so `SpriteAnimation` has **no `frame()` accessor** — see its
   [docstring](src/create/sprite/animation.mojo) and [`frame.sprite`](src/create/render/frame.mojo).
   Index inline at the use site instead. Don't retry it.

   (`Frame` used to take one parameter — the `Surface` it drew onto — for the same class of
   reason: a second parameter would have broken every `Program.update` signature at once, and
   pointing an existing `Frame` at a new framebuffer could not compile. The command-buffer split
   (`Frame` records, `Backend` replays onto a `Surface` it never sees) removed the need for a
   `Surface` on `Frame` at all, so `Frame` now takes **no** parameters. Don't reintroduce a
   `Surface` field or parameter on it — see its [docstring](src/create/render/frame.mojo).)

5. **An uncalled overload is compiled by nothing.** A library build only type-checks the `def`
   bodies it reaches, so an overload nothing calls is checked by no build. The program in
   [tests/render/test_frame.mojo](tests/render/test_frame.mojo) draws through all six of
   `frame.sprite`'s animator overloads for this reason — extend it when adding another. This is
   the general reason the repo gates on consumer programs as well as on `mojo precompile`.

6. **`glViewport` is sized from `drawable_size()`, never `width()`/`height()`.** Those are SDL's
   *logical* size and differ from the backing pixels under HiDPI or fractional scaling, so sizing
   the GL viewport from them stretches or clips the frame. `_run_gl.mojo` re-reads the drawable
   every frame, and again after event processing, for the same reason the CPU loop re-takes its
   `Surface`: a resize landed in between.

## Terminology

Concepts that span files. Every type's own surface — methods, constants, factories — is in its
docstring; this table is not an API reference and must not grow into one.

| Term | Meaning |
|---|---|
| `Program` | Full interactive program: `create(options)`, then `update(options, frame, input)` once per frame. `create` gets no `Frame`: no frame exists before the loop starts, so there is nothing to draw on and no geometry to read — which is what makes Gotcha 3 a compile error rather than a docstring. One per-frame method, not two: deciding and drawing are the same frame's work, so a decision never has to be smuggled between them through a field. No event callbacks — input arrives as `update`'s `Input` parameter |
| `Frame` | The one per-frame object a program is handed: the screen geometry (`width`/`height`, `left`/`right`/`bottom`/`top`), the clock (`time`) and the whole drawing API — and nothing that outlives the frame. `mut` because the program writes it from one side while the loop writes it from the other. Built fresh each frame and dropped before the frame is presented, so nothing may hold one across frames |
| `Options` | The dials that outlive a frame: `autoscale`, `autoclear`/`clear_color`, `letterbox`, `quit_on_escape`, `design_resolution()`, `frame_cap()`, `quit()`. Owned by the run loop, passed `mut` to `create` (on its own — the only thing `create` can touch) and to every `update`. Read at **frame construction**, so a dial set mid-`update` applies to the *next* frame; `frame_cap()` and `quit()` are the exception, since the loop reads them after the frame body returns |
| Screen space | The fixed coordinate space `Frame`/`Input` describe — origin centred, y up (see Coordinate system above). Camera-independent: `frame.left`/`right`/`bottom`/`top` and `input.mouse` live here, and `Viewport.base_matrix()` maps it straight to framebuffer pixels |
| World space | The camera-relative space a program draws in once it sets a `Camera` — effectively unbounded, since panning or zooming the camera just changes which part of it lands on screen. `Frame._user`/`to_local`/`to_world` operate here; with no camera set (the default), world space and screen space coincide |
| `Camera` | What maps world space onto screen space: `position` (world point centred on screen) and `zoom`. A field the program owns and moves on its own schedule, like `Sprite` — not fed by the run loop. `frame.camera(cam)` applies it to every draw call and nested `transform()` until changed or `frame.overlay()` suspends it; resets to identity every frame, like `Style`. `frame.overlay()` is the escape hatch for a HUD or other UI that must stay in screen space regardless of the camera |
| Design resolution | The size passed to `run` (default 1280x720, or pinned by `options.design_resolution()`) — the space a program is authored in, and the factor `options.autoscale` scales by. It is a design size, not a window size: a windowed or borderless launch opens at it because the two coincide there, while fullscreen and maximized take the display and scale the design onto it. `AutoScale.OFF` is the one mode that leaves it unused, making coordinates the window's own pixels. See Autoscale above |
| `DrawCommand` | One recorded draw: local-space geometry, the transform at record time, and the resolved `Style`. What `Frame` appends instead of touching pixels — see [_command.mojo](src/create/render/_command.mojo) |
| `Backend` | Owns the fonts, glyph cache and interned sprite images, and replays a frame's `DrawCommand`s — onto a `Surface` at `present` (CPU, the one caller of `_raster.mojo`) or through `GLRenderer` at `present_gpu` (GPU). Which one is a `kind` field, not a trait object |
| `Surface` | A borrowed RGBA framebuffer: pixel pointer plus width and height. Deliberately a plain value, not a trait. The **CPU** backend's replay target specifically — the GPU path has none, and `Frame` never holds one either way. Taken after event processing so a resize is never missed |
| `save_image` / `save_screenshot` | The two captures, and they answer different questions. `frame.save_image(path, scale, transparent)` is what the program *drew*: design resolution times `scale`, no letterbox bars, CPU-replayed from the recorded commands under **both** backends, so it is reproducible across machines and window sizes. `frame.save_screenshot(path)` is what the user *saw*: the drawable's own resolution, bars included, drawn by whichever rasteriser drew the frame, hence machine-dependent by design. Neither is a fallback for the other |
| `Viewport` | The design-space-to-pixel mapping: design size, autoscale mode, scale factor, offsets, base matrix. Owns no window and no pixels, so it is pure arithmetic; `Frame` forwards to it |
| `PersistentFrameState` | The library's own carry-over across the frame boundary — the `Backend` (hence fonts, glyph cache, sprite images), the `Viewport` and the clock — moved into each frame's `Frame` and back out again by `_release`. The program-settable dials are *not* here; they are `Options`, which the loop holds separately so `update` can be handed both at once. The transform stack and the style are *not* in it: `Frame` is reachable only from `create` and `update`, so nothing could seed a style outside a frame, and carrying one forward would preserve only a forgotten setting |
| `TransformGuard` / `StyleGuard` / `OverlayGuard` | RAII wrappers from `frame.transform(m)`, `frame.style()` and `frame.overlay()` — pop the matrix, restore the style, restore the camera and transform, on scope exit |
| Asset vs. playhead | `SpriteAnimation` and `Sound` are immutable artwork, shared by `ArcPointer`; `SpriteAnimator` and an `Audio` voice are one entity's position in it. The rate (`fps`) belongs to the asset, not the playhead |
| `Easing` / `Tween` | An `Easing` is the *shape* of a motion — a pure function of a 0-to-1 fraction, so `ease(curve, t)` needs no state. A `Tween` is a playhead that walks that fraction over a duration and reads out a value. A tween has no shared asset to split off the way an animation does: its whole definition is four numbers, so each entity owns its own |
| `Point2D` / `Vector2D` | The position/direction split, and which one a signature takes is decided by role, not by convenience. A **location** is a `Point2D`: `frame.circle(pos, r)`, `Rectangle.center()`, `input.mouse`. An **extent or a displacement** is a `Vector2D`: `Rectangle.size()`, `translate(delta)`, `input.wheel`, a velocity. `Point2D` carries only what a position admits — subtraction to a `Vector2D`, translation by one, `dist`, `lerp` — and refuses `mag`, `normalize`, `dot`, scalar `*`, unary `-` and `Point2D + Point2D`, which is the whole point of it: `pos.normalize()` used to compile and mean nothing. `.xy()`/`.xyz()` is the visible step between them (`Vector2D(p.xy())` is the escape hatch), and a bare tuple binds into either, so the distinction costs a call site nothing |
| `overlaps` / `intersects` / `contains` | The three geometry relations in [geometry.mojo](src/create/math/geometry.mojo), and they don't overlap in role. `overlaps(a, b)` is a free function, symmetric between two regions (`Rectangle`/`Circle`/`Triangle`). `l.intersects(x)` is a method on `Line` only, asymmetric — `Line` has no interior, so it can only ever be the subject, never an operand of a symmetric test. `s.contains(x)` is a method on the containing region, also asymmetric. A `Line` is never a region: it has no `overlaps` overload and no `center()`/`area()` |

## Do

- Use `@fieldwise_init` on program structs to auto-generate `__init__` from fields.
- Use `pixi run test` before committing.
- Use `frame.background(Color.X)` as the first drawing call in `update` to pick the frame's colour — it replaces the `autoclear` clear rather than adding a second one. Set `options.clear_color` in `create` instead if the colour never changes, and `options.autoclear = False` if the program wants the previous frame left alone.
- Use `frame.to_local`/`to_world` to move a position between world space and the current transform's frame — neither deals in pixels, and both take two `Float64`, so pass `input.mouse.x, input.mouse.y`. Both still *return* a `Tuple[Float64, Float64]`, which lands implicitly in a `Point2D` or a `Vector2D`, so they are the seam between the two rather than a conversion site.
- Use `Point2D` for a new signature's locations and `Vector2D` for its extents and deltas — `Rectangle(pos: Point2D, size: Vector2D)` and `frame.rectangle(pos, size)` are the shape to copy when one signature names both.
- Use `script_dir()` for every asset path; a bare relative path resolves against the CWD.

## Don't

- Don't use `alias` it has been depricated in favor of `comptime`
- Don't use `UnsafePointer` it has been depricated in favor of `Pointer`
- Don't use `fn` it has been removed — `error: 'fn' has been removed; use 'def' instead`
- Don't hold a raw `Pointer` to `Frame` outside `TransformGuard`/`StyleGuard` — use origin-tracked references.
- Don't name new test files without the `test_` prefix — the test runner won't pick them up.
- Don't add a `Point2D` overload beside a `Vector2D` one. Both have `@implicit` tuple constructors, so two overloads differing only in which they take make `frame.circle((0, 0), 20)` ambiguous — replace the parameter's type instead of overloading. The same ambiguity is why `p - Vector2D(1, 2)` must name the type while `p + (1, 2)` need not, and that asymmetry is the algebra's: subtracting from a position has two meanings — the displacement to another position, or a move backwards by one — so a bare tuple cannot say which, while addition has only one, because `Point2D + Point2D` does not exist. Don't sand the asymmetry away by adding a `Point2D` overload to `__add__` purely to make the tuple ambiguous there too: it would make the meaningless `p + Point2D(1, 2)` compile, which is the thing the type exists to refuse.
- Don't add a `Surface` field or parameter to `Frame`, and don't import `window` from `frame.mojo` — see Gotcha 4.
