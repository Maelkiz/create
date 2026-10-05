# AGENTS.md — `create.render`

Internals of the rendering stack. The root [AGENTS.md](../../../AGENTS.md) covers the consumer API
and the layering rules.

## Files

| File | Role |
|---|---|
| `canvas.mojo` | `Canvas` (records commands, touches no pixels), `PersistentCanvasState`, the guards |
| `_command.mojo` | `RenderCommand` and its kind constants; `_fill_box`, the box a fill gradient spans |
| `_backend.mojo` | `Backend` — fonts, glyph cache, interned images; replays commands via `present` (CPU) or `present_gpu` |
| `_raster.mojo` | CPU rasteriser over a `Surface`; called only from `_backend.mojo` |
| `_gl.mojo` | GL entry points resolved at runtime; the only file that talks to the driver |
| `_gl_backend.mojo` | `GLRenderer` — shader, vertex buffer, glyph atlas, image textures, batching |
| `_tessellate.mojo` | `RenderCommand` to triangles for the GPU |
| `_shadow.mojo` | Shadow geometry shared by both backends: `shadow_command` (the hard silhouette as a command, offset matrix composed in), `BlurredSilhouette` (analytic Gaussian coverage for shapes), `InsetRegion` (an inset shadow's interior and cut) |
| `_curve.mojo` | Bézier stroke geometry for both replays: flattening in device pixels, the mitred quad strip; the blurred shadow mask of any device quads (`quads_shadow_mask`) |
| `_sector.mojo` | Sector fill and outline tiled into device quads for both replays (`sector_quads`), and its blurred shadow mask |
| `_polygon.mojo` | Polygon fill and outline tiled into device quads for both replays (`polygon_quads`), and its blurred shadow mask |
| `_triangle.mojo` | A rounded or outlined triangle as a convex fill and ring quads for both replays (`triangle_pieces`) |
| `_coverage.mojo` | CPU antialiasing: `composite_coverage` turns a shape's runs recorded on a finer grid into per-pixel coverage, composited once |
| `_clip.mojo` | `_Clip` (one `canvas.clip` level: region command, invert, parent) and `_ClipRows`, the CPU replay's per-row runs of a clip, each with its coverage |
| `_blur.mojo` | Three-box-blur approximation of a Gaussian over an alpha mask, for text and image shadows; the blurred-mask cache limit and key |
| `_transform.mojo`, `_image.mojo`, `_fillet.mojo` | Shared by both replay paths (split out to avoid an import cycle, or so both agree on the numbers) |
| `_gl_target.mojo` | Offscreen FBO of an exact size, for the parity test and headless GPU |

## Canvas, commands and backends

A `Canvas` render call **records, never paints**: it appends a `RenderCommand` (local geometry,
transform at record time, style resolved now) to the `Backend`. Nothing rasterises until
`present`/`present_gpu` replays the frame, so later style calls can't reach back. Images are interned
into the backend at record time (the command carries an id); text is recorded as an owned `String`
and laid out at replay. Add a shape by extending `_command.mojo`'s kinds and `_backend.mojo`'s replay
(plus `_tessellate.mojo`), never by calling `_raster.mojo` from `Canvas`.

`RenderCommand.geom` has 6 slots, sized for a triangle's three points; the geometry table in
`_command.mojo` gives each kind's layout. `CMD_BEZIER` (control points) and `CMD_POLYGON` (vertices)
use `RenderCommand.points` instead, a `List` that stays empty (and unallocated) for every other kind.

`Canvas` holds no `Surface` and takes its geometry from the `Viewport` alone — don't add a `Surface`
field or parameter, and don't import `_window` from `canvas.mojo`. What survives the frame boundary:
`PersistentCanvasState` (the `Backend` and `Viewport` — moved in and back out by `_release` — and
the frame-wide settings a program sets on the canvas: `autoclear`, `letterbox_color`, and through
the backend the font and `antialiasing`) and `Context` (in `core`, owned by the loop, home to
`time` and `input`; its mapping dials reach `Canvas` as plain values through `_set_viewport`). The
transform stack, style and camera deliberately don't.

A frame-wide setting applies to the whole frame it is set in, because nothing is rasterised until
present: `_render_letterbox` reads `letterbox_color` at the end of the frame, and both replays read
`antialiasing` when they run. `canvas.antialiasing` bumps `Backend.recorded` so a cached read
replays at the new level.

The camera is folded into `RenderCommand.transform`; nothing below `Canvas` knows it exists.

`Backend.kind` selects the replay (`RenderBackend.CPU` onto a `Surface`, `GPU` through `GLRenderer`);
a field rather than a trait because Mojo has no dynamic dispatch.

The autoclear is a recorded `CMD_CLEAR`, so every path handles it: the GPU turns it into `glClear`,
an opaque `canvas.background()` replaces it via `Backend.record_clear` (`_clear_is_opaque`), and a
transparent `save_image` masks it out. `Canvas`'s constructor records it through
`Backend.open_with_clear`, which sets `autoclear_head`: the frame's first command is still that
clear. `canvas.autoclear(...)` calls `Backend.set_autoclear`, which takes it back out (only while
`autoclear_head` holds — a `background()` that replaced it stays) or inserts it at index 0, and
bumps `recorded` either way.

## Gradients

A fill gradient rides on the command's `Style` (`fill_gradient`); opacity scales its stops at
record time. Everything a replay needs comes from three pieces in `create/color/gradient.mojo`, shared so the
backends agree:
- **The ramp:** `RAMP_SIZE` (256) colours sampled from the stops at construction, behind an
  `ArcPointer` with the stops, so copying a `Gradient` (and the `Style` holding one) is a refcount.
- **The device mapping:** `_device_mapping(inverse(m), center, half)`, with the box from
  `_fill_box(c)`. The parameter (linear) or the position whose length it is (radial) is **affine
  in device pixels** — the whole design rests on that.
- **The sample:** `_sample(t, x, y)` reads linearly between two ramp entries and adds the 4x4
  Bayer threshold (`_BAYER`) before flooring to bytes. Exact ramp colours come out unchanged.

**CPU:** the fill call sites pass a `FillPaint` (`_raster.mojo`) from `_fill_paint(c, m)` — a
`Color` converts implicitly, so outline and shadow calls are untouched. `fill_span`'s `FillPaint`
overload is the choke point: a solid goes to the colour loop, a gradient to `_shade_span`, which
steps the mapping along the row and `blend`s each pixel. Decide solid-or-gradient once per run (or
per rect, in `fill_pixels`), never per pixel; a solid `FillPaint` is a colour and an empty
`Optional`. `shadow_command` clears the gradient — a shadow is one colour.

**GPU:** the fill emitters take a `ramp_row`; after emitting a fill, `_shade_fill` rewrites that
run of vertices to `MODE_GRADIENT` with the mapping's value at each vertex — the same post-pass
`emit_inset_shadow` uses. So a fill's vertices must be one contiguous run (`emit_circle` emits its
fan, then its ring). The ramp texture (256x256 RGBA, unit 2) holds one ramp per row, cached by
`_stops_key` + `_same_stops` across frames; full, it flushes and starts over. Linear filtering along
the row is the CPU's read between entries; the shader indexes `BAYER` by device pixel counted from
the top, as the CPU does.

