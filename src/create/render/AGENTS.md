# AGENTS.md — `create.render`

Internals of the rendering stack. The root [AGENTS.md](../../../AGENTS.md) covers the consumer API
and the layering rules.

## Files

| File | Role |
|---|---|
| `canvas.mojo` | `Canvas` (records commands, touches no pixels), `PersistentCanvasState`, the guards |
| `_command.mojo` | `RenderCommand` and its kind constants |
| `_backend.mojo` | `Backend` — fonts, glyph cache, interned images; replays commands via `present` (CPU) or `present_gpu` |
| `_raster.mojo` | CPU rasteriser over a `Surface`; called only from `_backend.mojo` |
| `_gl.mojo` | GL entry points resolved at runtime; the only file that talks to the driver |
| `_gl_backend.mojo` | `GLRenderer` — shader, vertex buffer, glyph atlas, sprite textures, batching |
| `_tessellate.mojo` | `RenderCommand` to triangles for the GPU |
| `_shadow.mojo` | Shadow geometry shared by both backends: `shadow_command` (the hard silhouette as a command, offset matrix composed in), `BlurredSilhouette` (analytic Gaussian coverage for shapes), `InsetRegion` (an inset shadow's interior and cut) |
| `_curve.mojo` | Bézier stroke geometry for both replays: flattening in device pixels, the mitred quad strip, the blurred shadow mask |
| `_blur.mojo` | Three-box-blur approximation of a Gaussian over an alpha mask, for text and sprite shadows; the blurred-mask cache limit and key |
| `_transform.mojo`, `_image.mojo`, `_fillet.mojo` | Shared by both replay paths (split out to avoid an import cycle, or so both agree on the numbers) |
| `_gl_target.mojo` | Offscreen FBO of an exact size, for the parity test and headless GPU |

## Canvas, commands and backends

A `Canvas` render call **records, never paints**: it appends a `RenderCommand` (local geometry,
transform at record time, style resolved now) to the `Backend`. Nothing rasterises until
`present`/`present_gpu` replays the frame, so later style calls can't reach back. Sprites are interned
into the backend at record time (the command carries an id); text is recorded as an owned `String`
and laid out at replay. Add a shape by extending `_command.mojo`'s kinds and `_backend.mojo`'s replay
(plus `_tessellate.mojo`), never by calling `_raster.mojo` from `Canvas`.

`RenderCommand.geom` has 8 slots, sized for `CMD_BEZIER`'s four points; the geometry table in
`_command.mojo` gives each kind's layout.

`Canvas` holds no `Surface` and takes its geometry from the `Viewport` alone — don't add a `Surface`
field or parameter, and don't import `_window` from `canvas.mojo`. What survives the frame boundary:
`PersistentCanvasState` (the `Backend` and `Viewport` — moved in and back out by `_release`) and
`Context` (in `core`, owned by the loop, and home to `time` and `input`; its dials reach `Canvas` as
plain values). The transform stack, style and camera deliberately don't.

The camera is folded into `RenderCommand.transform`; nothing below `Canvas` knows it exists.

`Backend.kind` selects the replay (`RenderBackend.CPU` onto a `Surface`, `GPU` through `GLRenderer`);
a field rather than a trait because Mojo has no dynamic dispatch.

The autoclear is a recorded `CMD_CLEAR`, so every path handles it: the GPU turns it into `glClear`,
an opaque `canvas.background()` replaces it via `Backend.record_clear`, and a transparent
`save_image` masks it out.

## Curves

A `CMD_BEZIER` records only its four control points. Each replay maps them through the command's
transform (a Bézier is affine-invariant) and flattens in device pixels
(`FLATTEN_TOLERANCE_PX`), so the curve stays smooth under any zoom. `stroke_quads` turns the
polyline into a strip of quads sharing mitred edges — no gap, no overlap, so a translucent stroke
composites once — which the CPU fills with `fill_quad` and the GPU pushes as vertices. Ends are
butt. Known limitation: at a cusp the miter is clamped (`MITER_LIMIT`) and the quads either side
overlap slightly.

## Captures

Requests filed on the `Backend` and serviced inside `present`/`present_gpu`, the only place holding
both the finished framebuffer and the unconsumed command buffer; a failed write raises from there.
- `canvas.save_image(path, scale, transparent)` — what the program drew: design resolution × `scale`,
  no letterbox, CPU-replayed from the commands under **both** backends (glyph cache and images live
  on `Backend`, not `GLRenderer`). Reproducible across machines.
- `canvas.save_screenshot(path)` — what the user saw: drawable resolution, bars included. On GPU this
  is a `glReadPixels` stall — fine on a keypress, not per frame.

See [examples/screenshot/src/main.mojo](../../../examples/screenshot/src/main.mojo).

## Outlines

Outlines mean different things per shape, and `corner_radius` must preserve that: a rectangle's is
an **inset ring** inside the fill; a triangle's is **centred device-space bands**. Spelled out in
`emit_triangle`'s docstring in [_tessellate.mojo](_tessellate.mojo).

## Shadows

Both replays handle a command's shadow around the command itself, in the command's blend mode:
- **Outer** (`casts_outer_shadow`), *before* the command. Blur is quantised to whole device pixels
  (`Int(shadow_blur * pixel_scale + 0.5)`) by both backends identically; 0 replays
  `shadow_command(c, scale)` through the normal dispatch. Otherwise shapes and lines evaluate
  `BlurredSilhouette` coverage analytically (CPU per pixel over the reach; GPU one quad in
  `MODE_SHADOW_BOX`/`MODE_SHADOW_EDGES`), and text and sprites blur a mask (`_blur.mojo`): glyph
  masks are keyed by blur in the glyph cache and packed into the atlas; sprite masks are cached per
  `shadow_mask_key` in `Backend.shadow_masks` (CPU) and `GLRenderer.shadow_textures` (GPU), both
  dropped whole at `SHADOW_MASK_LIMIT`.
  A Bézier's stroke is rasterised into a mask and blurred too (`bezier_shadow_mask`), but
  **uncached**: it has no stable id to key by, so each blurred Bézier shadow costs one blur per
  frame, and on the GPU one texture upload plus one draw call; the textures are deleted after the
  frame's final flush.
- **Inset** (`casts_inset_shadow`), *after* the command: the interior (`inset_interior`) is the
  clip, the silhouette is the interior shrunk by the spread and moved by the shadow transform, and
  alpha is `1 − coverage`. The CPU tests pixel centres in the interior's box; the GPU tessellates
  the interior with the fill emitters and sets each vertex's silhouette parameters from its device
  position (`MODE_INSET_BOX`/`MODE_INSET_EDGES`). A hard inset on the GPU uses a steep sigma
  (1/64 px), not a step.

The offset is one matrix: screen-fixed composes a device translation after the command transform,
follows-transform composes `translate(offset)` before it (`shadow_transform`).

Parity (`test_gl_parity.mojo`) needed no extra tolerance for blurred cases: both backends evaluate
the same coverage formulas at pixel centres.

## CPU rasteriser

Compute each row's covered run analytically and hand `(start, count)` to `fill_span` once — never
test every pixel in a bounding box. `fill_span` owns the opaque-store and vectorised compositing.
`blend` is only for genuinely per-pixel alpha (glyph coverage, sprite texels).

The command's `BlendMode` rides on the `Surface` (`_with_blend_mode`, set once in `Backend._one`), so
no raster loop threads it; `blend` and `fill_span` read it and share `_blend_lanes` for every mode but
`NORMAL`. A new mode goes there and in `GLRenderer._blend_mode` — it must be one fixed-function GL
blend equation, which is why there is no `DIFFERENCE`.

## GPU path (OpenGL 3.3)

`_tessellate.mojo` bakes each command's transform into its vertices (13 × `Float32`: `x, y, u, v,
r, g, b, a, mode, s0, s1, s2, s3`), so everything accumulates into one buffer and flushes as one
`glBufferData` + `glDrawArrays`. `s0..s3` are per-mode shape parameters, zero where unused; they
only ever hold quantities affine across a triangle, so interpolation evaluates them exactly.

| Mode | Value | Fragment |
|---|---|---|
| `MODE_SOLID` | 0 | Vertex colour, no sampling |
| `MODE_MASK` | 1 | Glyph: atlas red scales alpha |
| `MODE_TEXTURE` | 2 | Sprite: sampled RGBA × colour |
| `MODE_SILHOUETTE` | 3 | Sprite shadow: sampled alpha scales colour alpha |
| `MODE_SHADOW_BOX` | 4 | Blurred rect/rounded rect/circle/line shadow; `s3` a ring |
| `MODE_SHADOW_EDGES` | 5 | Blurred triangle shadow, three edge distances; `s3` a ring |
| `MODE_INSET_BOX` / `MODE_INSET_EDGES` | 6 / 7 | 4 / 5 without ring, coverage inverted |

A batch breaks only on an opaque `CMD_CLEAR`, a second distinct unit-1 texture, a `BlendMode`
change, or frame end — glyph atlas on texture unit 0, sprites on unit 1. A blurred sprite shadow's
mask is its own unit-1 texture, so a shadowed sprite costs one extra draw call, and interleaving
several costs one per switch; a blurred Bézier shadow likewise costs one. Blurred text shadows
live in the atlas and cost none. Per frame, only the viewport is written, and only on resize.

Before optimising: `pixi run benchmark frame` measures ~6 ms/frame at 1920x1080 (vsync off); the
vertex list stops reallocating after frame 1; orphan-then-`glBufferSubData` measured identical to
the current single `glBufferData`. `pixi run benchmark raster` measures CPU rasterisation headless.

**`render` reaches GL without `_window`:** `_gl.mojo` `dlopen`s SDL itself and resolves through
`SDL_GL_GetProcAddress`. A GL context must be current before `GL()` is constructed.

**FFI rules for `_gl.mojo`** (calls go through bitcast `thin abi("C")` pointers; this works):
1. A `String` whose pointer goes to C must outlive the call — put `_ = s` after it. Check every
   resolved address against 0.
2. Read C out-parameters from heap memory (`List`), not a local `InlineArray` — the optimizer may
   serve the local stale.
3. Keep the GL context owner alive past the last GL call (`_ = win^` in tests and spikes).
