"""The GPU half of `Backend` — a frame's commands as batched `glDrawArrays`.

The split with `_tessellate.mojo` is deliberate and load-bearing: *where* a
triangle goes is arithmetic and is decided there, testable with no context and
no GPU; this file is only the GL plumbing that uploads and renders it. Nothing
here decides geometry.

**One batch spans as many commands as it can.** The vertex buffer accumulates
across commands and is flushed only when something makes a shared draw call
impossible — an opaque `CMD_CLEAR` (which resets the framebuffer, so earlier
vertices must already have landed), a *second* sprite texture (a blurred
sprite shadow's mask counts: it is a texture of its own), a change of
`BlendMode` (blend state is per draw call), and the end of the frame. Solids, glyphs and one sprite share a batch because they sample
different things: the atlas is permanently on texture unit 0 and sprites go on
unit 1, so a sprite between two glyphs costs no rebind and text rendered over a
sprite — the obvious way to write a HUD — costs no break either. That is the
whole point of baking the
transform per vertex rather than passing it as a uniform: a per-command
uniform would force a draw call per command and there would be no batching to
speak of.

**Clearing follows the CPU replay rather than the obvious GL call.**
`_raster.fill_all` *composites* — a `background` with `a < 255` blends over
what was already rendered — so only an opaque clear becomes `glClear`. A
translucent one is a full-drawable quad in the batch, which blends, and an
`a == 0` one renders nothing at all.
"""

from std.collections import Dict, Optional
from std.memory import unsafe_memcpy

from create.math.matrix import apply as mat_apply

from ._command import (
    CMD_BEZIER,
    CMD_SECTOR,
    CMD_POLYGON,
    CMD_CIRCLE,
    CMD_CLEAR,
    CMD_LETTERBOX,
    CMD_LINE,
    CMD_RECT,
    CMD_SPRITE,
    CMD_TEXT,
    CMD_TRIANGLE,
    RenderCommand,
)
from ._gl import (
    GL,
    GL_ARRAY_BUFFER,
    GL_BLEND,
    GL_CLAMP_TO_EDGE,
    GL_COLOR_BUFFER_BIT,
    GL_COMPILE_STATUS,
    GL_DST_COLOR,
    GL_FALSE,
    GL_FLOAT,
    GL_FRAGMENT_SHADER,
    GL_FUNC_ADD,
    GL_FUNC_REVERSE_SUBTRACT,
    GL_INFO_LOG_LENGTH,
    GL_LINEAR,
    GL_LINK_STATUS,
    GL_MULTISAMPLE,
    GL_NEAREST,
    GL_ONE,
    GL_ONE_MINUS_DST_COLOR,
    GL_ONE_MINUS_SRC_ALPHA,
    GL_PACK_ALIGNMENT,
    GL_R8,
    GL_RGBA,
    GL_RGBA8,
    GL_RED,
    GL_SRC_ALPHA,
    GL_STREAM_DRAW,
    GL_TEXTURE0,
    GL_TEXTURE1,
    GL_TEXTURE2,
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_TEXTURE_MIN_FILTER,
    GL_TEXTURE_WRAP_S,
    GL_TEXTURE_WRAP_T,
    GL_TRIANGLES,
    GL_UNPACK_ALIGNMENT,
    GL_UNSIGNED_BYTE,
    GL_VERTEX_SHADER,
    _Bytes,
    _Address,
    _Ints,
    _Strings,
    _UInts,
)
from ._blur import (
    SHADOW_MASK_LIMIT,
    blur_reach,
    blur_sprite_alpha,
    shadow_mask_key,
)
from ._curve import PlacedMask, bezier_shadow_mask
from ._sector import sector_shadow_mask
from ._polygon import polygon_shadow_mask
from ._image import _Image
from ._tessellate import (
    MODE_SOLID,
    VertexBuffer,
    emit_bezier,
    emit_blurred_shadow,
    emit_circle,
    emit_glyph,
    emit_inset_shadow,
    emit_letterbox,
    emit_line,
    emit_rect,
    emit_polygon,
    emit_sector,
    emit_silhouette_mask,
    emit_sprite,
    emit_triangle,
)
from ._shadow import (
    blurs_analytically,
    casts_inset_shadow,
    casts_outer_shadow,
    shadow_command,
)
from ._text import PlacedGlyph, TextRenderer
from ._transform import pixel_scale
from .blend_mode import BlendMode
from .color import Color
from .gradient import Gradient, RAMP_SIZE

comptime _VERTEX_FLOATS = 13
"""Mirrors `_tessellate._VERTEX_FLOATS`, which the attribute layout below
unpacks into five attributes."""

comptime _RAMP_ROWS = 256
"""Gradient ramps the ramp texture holds at once, one per row. A frame with
more distinct gradients than this flushes and starts the texture over, so it
still renders, at a draw call per refill."""

comptime ATLAS_SIZE = 1024
"""The glyph atlas is square and fixed: a resize would have to re-pack and
re-upload every glyph mid-frame, and a face large enough to overflow a
megatexel of coverage is past what this backend is for."""

comptime _ATLAS_PAD = 1
"""Texels of blank left between packed glyphs, and before the first one.

`GL_LINEAR` samples a neighbourhood, so without a gutter a glyph's edge would
pick up the one packed beside it. The leading pad is also what keeps texel
(0, 0) — the white texel — out of the allocator's reach."""