**Background:** `background(gradient)` records a `CMD_CLEAR` with the rectangle's geometry (the
design area) and the canvas's base matrix, so `_fill_box` and the mapping work as for a rect, and a
capture's `pre` maps it like any command. The CPU shades every row; the GPU draws a framebuffer quad
(never `glClear`, which takes one colour).

Parity is checked per pixel, not just structurally: `test_gradient_fill.mojo` renders each scene on
both backends and compares away from edges within one level.

## Curves

A `CMD_BEZIER` records a **chain** of cubic Béziers as control points in `points`: 3n+1 for n
curves, each ending where the next starts (`bezier_command` records a chain of one,
`bezier_chain_command` any). Each replay maps them through the command's transform (a Bézier is
affine-invariant), flattens each curve in device pixels (`FLATTEN_TOLERANCE_PX`) so it stays smooth
under any zoom, and joins the pieces into one polyline. `stroke_quads` turns that into a strip of
quads sharing mitred edges — no gap, no overlap, so a translucent stroke composites once, across the
joints between curves too — which the CPU fills with `fill_quad` and the GPU pushes as vertices.
Ends are butt; a polyline whose last point is its first is a ring instead, its closing joint
mitred like any other. Known limitation: at a cusp the miter is clamped (`MITER_LIMIT`) and the
quads either side overlap slightly.

