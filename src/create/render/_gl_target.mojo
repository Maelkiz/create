"""An offscreen render target: a texture-backed framebuffer object at an
exact pixel size no window manager can veto.

Exists for headless GL work — `tests/render/test_gl_parity.mojo`'s frame
comparison and, later, `run_headless(..., backend=RenderBackend.GPU)` — where
the frame has to land in a buffer of a known size rather than whatever
drawable the window happens to hand back.
"""

from ._gl import (
    GL,
    GL_CLAMP_TO_EDGE,
    GL_COLOR_ATTACHMENT0,
    GL_DEPTH24_STENCIL8,
    GL_DEPTH_STENCIL_ATTACHMENT,
    GL_RENDERBUFFER,
    GL_FRAMEBUFFER,
    GL_FRAMEBUFFER_COMPLETE,
    GL_NEAREST,
    GL_RGBA,
    GL_RGBA8,
    GL_TEXTURE_2D,
    GL_TEXTURE_MAG_FILTER,
    GL_TEXTURE_MIN_FILTER,
    GL_TEXTURE_WRAP_S,
    GL_TEXTURE_WRAP_T,
    GL_UNSIGNED_BYTE,
    _UInts,
)
from ._gl_backend import _delete_object


struct _GLTarget(Movable):
    """A texture plus the framebuffer object that renders into it.

    Owns the `GL` it was built with, so teardown — unbind, then delete the
    framebuffer and the texture — can run from `__deinit__` with no
    parameters to pass one in. The context that `gl` was resolved against
    must still be current when `_GLTarget` is destroyed (FFI rule 3 in
    `_gl.mojo`), same as everywhere else a `GL` is torn down.
    """

    var gl: GL
    var color: UInt32
    var stencil: UInt32
    """Depth and stencil in one renderbuffer, as a window's default
    framebuffer has them: `canvas.clip` needs the stencil."""
    var fbo: UInt32
    var width: Int
    var height: Int

    def __init__(out self, var gl: GL, width: Int, height: Int) raises:
        var names = List[UInt32](length=1, fill=0)
        gl.gen_textures(1, _UInts(unsafe_from_address=Int(names.unsafe_ptr())))
        var color = names[0]
        gl.bind_texture(GL_TEXTURE_2D, color)
        var blank = List[UInt8](length=width * height * 4, fill=0)
        gl.tex_image_2d(
            GL_TEXTURE_2D,
            0,
            GL_RGBA8,
            Int32(width),
            Int32(height),
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            Int(blank.unsafe_ptr()),
        )
        _ = blank^
        gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        gl.tex_parameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

        gl.gen_framebuffers(
            1, _UInts(unsafe_from_address=Int(names.unsafe_ptr()))
        )
        var fbo = names[0]
        gl.bind_framebuffer(GL_FRAMEBUFFER, fbo)
        gl.framebuffer_texture_2d(
            GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color, 0
        )
        gl.gen_renderbuffers(
            1, _UInts(unsafe_from_address=Int(names.unsafe_ptr()))
        )
        var stencil = names[0]
        gl.bind_renderbuffer(GL_RENDERBUFFER, stencil)
        gl.renderbuffer_storage(
            GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, Int32(width), Int32(height)
        )
        gl.framebuffer_renderbuffer(
            GL_FRAMEBUFFER,
            GL_DEPTH_STENCIL_ATTACHMENT,
            GL_RENDERBUFFER,
            stencil,
        )
        if (
            gl.check_framebuffer_status(GL_FRAMEBUFFER)
            != GL_FRAMEBUFFER_COMPLETE
        ):
            raise Error("the offscreen framebuffer is incomplete")

        self.gl = gl^
        self.color = color
        self.stencil = stencil
        self.fbo = fbo
        self.width = width
        self.height = height

    def __deinit__(deinit self):
        self.gl.bind_framebuffer(GL_FRAMEBUFFER, 0)
        _delete_object(self.gl.delete_framebuffers, self.fbo)
        _delete_object(self.gl.delete_renderbuffers, self.stencil)
        _delete_object(self.gl.delete_textures, self.color)