comptime _VERTEX_SHADER = String(
    """#version 330 core
layout (location = 0) in vec2 a_pos;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec4 a_color;
layout (location = 3) in float a_mode;
layout (location = 4) in vec4 a_shape;

uniform vec2 u_viewport;

out vec2 v_uv;
out vec4 v_color;
out float v_mode;
out vec4 v_shape;

void main() {
    // Device pixels, y down, to NDC. The y flip is here rather than in the
    // tessellator so vertices stay in the same space the CPU replay scans.
    vec2 ndc = vec2(
        a_pos.x / u_viewport.x * 2.0 - 1.0,
        1.0 - a_pos.y / u_viewport.y * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    v_uv = a_uv;
    v_color = a_color;
    v_mode = a_mode;
    v_shape = a_shape;
}
"""
)

comptime _FRAGMENT_SHADER = String(
    """#version 330 core
in vec2 v_uv;
in vec4 v_color;
in float v_mode;
in vec4 v_shape;

uniform sampler2D u_atlas;
uniform sampler2D u_sprite;
uniform sampler2D u_ramp;
uniform int u_premultiply;
uniform vec2 u_viewport;

// `gradient.mojo`'s `_BAYER`, entry for entry.
const float BAYER[16] = float[16](
    0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0
);

out vec4 frag_color;

// Blurred shadow coverage: `_shadow.mojo`'s functions, term for term.
float gaussian_cdf(float x) {
    if (x >= 4.0) return 1.0;
    if (x <= -4.0) return 0.0;
    float z = abs(x) * 0.70710678118654752;
    float t = 1.0 / (1.0 + 0.3275911 * z);
    float poly = t * (0.254829592 + t * (-0.284496736
        + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
    float erf = 1.0 - poly * exp(-z * z);
    return x >= 0.0 ? 0.5 * (1.0 + erf) : 0.5 * (1.0 - erf);
}

float box_coverage(vec2 p, vec2 half_size, float radius) {
    if (radius <= 0.0) {
        float x = gaussian_cdf(half_size.x + p.x)
            + gaussian_cdf(half_size.x - p.x) - 1.0;
        float y = gaussian_cdf(half_size.y + p.y)
            + gaussian_cdf(half_size.y - p.y) - 1.0;
        return max(x, 0.0) * max(y, 0.0);
    }
    float r = min(radius, min(half_size.x, half_size.y));
    vec2 q = abs(p) - (half_size - r);
    float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    return gaussian_cdf(-sdf);
}

float edge_coverage(vec3 d) {
    return gaussian_cdf(d.x) * gaussian_cdf(d.y) * gaussian_cdf(d.z);
}

void main() {
    if (v_mode < 0.5) {
        frag_color = v_color;
    } else if (v_mode < 1.5) {
        frag_color = vec4(v_color.rgb, v_color.a * texture(u_atlas, v_uv).r);
    } else if (v_mode < 2.5) {
        frag_color = v_color * texture(u_sprite, v_uv);
    } else if (v_mode < 3.5) {
        frag_color = vec4(v_color.rgb, v_color.a * texture(u_sprite, v_uv).a);
    } else if (v_mode > 7.5) {
        // Gradient: `Gradient._sample`, with texture filtering reading
        // between ramp entries and the dither indexed by device pixel, rows
        // counted from the top as the CPU counts them.
        float t = clamp(v_shape.x > 0.5 ? length(v_uv) : v_uv.x, 0.0, 1.0);
        vec4 c = texture(u_ramp, vec2(
            (t * 255.0 + 0.5) / 256.0, (v_shape.y + 0.5) / 256.0
        ));
        ivec2 p = ivec2(gl_FragCoord.x, u_viewport.y - gl_FragCoord.y);
        float d = (BAYER[(p.y & 3) * 4 + (p.x & 3)] + 0.5) / 16.0;
        frag_color = min(floor(c * 255.0 + d), 255.0) / 255.0;
    } else {
        // `s3` is the ring: subtract the silhouette shrunk by it. Modes 6
        // and 7 are 4 and 5 inverted, for an inset shadow.
        float ring = v_shape.w;
        bool inset = v_mode > 5.5;
        float c;
        if (v_mode < 4.5 || (inset && v_mode < 6.5)) {
            c = box_coverage(v_uv, v_shape.xy, v_shape.z);
            if (ring > 0.0 && c > 0.0) {
                c -= box_coverage(
                    v_uv, v_shape.xy - ring, max(v_shape.z - ring, 0.0)
                );
            }
        } else {
            c = edge_coverage(v_shape.xyz);
            if (ring > 0.0 && c > 0.0) {
                c -= edge_coverage(v_shape.xyz - ring);
            }
        }
        if (inset) {
            c = 1.0 - c;
        }
        frag_color = vec4(v_color.rgb, v_color.a * max(c, 0.0));
    }
    // Every blend mode but NORMAL is written against premultiplied colour;
    // see `GLRenderer._blend_mode`.
    if (u_premultiply != 0) {
        frag_color.rgb *= frag_color.a;
    }
}
"""
)


def _gen_object(gen: def(Int32, _UInts) thin abi("C") -> None) -> UInt32:
    """One GL object name, read back off the heap.

    Rule 2 from `_gl.mojo`: the name is a C out-parameter, so it comes back
    through a `List` rather than a local array.
    """
    var buf = List[UInt32](length=1, fill=0)
    gen(1, _UInts(unsafe_from_address=Int(buf.unsafe_ptr())))
    return buf[0]


def _delete_object(
    delete: def(Int32, _UInts) thin abi("C") -> None, name: UInt32
):
    var buf = List[UInt32](length=1, fill=name)
    delete(1, _UInts(unsafe_from_address=Int(buf.unsafe_ptr())))
    _ = buf^