`canvas.spline` converts its `Spline` (Catmull-Rom) to Béziers **at record time, in local space**,
and records one chain. The conversion is exact, and doing it before the transform matters: the
centripetal knot spacing depends on distances, which a non-uniform scale would change, so a spline
converted after it would change shape rather than just stretch. Separate commands per curve would
meet on butt ends and double-blend a translucent joint; one chain doesn't.

## Sectors

A `CMD_SECTOR` (`cx, cy, r, start, sweep`, and a grow in `geom[5]`) is tiled at replay by
`sector_quads` into convex device quads — the same quads for both backends, so they agree the way
curves do: the CPU fills them with `fill_quad`, whose half-open rule composites shared edges once,
and the GPU pushes them as vertices. The tiling walks the sweep in thin wedges about the tip, and
along each ray the sector is one stretch from the tip: fill in the middle, outline either side. The
outline is inset, as a circle's is: the fill is the sector eroded by the outline thickness. Built in
local space and mapped per corner, so a non-uniform transform gives an elliptical sector.

`geom[5]` is 0 for a render call. A shadow sets it to its spread, and the tiling grows (or shrinks)
the sector by exactly that first — round the tip and the arc's ends, into the missing wedge — rather
than leaning on a corner radius, which a sector has none of. An outline-only sector's shadow ring
is the grown sector's outline band, thickened by twice the spread.

`canvas.arc` needs none of this: it records a `CMD_BEZIER` chain.

## Polygons

A `CMD_POLYGON` (vertices in `points`, a grow in `geom[0]`) is tiled at replay by `polygon_quads`
into the same kind of shared convex device quads as a sector, in local space and mapped per corner.
The cut is into **horizontal slabs**: every y where an edge ends or two edges cross, so within a
slab no edges cross, the edges sort by x, and a walk from the left keeps a winding count per
*layer*. The slabs come from a sweep upwards: each runs to the next edge's start or end, cut down
to the lowest crossing between neighbours in its middle's order until none cross — any crossing
inside a slab flips some neighbouring pair, so only neighbours are searched. Each stretch between neighbouring edges is classified fill, outline or nothing
(`_classify`), runs of one class merge, and each run is one trapezoid, every x taken from the
edge's lower end so neighbouring quads share corners exactly.

Layer 0 is the polygon (nonzero). The others are **bands**: points within `d` of some lines, a
counter-clockwise rectangle along each line and a polygonised disc at each end, inside where the
count is not zero. `Polygon._pieces()` cuts the edges at every crossing, each crossing found along
the lower-indexed edge so both edges share its point exactly, into the **rim** (outside along one
side) and the **seams** (wound on both sides). The outer band (radius `grow`) and the inner band
(`grow - t`) are the rim's; offsetting by `d` is the polygon with (outwards) or without (inwards)
its band. The seam band has radius `t/2`: fill is the inner offset off the seams, outline the rest
of the outer offset, so a seam is stroked centred and as thick as the rim. A seam disc already
inside an inner-band disc is left out.

`geom[0]` is 0 for a render call and the spread for a shadow; an outline-only shadow's thickness
`t + 2·spread` grows the seam band by the spread too, so the ring is the outline grown. Cost is
slabs × the edges spanning them, bands included: every slab runs the polygon's whole width, so
a crossing in one corner cuts quads everywhere — ~115 µs per outlined 5-tip star, ~195 µs per
outlined pentagram, ~2.4 ms per outlined 40-tip star.

## Clips

`canvas.clip(region, invert)` records no command. `ClipGuard` calls `Backend.push_clip`, which
appends a `_Clip` to `Backend.clips` and makes it current (`Backend.clip`). The clip holds the
region as an ordinary `RenderCommand` in `clip_style()` (an opaque white fill and nothing else),
its parent and `invert`. `Backend.record`/`record_clear` stamp the current id on every command
(`RenderCommand.clip`, 0 for none), so no command builder knows about clips. The guard restores the
previous id; `clips` resets with the command buffer. A clipped clear never replaces the clear before
it.

