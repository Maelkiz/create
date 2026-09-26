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
| `_transform.mojo`, `_image.mojo`, `_fillet.mojo` | Shared by both replay paths (split out to avoid an import cycle, or so both agree on the numbers) |
| `_gl_target.mojo` | Offscreen FBO of an exact size, for the parity test and headless GPU |

## Canvas, commands and backends

A `Canvas` render call **records, never paints**: it appends a `RenderCommand` (local geometry,
transform at record time, style resolved now) to the `Backend`. Nothing rasterises until
`present`/`present_gpu` replays the frame, so later style calls can't reach back. Sprites are interned
into the backend at record time (the command carries an id); text is recorded as an owned `String`
and laid out at replay. Add a shape by extending `_command.mojo`'s kinds and `_backend.mojo`'s replay
(plus `_tessellate.mojo`), never by calling `_raster.mojo` from `Canvas`.

`Canvas` holds no `Surface` and takes its geometry from the `Viewport` alone — don't add a `Surface`
field or parameter, and don't import `_window` from `canvas.mojo`. What survives the frame boundary:
`PersistentCanvasState` (the `Backend` and `Viewport` — moved in and back out by `_release`) and
`Context` (owned by the loop, and home to `time` and `input`). The transform stack, style and camera deliberately don't.

The camera is folded into `RenderCommand.transform`; nothing below `Canvas` knows it exists.

`Backend.kind` selects the replay (`RenderBackend.CPU` onto a `Surface`, `GPU` through `GLRenderer`);
a field rather than a trait because Mojo has no dynamic dispatch.

The autoclear is a recorded `CMD_CLEAR`, so every path handles it: the GPU turns it into `glClear`,
an opaque `canvas.background()` replaces it via `Backend.record_clear`, and a transparent
`save_image` masks it out.

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

## CPU rasteriser

Compute each row's covered run analytically and hand `(start, count)` to `fill_span` once — never
test every pixel in a bounding box. `fill_span` owns the opaque-store and vectorised compositing.
`blend` is only for genuinely per-pixel alpha (glyph coverage, sprite texels).

The command's `BlendMode` rides on the `Surface` (`_with_blend_mode`, set once in `Backend._one`), so
no raster loop threads it; `blend` and `fill_span` read it and share `_blend_lanes` for every mode but
`NORMAL`. A new mode goes there and in `GLRenderer._blend_mode` — it must be one fixed-function GL
blend equation, which is why there is no `DIFFERENCE`.

## GPU path (OpenGL 3.3)

`_tessellate.mojo` bakes each command's transform into its vertices (9 × `Float32`: `x, y, u, v, r,
g, b, a, mode`; `mode` picks solid/glyph/texture in the shader), so everything accumulates into one
buffer and flushes as one `glBufferData` + `glDrawArrays`. A batch breaks only on an opaque
`CMD_CLEAR`, a second distinct sprite texture, a `BlendMode` change, or frame end — glyph atlas on texture unit 0, sprites
on unit 1. Per frame, only the viewport is written, and only on resize.

Before optimising: `examples/gl_bench.mojo` runs ~1.1 ms/frame; the vertex list stops reallocating
after frame 1; orphan-then-`glBufferSubData` measured identical to the current single `glBufferData`.
`examples/cpu_bench.mojo` measures CPU rasterisation headless.

**`render` reaches GL without `_window`:** `_gl.mojo` `dlopen`s SDL itself and resolves through
`SDL_GL_GetProcAddress`. A GL context must be current before `GL()` is constructed.

**FFI rules for `_gl.mojo`** (calls go through bitcast `thin abi("C")` pointers; this works):
1. A `String` whose pointer goes to C must outlive the call — put `_ = s` after it. Check every
   resolved address against 0.
2. Read C out-parameters from heap memory (`List`), not a local `InlineArray` — the optimizer may
   serve the local stale.
3. Keep the GL context owner alive past the last GL call (`_ = win^` in tests and spikes).