def _info_log(
    length: Int,
    get: def(UInt32, Int32, _Address, _Bytes) thin abi("C") -> None,
    name: UInt32,
) -> String:
    if length <= 0:
        return String("(no log)")
    var buf = List[UInt8](length=length + 1, fill=0)
    get(
        name,
        Int32(length),
        0,
        _Bytes(unsafe_from_address=Int(buf.unsafe_ptr())),
    )
    var out = String(unsafe_from_utf8_ptr=buf.unsafe_ptr())
    _ = buf^
    return out^


def _compile(gl: GL, kind: UInt32, src: String) raises -> UInt32:
    """One compiled shader, or an error carrying the driver's log.

    The source is passed NUL-terminated with a null length array, and
    `_ = src` keeps it alive across the call — rule 1.
    """
    var shader = gl.create_shader(kind)
    var ptrs = List[_Bytes](
        length=1, fill=_Bytes(unsafe_from_address=Int(src.unsafe_ptr()))
    )
    gl.shader_source(
        shader,
        1,
        _Strings(unsafe_from_address=Int(ptrs.unsafe_ptr())),
        0,
    )
    _ = ptrs^
    _ = src
    gl.compile_shader(shader)

    var status = List[Int32](length=1, fill=0)
    gl.get_shaderiv(
        shader,
        GL_COMPILE_STATUS,
        _Ints(unsafe_from_address=Int(status.unsafe_ptr())),
    )
    if status[0] == 0:
        var length = List[Int32](length=1, fill=0)
        gl.get_shaderiv(
            shader,
            GL_INFO_LOG_LENGTH,
            _Ints(unsafe_from_address=Int(length.unsafe_ptr())),
        )
        var log = _info_log(Int(length[0]), gl.get_shader_info_log, shader)
        gl.delete_shader(shader)
        raise Error("GL shader failed to compile: " + log)
    return shader


def _link(gl: GL) raises -> UInt32:
    var vertex = _compile(gl, GL_VERTEX_SHADER, _VERTEX_SHADER)
    var fragment = _compile(gl, GL_FRAGMENT_SHADER, _FRAGMENT_SHADER)
    var program = gl.create_program()
    gl.attach_shader(program, vertex)
    gl.attach_shader(program, fragment)
    gl.link_program(program)
    # Attached shaders are freed with the program once it is linked.
    gl.delete_shader(vertex)
    gl.delete_shader(fragment)

    var status = List[Int32](length=1, fill=0)
    gl.get_programiv(
        program,
        GL_LINK_STATUS,
        _Ints(unsafe_from_address=Int(status.unsafe_ptr())),
    )
    if status[0] == 0:
        var length = List[Int32](length=1, fill=0)
        gl.get_programiv(
            program,
            GL_INFO_LOG_LENGTH,
            _Ints(unsafe_from_address=Int(length.unsafe_ptr())),
        )
        var log = _info_log(Int(length[0]), gl.get_program_info_log, program)
        gl.delete_program(program)
        raise Error("GL shader program failed to link: " + log)
    return program


struct _AtlasRect(ImplicitlyCopyable, Movable):
    """Where one glyph's mask sits in the atlas, in texels."""

    var x: Int
    var y: Int
    var w: Int
    var h: Int

    def __init__(out self, x: Int, y: Int, w: Int, h: Int):
        self.x = x
        self.y = y
        self.w = w
        self.h = h