Each replay rasterises the region **with the code that draws that shape**, so a clip and a fill of
the same shape cover the same pixels:
- **CPU:** before any command, `Backend._clip_rows` replays each region through `_one` onto a
  *recording* surface (`Surface._recording_into`) `grid` times finer, as `_shape` antialiases a
  shape. There `fill_span` appends `(row, lo, hi, key)` and writes nothing; `key` names the run's
  paint, which a clip ignores. `_ClipRows` merges those per sub-row, then counts each pixel's
  covered samples into runs of constant `cover` (0–255, floored like `_mixed`, so a clip edge
  matches a fill of the same shape exactly), complements them for `invert` (`255 − cover`), and
  intersects with the parent's (covers multiply). A clipped command's surface carries its rows
  (`Surface._with_clip`). `fill_span`, `blend` and `fill_all` cut to them and scale a partly kept
  run's alpha by its cover (`_kept`), and nothing else writes pixels, so no rasteriser knows about
  clips. With antialiasing off the grid is 1 and every cover is 255.
  - The clipped paths are out of line (`_fill_span_clipped`, `_shade_span_clipped`, `_blend_clipped`).
    Keep them there: a recursive or larger `fill_span` stops inlining and cost circles ~40%.
  - `blit_image`/`blit_alpha` check for a clip once and pass `blend[clipped=False]`, because the
    per-pixel test alone cost an image blit ~15%.
  - The rows live in a local `List` that the surfaces point into untracked (`MutUntrackedOrigin`),
    built in full before the first command so it never reallocates under them.
- **GPU:** the stencil buffer. When `c.clip` differs from what the stencil holds,
  `GLRenderer._apply_clip` flushes, clears the stencil, and draws the chain outermost first through
  `_one` with colour writes off. Level `d` increments the pixels at `d − 1` that its region covers.
  An inverted level increments everything at `d − 1`, then decrements its region. Draws then test
  `EQUAL` to the depth. `glClear` ignores the stencil, so a clipped opaque clear is a quad. The
  window requests 8 stencil bits; `_GLTarget` and the multisampled target attach a depth-stencil
  renderbuffer. Under multisampling the stencil is per sample, so a GPU clip's edge is antialiased
  like a shape's, as the CPU's is by coverage. Disabling `GL_MULTISAMPLE` while writing the stencil
  would make it hard by the spec, but Mesa's llvmpipe then leaves part of each interior pixel's
  samples unmarked — don't retry it without checking on that driver.
- Cost: on the GPU, a clip change is a flush plus one draw per level of its chain. On the CPU, each
  clip is one rasterisation of its region per frame (per capture too), plus an index lookup per span.

`test_clip.mojo` asserts samples on both backends and compares frames only where the CPU frame is
flat (a pixel and its eight neighbours one colour), with an allowance for shapes' own edges: a
rotated edge differs between the two rasterisers, as it does for a plain rotated rectangle, and a
GPU clip's rim is multisampled.

## Antialiasing

**GPU:** `GLRenderer.render(..., samples)` draws into a `_MultisampleTarget` (colour and
depth-stencil renderbuffers) and blits it into the framebuffer that was bound — the window's, or a
headless `_GLTarget` — then rebinds that. The target is reallocated when the drawable size or the
sample count changes, and freed at `OFF`; the count is capped at `GL_MAX_SAMPLES`. Windows open
single-sampled, so the level can change without recreating the GL context.

**CPU:** `Backend.antialiasing` (an `Antialiasing`, seeded by the run loops and set by
`canvas.antialiasing`) applies to the CPU replay of the
shape kinds — rect, circle, line, Bézier, sector, polygon, triangle — through `Backend._shape`.
Clear, text, images, letterbox and blurred or inset shadows are untouched; a hard shadow is a
shape command, so it is antialiased like one.