struct GLRenderer(Movable):
    """Everything the GPU path owns: the entry points, one VAO/VBO, the shader
    program, the glyph atlas, and the vertex buffer they are fed from.

    Constructing one requires a current GL context — `GL()` does — so it is
    built by the GL run loop after the window, never eagerly.
    """

    var gl: GL
    var vao: UInt32
    var vbo: UInt32
    var program: UInt32
    var u_viewport: Int32
    var u_premultiply: Int32
    var blend_mode: BlendMode
    """The mode the GL blend state is set for. Kept across frames, like
    `bound`, since nothing else in the library sets blend state."""
    var viewport_w: Int
    var viewport_h: Int
    """What `u_viewport` and `glViewport` were last set to. The program, the
    VAO and the sampler uniforms are set once at construction and never
    touched again, so a steady frame's only fixed cost is the atlas bind."""
    var atlas: UInt32
    var glyphs: Dict[Int, _AtlasRect]
    """Glyph cache key to its rect in the atlas. Keyed by `TextRenderer`'s own
    key, so a size or weight that misses there misses here too and the two
    caches cannot disagree about what a key means."""
    var shelf_x: Int
    var shelf_y: Int
    var shelf_h: Int
    """The shelf allocator's cursor: glyphs fill a row left to right, then a
    new row starts below the tallest glyph of the last one. Nothing is ever
    freed — the atlas is reset whole or not at all."""
    var font_generation: Int
    """The `TextRenderer.font_generation` these rects were packed against."""
    var textures: Dict[Int, UInt32]
    """Backend image id to GL texture name. The id is already the interning
    key on `Backend.images`, so a sprite rendered a thousand times is one entry
    and one upload; the pixels are read from the `_Image` only the first
    time."""
    var shadow_textures: Dict[Int, UInt32]
    """Blurred sprite silhouettes as textures, keyed by `shadow_mask_key`
    like the CPU's `Backend.shadow_masks`. Each is a texture of its own on
    the sprite unit, so a blurred sprite shadow costs a draw call per
    distinct mask it switches to, where a hard one samples the sprite's own
    texture and costs none."""
    var frame_textures: List[UInt32]
    """Textures used for one frame only — blurred curve shadows, whose masks
    have no stable key to cache by — deleted once the frame's last batch has
    drawn."""
    var ramps: UInt32
    """Gradient ramps, `RAMP_SIZE` texels a row, permanently on unit 2."""
    var ramp_rows: Dict[Int, List[Int]]
    """`Gradient._stops_key` to the rows holding ramps of that key — usually
    one; more only on a hash collision, told apart by `ramp_gradients`."""
    var ramp_gradients: List[Gradient]
    """The gradient whose ramp each row holds, in row order. Kept across
    frames, so a gradient built once in `create` uploads once."""
    var bound: UInt32
    """What is on texture unit 1 — the sprite unit — right now. Kept across
    frames, since nothing else in the library binds there. A batch is one
    `glDrawArrays`, so replacing it has to flush first; the atlas on unit 0 is
    never replaced and so never forces one."""
    var vertices: VertexBuffer
    var draw_calls: Int
    """Batches flushed by the last `render`. Read by the bench example and the
    Phase 8 performance work; it costs one increment a batch."""

    def __init__(out self) raises:
        self.gl = GL()
        self.program = _link(self.gl)
        self.vao = _gen_object(self.gl.gen_vertex_arrays)
        self.vbo = _gen_object(self.gl.gen_buffers)
        self.viewport_w = 0
        self.viewport_h = 0
        self.atlas = _gen_object(self.gl.gen_textures)
        self.glyphs = Dict[Int, _AtlasRect]()
        self.shelf_x = _ATLAS_PAD
        self.shelf_y = 0
        self.shelf_h = 1
        self.font_generation = 0
        self.textures = Dict[Int, UInt32]()
        self.shadow_textures = Dict[Int, UInt32]()
        self.frame_textures = List[UInt32]()
        self.ramps = _gen_object(self.gl.gen_textures)
        self.ramp_rows = Dict[Int, List[Int]]()
        self.ramp_gradients = List[Gradient]()
        self.bound = 0
        self.vertices = VertexBuffer()
        self.draw_calls = 0

        var name = String("u_viewport")
        self.u_viewport = self.gl.get_uniform_location(
            self.program, _Bytes(unsafe_from_address=Int(name.unsafe_ptr()))
        )
        _ = name
        var premultiply = String("u_premultiply")
        self.u_premultiply = self.gl.get_uniform_location(
            self.program,
            _Bytes(unsafe_from_address=Int(premultiply.unsafe_ptr())),
        )
        _ = premultiply
        self.blend_mode = BlendMode.NORMAL
        self._setup_vertex_array()
        self._setup_atlas()
        self._setup_ramps()

        # Set once: nothing here varies per frame, and the program and VAO are
        # the only ones this process ever binds.
        self.gl.use_program(self.program)
        self.gl.bind_vertex_array(self.vao)
        self._sampler_unit("u_atlas", 0)
        self._sampler_unit("u_sprite", 1)
        self._sampler_unit("u_ramp", 2)

        self.gl.enable(GL_BLEND)
        # Straight (non-premultiplied) alpha, matching `_raster.blend`, so a
        # translucent fill composites identically on both backends.
        self.gl.blend_func(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        self.gl.enable(GL_MULTISAMPLE)
        self.gl.check("initialising the GL renderer")

    def __deinit__(deinit self):
        self.gl.delete_program(self.program)
        _delete_object(self.gl.delete_buffers, self.vbo)
        _delete_object(self.gl.delete_vertex_arrays, self.vao)
        _delete_object(self.gl.delete_textures, self.atlas)
        _delete_object(self.gl.delete_textures, self.ramps)
        for ref entry in self.textures.items():
            _delete_object(self.gl.delete_textures, entry.value)
        for ref entry in self.shadow_textures.items():
            _delete_object(self.gl.delete_textures, entry.value)

    def _setup_vertex_array(mut self):
        """Bind the VAO once and record the interleaved attribute layout.

        Nothing rebinds these per frame: a VAO remembers the pointers and the
        enables, which is the whole reason to have one.
        """
        comptime stride = Int32(_VERTEX_FLOATS * 4)
        self.gl.bind_vertex_array(self.vao)
        self.gl.bind_buffer(GL_ARRAY_BUFFER, self.vbo)
        self.gl.vertex_attrib_pointer(0, 2, GL_FLOAT, GL_FALSE, stride, 0)
        self.gl.enable_vertex_attrib_array(0)
        self.gl.vertex_attrib_pointer(1, 2, GL_FLOAT, GL_FALSE, stride, 8)
        self.gl.enable_vertex_attrib_array(1)
        self.gl.vertex_attrib_pointer(2, 4, GL_FLOAT, GL_FALSE, stride, 16)
        self.gl.enable_vertex_attrib_array(2)
        self.gl.vertex_attrib_pointer(3, 1, GL_FLOAT, GL_FALSE, stride, 32)
        self.gl.enable_vertex_attrib_array(3)
        self.gl.vertex_attrib_pointer(4, 4, GL_FLOAT, GL_FALSE, stride, 36)
        self.gl.enable_vertex_attrib_array(4)

    def _setup_atlas(mut self) raises:
        """A single-channel coverage atlas, allocated blank.

        `_pack` fills it a glyph at a time with `glTexSubImage2D`; allocating
        it whole up front is what lets those uploads be sub-images and what
        makes a sampler safe to read before any text is rendered. Texel (0, 0) is
        left opaque and outside the allocator's reach, so a `MODE_MASK` quad
        can sample "full coverage" without a glyph.

        Unit 0 is the atlas's for the life of the renderer: it is bound here
        and never replaced, which is what lets glyphs batch with sprites.
        """
        self.gl.active_texture(GL_TEXTURE0)
        self.gl.bind_texture(GL_TEXTURE_2D, self.atlas)
        # One byte per texel: the default four-byte row alignment would
        # mis-stride every upload whose width is not a multiple of four.
        self.gl.pixel_storei(GL_UNPACK_ALIGNMENT, 1)
        var blank = List[UInt8](length=ATLAS_SIZE * ATLAS_SIZE, fill=0)
        blank[0] = 255
        self.gl.tex_image_2d(
            GL_TEXTURE_2D,
            0,
            GL_R8,
            Int32(ATLAS_SIZE),
            Int32(ATLAS_SIZE),
            0,
            GL_RED,
            GL_UNSIGNED_BYTE,
            Int(blank.unsafe_ptr()),
        )
        _ = blank^
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
        )
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE
        )

    def _setup_ramps(mut self) raises:
        """The gradient ramp texture, allocated blank on unit 2 for good.

        Filtered linearly along a row, which is the CPU's read between two
        ramp entries; a row is sampled at its centre, so its neighbours never
        bleed in.
        """
        self.gl.active_texture(GL_TEXTURE2)
        self.gl.bind_texture(GL_TEXTURE_2D, self.ramps)
        var blank = List[UInt8](length=RAMP_SIZE * _RAMP_ROWS * 4, fill=0)
        self.gl.tex_image_2d(
            GL_TEXTURE_2D,
            0,
            GL_RGBA8,
            Int32(RAMP_SIZE),
            Int32(_RAMP_ROWS),
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            Int(blank.unsafe_ptr()),
        )
        _ = blank^
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
        )
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE
        )

    def _ramp_row(mut self, c: RenderCommand) raises -> Int:
        """The ramp texture row holding `c`'s fill gradient's ramp, uploading
        it on first sight; -1 when `c` fills with no gradient."""
        if not c.style.fill_gradient or not c.style._fill_visible():
            return -1
        ref gradient = c.style.fill_gradient.value()
        var key = gradient._stops_key()
        if key in self.ramp_rows:
            for row in self.ramp_rows[key]:
                if self.ramp_gradients[row]._same_stops(gradient):
                    return row
        if len(self.ramp_gradients) == _RAMP_ROWS:
            # Full: what is batched still reads the old rows, so draw it
            # before any is overwritten.
            self._flush()
            self.ramp_rows.clear()
            self.ramp_gradients.clear()
        var row = len(self.ramp_gradients)
        self.ramp_gradients.append(gradient)
        if key not in self.ramp_rows:
            self.ramp_rows[key] = List[Int]()
        self.ramp_rows[key].append(row)
        var texels = List[UInt8](capacity=RAMP_SIZE * 4)
        for ref color in gradient._ramp[]:
            texels.append(color.r)
            texels.append(color.g)
            texels.append(color.b)
            texels.append(color.a)
        # An upload targets whatever is bound, so name the ramps' unit.
        self.gl.active_texture(GL_TEXTURE2)
        self.gl.tex_sub_image_2d(
            GL_TEXTURE_2D,
            0,
            0,
            Int32(row),
            Int32(RAMP_SIZE),
            1,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            _Bytes(unsafe_from_address=Int(texels.unsafe_ptr())),
        )
        _ = texels^
        return row

    def _sampler_unit(mut self, name: String, unit: Int32) raises:
        """Point one sampler uniform at a texture unit, for good."""
        var location = self.gl.get_uniform_location(
            self.program, _Bytes(unsafe_from_address=Int(name.unsafe_ptr()))
        )
        _ = name
        self.gl.uniform_1i(location, unit)

    def render(
        mut self,
        cmds: List[RenderCommand],
        images: Dict[Int, _Image],
        mut text: TextRenderer,
        width: Int,
        height: Int,
        scale: Float64,
    ) raises:
        """Replay `cmds` onto the current drawable, `width` x `height` pixels.

        `width`/`height` are the *drawable's*, not the viewport's — under
        display scaling the two differ, and the letterbox bars have to reach
        the real edge of the frame.
        """
        if width != self.viewport_w or height != self.viewport_h:
            # A resize, so once in a while — everything else the render needs is
            # already set from construction.
            self.gl.viewport(0, 0, Int32(width), Int32(height))
            self.gl.uniform_2f(self.u_viewport, Float32(width), Float32(height))
            self.viewport_w = width
            self.viewport_h = height

        self.vertices.clear()
        self.draw_calls = 0
        for ref c in cmds:
            # An opaque clear draws nothing, so its mode (always `NORMAL`)
            # must not force a flush; a translucent one sets it in `_clear`.
            if c.kind != CMD_CLEAR:
                self._blend_mode(c.style.blend_mode)
            # The shadow shares the command's blend mode, so it joins the
            # same batch; a sprite's samples the sprite's own texture.
            if casts_outer_shadow(c):
                var sh = shadow_command(c, scale)
                # Quantised as the CPU replay does, so both agree on when a
                # shadow is hard and which cached mask a soft one uses.
                var blur = Int(
                    c.style.shadow_blur * pixel_scale(sh.transform, scale) + 0.5
                )
                if blur == 0:
                    self._one(sh, images, text, width, height, scale)
                elif blurs_analytically(c):
                    emit_blurred_shadow(self.vertices, sh, scale)
                elif c.kind == CMD_TEXT:
                    self._text(sh, text, scale, blur)
                elif c.kind == CMD_SPRITE:
                    self._sprite_shadow(sh, images, scale, blur)
                elif c.kind == CMD_BEZIER:
                    self._mask_shadow(
                        bezier_shadow_mask(sh, sh.transform, scale, blur),
                        c.style.shadow_color,
                    )
                elif c.kind == CMD_SECTOR:
                    self._mask_shadow(
                        sector_shadow_mask(sh, sh.transform, scale, blur),
                        c.style.shadow_color,
                    )
                elif c.kind == CMD_POLYGON:
                    self._mask_shadow(
                        polygon_shadow_mask(sh, sh.transform, scale, blur),
                        c.style.shadow_color,
                    )
            self._one(c, images, text, width, height, scale)
            # Over the command, clipped to its interior; solid-mode
            # geometry, so it batches with anything.
            if casts_inset_shadow(c):
                emit_inset_shadow(self.vertices, c, scale)
        self._flush()
        for name in self.frame_textures:
            _delete_object(self.gl.delete_textures, name)
            if name == self.bound:
                self.bound = 0
        self.frame_textures.clear()

    def _one(
        mut self,
        c: RenderCommand,
        images: Dict[Int, _Image],
        mut text: TextRenderer,
        width: Int,
        height: Int,
        scale: Float64,
    ) raises:
        """Emit one command's geometry. The blend state is already set."""
        # A fill gradient's ramp row is looked up before its command emits
        # anything: claiming a row can flush the batch.
        if c.kind == CMD_CLEAR:
            self._clear(c.style.fill_color, width, height)
        elif c.kind == CMD_RECT:
            var row = self._ramp_row(c)
            emit_rect(self.vertices, c, scale, row)
        elif c.kind == CMD_CIRCLE:
            var row = self._ramp_row(c)
            emit_circle(self.vertices, c, scale, row)
        elif c.kind == CMD_LINE:
            emit_line(self.vertices, c, scale)
        elif c.kind == CMD_BEZIER:
            emit_bezier(self.vertices, c, scale)
        elif c.kind == CMD_SECTOR:
            var row = self._ramp_row(c)
            emit_sector(self.vertices, c, scale, row)
        elif c.kind == CMD_POLYGON:
            var row = self._ramp_row(c)
            emit_polygon(self.vertices, c, scale, row)
        elif c.kind == CMD_TRIANGLE:
            var row = self._ramp_row(c)
            emit_triangle(self.vertices, c, scale, row)
        elif c.kind == CMD_SPRITE:
            self._sprite(c, images, scale)
        elif c.kind == CMD_TEXT:
            self._text(c, text, scale)
        elif c.kind == CMD_LETTERBOX:
            # Bars are solid, but they must land over whatever texture is
            # bound, so no rebind here — `MODE_SOLID` never samples.
            emit_letterbox(self.vertices, c, width, height)

    def read_frame(mut self, width: Int, height: Int) raises -> List[UInt8]:
        """Read the current drawable back as `width` x `height` RGBA bytes.

        Rows come back top-down, matching every `Surface` in this library;
        `glReadPixels` hands them over bottom-up, so they are flipped here.

        A readback stalls the pipeline: the driver has to finish everything
        queued before it can answer. That is the whole reason this is not on
        the per-frame path — once, on a keypress, it costs one frame's
        latency, which is a different regime from reading every frame back.
        """
        var flipped = List[UInt8](length=width * height * 4, fill=0)
        self.gl.pixel_storei(GL_PACK_ALIGNMENT, 1)
        self.gl.read_pixels(
            0,
            0,
            Int32(width),
            Int32(height),
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            _Bytes(unsafe_from_address=Int(flipped.unsafe_ptr())),
        )
        self.gl.check("reading the frame back")

        var out = List[UInt8](length=width * height * 4, fill=0)
        var row = width * 4
        for y in range(height):
            var src = (height - 1 - y) * row
            var dst = y * row
            unsafe_memcpy(
                dest=out.unsafe_ptr().unsafe_offset(dst),
                src=flipped.unsafe_ptr().unsafe_offset(src),
                count=row,
            )
        _ = flipped^
        return out^

    def _text(
        mut self,
        c: RenderCommand,
        mut text: TextRenderer,
        scale: Float64,
        blur: Int = 0,
    ) raises:
        """`CMD_TEXT`, laid out by the same function the CPU replay uses.

        A blurred shadow's glyphs are just other keys to `layout`, packed into
        the same atlas beside the sharp ones — so they cost no draw call.
        """
        if c.style.text_color.a == 0:
            return
        if text.font_generation != self.font_generation:
            # A different face behind the same keys: the packed masks are the
            # old face's, so the shelves start over.
            self.glyphs.clear()
            self.shelf_x = _ATLAS_PAD
            self.shelf_y = 0
            self.shelf_h = 1
            self.font_generation = text.font_generation
        var m = c.transform
        # Only the anchor is mapped — the layout happens in pixel space.
        var p = mat_apply(m, c.geom[0], c.geom[1])
        var placed = text.layout(
            c.text, p[0], p[1], c.style, pixel_scale(m, scale), blur
        )
        if len(placed) == 0:
            return
        comptime inv = 1.0 / Float64(ATLAS_SIZE)
        for ref g in placed:
            var r = self._pack(g, text)
            emit_glyph(
                self.vertices,
                Float64(g.x),
                Float64(g.y),
                Float64(g.width),
                Float64(g.height),
                Float64(r.x) * inv,
                Float64(r.y) * inv,
                Float64(r.x + r.w) * inv,
                Float64(r.y + r.h) * inv,
                c.style.text_color,
            )

    def _pack(
        mut self, g: PlacedGlyph, mut text: TextRenderer
    ) raises -> _AtlasRect:
        """The glyph's rect in the atlas, uploading its mask on first sight."""
        if g.key in self.glyphs:
            return self.glyphs[g.key]
        if self.shelf_x + g.width + _ATLAS_PAD > ATLAS_SIZE:
            self.shelf_x = _ATLAS_PAD
            self.shelf_y += self.shelf_h + _ATLAS_PAD
            self.shelf_h = 1
        if self.shelf_y + g.height > ATLAS_SIZE:
            raise Error(
                "the GL glyph atlas is full — "
                + String(len(self.glyphs))
                + " glyphs packed into "
                + String(ATLAS_SIZE)
                + "x"
                + String(ATLAS_SIZE)
            )
        var rect = _AtlasRect(self.shelf_x, self.shelf_y, g.width, g.height)
        self.shelf_x += g.width + _ATLAS_PAD
        self.shelf_h = max(self.shelf_h, g.height)

        # An upload targets whatever is bound, so name the atlas's unit; a
        # sprite may well be current on unit 1.
        var mask = text.glyph_mask(g.key)
        self.gl.active_texture(GL_TEXTURE0)
        self.gl.pixel_storei(GL_UNPACK_ALIGNMENT, 1)
        self.gl.tex_sub_image_2d(
            GL_TEXTURE_2D,
            0,
            Int32(rect.x),
            Int32(rect.y),
            Int32(rect.w),
            Int32(rect.h),
            GL_RED,
            GL_UNSIGNED_BYTE,
            _Bytes(unsafe_from_address=Int(mask.unsafe_ptr())),
        )
        _ = mask^
        self.glyphs[g.key] = rect
        return rect

    def _bind(mut self, name: UInt32) raises:
        """Put `name` on the sprite unit, flushing first if that replaces a
        texture the batch so far is sampling."""
        if name == self.bound:
            return
        self._flush()
        self.gl.active_texture(GL_TEXTURE1)
        self.gl.bind_texture(GL_TEXTURE_2D, name)
        self.bound = name

    def _sprite(
        mut self, c: RenderCommand, images: Dict[Int, _Image], scale: Float64
    ) raises:
        if c.image not in images:
            return
        self._bind(self._texture(c.image, images))
        emit_sprite(self.vertices, c, scale)

    def _texture(mut self, id: Int, images: Dict[Int, _Image]) raises -> UInt32:
        """The GL texture for a backend image id, uploaded on first use."""
        if id in self.textures:
            return self.textures[id]
        # Uploading rebinds unit 1 itself, ahead of `_bind`'s own check — so
        # whatever the batch so far is sampling from unit 1 must be flushed
        # here, or it silently gets rendered under this new texture instead.
        self._flush()
        ref img = images[id]
        var name = self._upload(
            img.width, img.height, Int(img.pixels.unsafe_ptr()), GL_LINEAR
        )
        # The bind above went behind `_bind`'s back; tell it what is current.
        # Nothing was batched against the old binding — `_sprite` calls this
        # through `_bind`, which flushed first.
        self.bound = name
        self.textures[id] = name
        return name

    def _sprite_shadow(
        mut self,
        c: RenderCommand,
        images: Dict[Int, _Image],
        scale: Float64,
        blur: Int,
    ) raises:
        """The silhouette command `c` blurred by `blur` device pixels: the
        CPU replay's mask, uploaded once and drawn over `_sprite`'s rect
        grown by the blur's reach."""
        if c.image not in images:
            return
        var sf = pixel_scale(c.transform, scale)
        var dw = max(Int(c.geom[2] * sf + 0.5), 1)
        var dh = max(Int(c.geom[3] * sf + 0.5), 1)
        var sigma = Float64(blur) / 2.0
        var key = shadow_mask_key(c.image, dw, dh, blur)
        if key in self.shadow_textures:
            self._bind(self.shadow_textures[key])
        else:
            # Uploading rebinds the sprite unit, so whatever the batch so far
            # samples there has to land first — as in `_texture`.
            self._flush()
            if len(self.shadow_textures) >= SHADOW_MASK_LIMIT:
                for ref entry in self.shadow_textures.items():
                    _delete_object(self.gl.delete_textures, entry.value)
                self.shadow_textures.clear()
            ref img = images[c.image]
            var mask = blur_sprite_alpha(
                img.pixels.unsafe_ptr(), img.width, img.height, dw, dh, sigma
            )
            # White with the mask in alpha: `MODE_SILHOUETTE` reads only
            # alpha, and RGBA keeps every texture on the sprite unit alike.
            var rgba = List[UInt8](
                length=mask.width * mask.height * 4, fill=255
            )
            for i in range(mask.width * mask.height):
                rgba[i * 4 + 3] = mask.pixels[i]
            # Texels land one-to-one on device pixels, so nearest sampling
            # reads each exactly, as `blit_alpha` does.
            var name = self._upload(
                mask.width, mask.height, Int(rgba.unsafe_ptr()), GL_NEAREST
            )
            _ = rgba^
            self.bound = name
            self.shadow_textures[key] = name
        emit_sprite(self.vertices, c, scale, blur_reach(sigma))

    def _mask_shadow(mut self, placed: PlacedMask, color: Color) raises:
        """A blurred curve or sector shadow: the CPU replay's mask, uploaded
        for this frame only and drawn as one quad where the CPU blits it."""
        ref mask = placed.mask
        if mask.width == 0 or mask.height == 0:
            return
        # Uploading rebinds the sprite unit; see `_sprite_shadow`.
        self._flush()
        var rgba = List[UInt8](length=mask.width * mask.height * 4, fill=255)
        for i in range(mask.width * mask.height):
            rgba[i * 4 + 3] = mask.pixels[i]
        var name = self._upload(
            mask.width, mask.height, Int(rgba.unsafe_ptr()), GL_NEAREST
        )
        _ = rgba^
        self.bound = name
        self.frame_textures.append(name)
        emit_silhouette_mask(
            self.vertices,
            Float64(placed.x),
            Float64(placed.y),
            Float64(mask.width),
            Float64(mask.height),
            color,
        )

    def _upload(
        mut self, width: Int, height: Int, pixels: Int, filter: Int32
    ) raises -> UInt32:
        """A new RGBA texture of the `width` x `height` pixels at address
        `pixels`, left bound on the sprite unit. The caller flushes first and
        records the binding in `bound`."""
        var name = _gen_object(self.gl.gen_textures)
        self.gl.active_texture(GL_TEXTURE1)
        self.gl.bind_texture(GL_TEXTURE_2D, name)
        self.gl.pixel_storei(GL_UNPACK_ALIGNMENT, 1)
        self.gl.tex_image_2d(
            GL_TEXTURE_2D,
            0,
            GL_RGBA8,
            Int32(width),
            Int32(height),
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            pixels,
        )
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
        self.gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
        )
        self.gl.tex_parameteri(
            GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE
        )
        return name

    def _clear(mut self, color: Color, width: Int, height: Int) raises:
        """`CMD_CLEAR`, composited the way the CPU replay composites it."""
        if color.a == 0:
            return
        if color.a == 255:
            # Opaque: the cheap path, but it wipes the framebuffer, so
            # anything already batched has to land first.
            self._flush()
            self.gl.clear_color(
                Float32(Int(color.r)) / 255.0,
                Float32(Int(color.g)) / 255.0,
                Float32(Int(color.b)) / 255.0,
                1.0,
            )
            self.gl.clear(GL_COLOR_BUFFER_BIT)
            return
        self._blend_mode(BlendMode.NORMAL)
        var w = Float64(width)
        var h = Float64(height)
        self.vertices.quad(0.0, 0.0, w, 0.0, w, h, 0.0, h, color)

    def _blend_mode(mut self, mode: BlendMode) raises:
        """Set the GL blend state for `mode`, flushing first if that changes
        it — blend state applies to a whole draw call.

        `NORMAL` is the straight-alpha `glBlendFunc` set at construction.
        The other modes cannot be written against straight alpha — `MULTIPLY`
        needs `s * a * d`, `SCREEN` needs `s * a * (1 - d)` — so the shader
        premultiplies for them, and each becomes one fixed-function equation
        matching `_raster._blend_lanes`:

        | Mode | Colour |
        |---|---|
        | `ADD` | `s*a + d` |
        | `SUBTRACT` | `d - s*a` |
        | `MULTIPLY` | `s*a * d + d * (1 - a)` |
        | `SCREEN` | `s*a * (1 - d) + d` |

        Alpha is `a + d.a * (1 - a)` for all four, source-over as on the CPU.
        """
        if mode == self.blend_mode:
            return
        self._flush()
        if mode == BlendMode.NORMAL:
            self.gl.blend_equation_separate(GL_FUNC_ADD, GL_FUNC_ADD)
            self.gl.blend_func(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
            self.gl.uniform_1i(self.u_premultiply, 0)
        else:
            var src = GL_ONE
            var dst = GL_ONE
            var equation = GL_FUNC_ADD
            if mode == BlendMode.SUBTRACT:
                equation = GL_FUNC_REVERSE_SUBTRACT
            elif mode == BlendMode.MULTIPLY:
                src = GL_DST_COLOR
                dst = GL_ONE_MINUS_SRC_ALPHA
            elif mode == BlendMode.SCREEN:
                src = GL_ONE_MINUS_DST_COLOR
            self.gl.blend_equation_separate(equation, GL_FUNC_ADD)
            self.gl.blend_func_separate(
                src, dst, GL_ONE, GL_ONE_MINUS_SRC_ALPHA
            )
            self.gl.uniform_1i(self.u_premultiply, 1)
        self.blend_mode = mode

    def _flush(mut self) raises:
        """Upload what has accumulated and render it as one batch.

        One `glBufferData` per batch rather than an orphan followed by a
        `glBufferSubData`: respecifying the whole store *is* the orphan, so
        the two-call version was doing the same thing twice, and dropping it
        measured identical (1.03-1.13 ms either way on the bench sketch).
        """
        var count = self.vertices.count()
        if count == 0:
            return
        var size = len(self.vertices.data) * 4
        var src = Int(self.vertices.data.unsafe_ptr())
        self.gl.bind_buffer(GL_ARRAY_BUFFER, self.vbo)
        self.gl.buffer_data(GL_ARRAY_BUFFER, Int64(size), src, GL_STREAM_DRAW)
        self.gl.draw_arrays(GL_TRIANGLES, 0, Int32(count))
        self.vertices.clear()
        self.draw_calls += 1