- **Record at `grid`×.** `_shape` replays the command through the kind's own rasteriser
  (`_shape_pixels`) onto a recording surface `grid` times wider and taller, with `mat_scale(grid)`
  in front of the device matrix and `scale × grid` as the fallback pixel scale. So every rasteriser
  samples at sample centres instead of pixel centres, outline thickness and curve flattening
  refine with it, and no rasteriser knows. Each run is `(row, lo, hi, key)`, the key
  `_color_key(color)` or `GRADIENT_KEY`, so fill and outline stay apart.
- **Composite once** (`composite_coverage`): runs are bucketed by pixel row; each adds its coverage
  changes (partial samples at either end, `grid` between) to a difference array per paint and
  notes the columns it touches. The sorted touched columns split the row into stretches of constant
  coverage: full ones go to `fill_span` as one run, partial ones mix their paints premultiplied by
  sample share and blend once — so fill and outline crossing one pixel leave no seam, and a
  translucent shape stays one layer deep. A gradient's partial stretch samples per pixel.
- **Clip regions** take the same grid, recorded by `_clip_rows` itself (see Clips); `_shape`
  passes a recording surface straight to `_shape_pixels`.
- Hot loops index through pointers into `CoverageScratch` buffers kept on the `Backend`: checked
  `List` access cost as much as the compositing did.

Cost (`pixi run benchmark raster`, 1920×1080): 2000 small alpha shapes ~4.8 ms off, ~11 ms `LOW`,
~16 ms `MEDIUM`, ~23 ms `HIGH`; 20 outlined circles of radius 200 ~3.2 / 6 / 8 / 11.5 ms. Small
shapes are nearly all edge, so they pay most. The GPU's MSAA costs it little; it is unaffected.

## Reads

`canvas.pixel` and `canvas.snapshot` go through `Backend.read(width, height, scale, to_target,
seeded)`, antialiased as the frame is. It replays the commands recorded so far onto a `MemorySurface`, skipping the letterbox,
with `pre = to_target @ screen_inv`. `to_target` maps screen space to the read's pixels;
`screen_inv` is the window-pixel-to-screen mapping that `Canvas.__init__` hands over through
`begin_frame`. Like `present`, it moves the command buffer out and back. Pixels whose centre is off
the screen are made transparent afterwards, since a clear fills the whole target.
- `read_frame` caches the full-screen read at design size in `frame_read`. It stays current
  while `recorded` (bumped by every `record` and `record_clear`) is unchanged, and resets at present.
  `pixel` and a full-screen scale-1 `snapshot` share it.
- `seeded` (autoclear off): the first such read sets `keep_frames`. From then on `present` samples
  each finished CPU frame down to design size into `last_frame` (`_keep_frame`), and later
  reads start from it (`_seed`), nearest pixel.

**The image cache** (`Backend.images`) is keyed by a backend id per *image version*.
`intern_image(source, version, …)` reuses the copy only while `Image._version` matches, so an
edited image gets a new id and earlier commands keep the old copy. `_expire_images`, after each
present, drops copies unused for `IMAGE_KEEP_FRAMES` frames and tells `GLRenderer.forget_images` to
delete their textures.

## Captures

Requests filed on the `Backend` and serviced inside `present`/`present_gpu`, the only place holding
both the finished framebuffer and the unconsumed command buffer; a failed write raises from there.
- `canvas.save_image(path, scale, transparent)` — what the program drew: design size × `scale`,
  no letterbox, CPU-replayed from the commands under **both** backends (glyph cache and images live
  on `Backend`, not `GLRenderer`). Reproducible across machines.
- `canvas.save_screenshot(path)` — what the user saw: drawable resolution, bars included. On GPU this
  is a `glReadPixels` stall — fine on a keypress, not per frame.

See [examples/screenshot/src/main.mojo](../../../examples/screenshot/src/main.mojo).

## Outlines

Outlines mean different things per shape, and `corner_radius` must preserve that: a rectangle's is
an **inset ring** inside the fill; a triangle's is a **centred band**, half its width outside the
edges and half inside.

**Every kind composites once.** Fill and outline never overlap, and neither do pieces of either, so
a translucent shape or a non-`NORMAL` blend mode is as translucent everywhere.
`test_translucency.mojo` draws every kind at opacity 0.5 on both backends and fails on any pixel
deeper than one layer. A new shape or path must keep this:
- **Rectangles:** the fill is inset by the outline. The CPU's axis-aligned paths split each row into
  outline, fill, outline: four bands when sharp, `_rounded_box_row` when rounded. Rotated and
  stretched rectangles take the general affine path, which samples pixel **centres**, as every
  path must (it once sampled corners and drew a 40-pixel rectangle 41 wide).
- **Triangles:** a rounded or outlined triangle is `triangle_pieces`, the same pieces on both
  backends.
  - **Sharp:** the ring is one quad per edge between the outer edge (mitred, or bevelled past
    `MITER_LIMIT`) and the inner edge, which is the triangle scaled about its incentre.
  - **Rounded:** one quad per arc segment between concentric arcs of radius `r ± h`, and one per
    edge. Once `h ≥ r` the inner edge is sharp, and each corner is a fan from its inner vertex.
  - **Fill:** the inner edge as one convex polygon. The CPU fills it with `fill_convex`, which walks
    edges exactly as `fill_quad` does (slope precomputed from the lower end), so a shared edge
    gives bit-identical crossings. The GPU fans it.
  - A plain unoutlined sharp triangle keeps its single-pass fill.
  - Built in local space, with `h` the device thickness divided by the pixel scale, and mapped per
    point, so a sheared rounded corner stays an ellipse arc.

## Shadows

Both replays handle a command's shadow around the command itself, in the command's blend mode:
- **Outer** (`casts_outer_shadow`), *before* the command. Blur is quantised to whole device pixels
  (`Int(shadow_blur * pixel_scale + 0.5)`) by both backends identically; 0 replays
  `shadow_command(c, scale)` through the normal dispatch. Otherwise shapes and lines evaluate
  `BlurredSilhouette` coverage analytically (CPU per pixel over the reach; GPU one quad in
  `MODE_SHADOW_BOX`/`MODE_SHADOW_EDGES`), and text and images blur a mask (`_blur.mojo`): glyph
  masks are keyed by blur in the glyph cache and packed into the atlas; image masks are cached per
  `shadow_mask_key` in `Backend.shadow_masks` (CPU) and `GLRenderer.shadow_textures` (GPU), both
  dropped whole at `SHADOW_MASK_LIMIT`.
  A Bézier's stroke and a sector's or polygon's quads are rasterised into a mask and blurred too
  (`quads_shadow_mask`, via `bezier_shadow_mask`/`sector_shadow_mask`/`polygon_shadow_mask`), but
  **uncached**: they have no stable id to key by, so each blurred Bézier, sector or polygon shadow
  costs one blur per frame, and on
  the GPU one texture upload plus one draw call; the textures are deleted after the frame's final
  flush.
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
`blend` is only for genuinely per-pixel alpha (glyph coverage, image texels).

The command's `BlendMode` rides on the `Surface` (`_with_blend_mode`, set once in `Backend._one`), as
does its clip (see Clips), so no raster loop threads either; `blend` and `fill_span` read it and share `_blend_lanes` for every mode but
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
| `MODE_TEXTURE` | 2 | Image: sampled RGBA × colour |
| `MODE_SILHOUETTE` | 3 | Image shadow: sampled alpha scales colour alpha |
| `MODE_SHADOW_BOX` | 4 | Blurred rect/rounded rect/circle/line shadow; `s3` a ring |
| `MODE_SHADOW_EDGES` | 5 | Blurred triangle shadow, three edge distances; `s3` a ring |
| `MODE_INSET_BOX` / `MODE_INSET_EDGES` | 6 / 7 | 4 / 5 without ring, coverage inverted |
| `MODE_GRADIENT` | 8 | Gradient fill: `uv` the device mapping, `s0` radial, `s1` ramp row; samples unit 2, dithers |

A batch breaks only on an opaque `CMD_CLEAR`, a second distinct unit-1 texture, a `BlendMode`
change, a clip change (see Clips), or frame end — glyph atlas on texture unit 0, images on unit 1, gradient ramps on unit 2
(never rebound, so gradients batch with anything; a ramp texture refill flushes once). A blurred image shadow's
mask is its own unit-1 texture, so a shadowed image costs one extra draw call, and interleaving
several costs one per switch; a blurred Bézier, sector or polygon shadow likewise costs one. Blurred text shadows
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
