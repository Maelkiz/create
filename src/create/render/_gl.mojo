"""OpenGL 3.3 entry points, resolved once and checked once.

`render` must not import `window` (see AGENTS.md), so this module cannot take
a `GLWindow` and cannot use its `get_proc_address`. It opens SDL itself and
calls `SDL_GL_GetProcAddress` — `dlopen` refcounts, so a second handle
alongside `_window`'s is harmless, and SDL's loader is used rather than
plain `dlsym` because extension entry points are not guaranteed to be in the
process's symbol table.

**A GL context must already be current when `GL()` is constructed.** On most
drivers `SDL_GL_GetProcAddress` returns null without one. The GL run loop
guarantees it by creating its `GLWindow` first.

Three FFI lifetime rules are encoded here, and getting any of them wrong
looks like a compiler fault rather than the ordinary mistake it is:

1. **A `String` whose pointer is handed to C must outlive the call.**
   `unsafe_ptr()` erases the origin, so the optimizer may destroy the string
   before the callee reads it; `dlsym` then reads garbage and returns null,
   and calling address 0 segfaults. Hence the `_ = name` in `_proc_address`,
   and the null check that turns a mis-resolved symbol into a named error
   instead of a crash.
2. **Read a C out-parameter back from heap memory, not a local
   `Array`.** The write lands either way, but `MutUntrackedOrigin` gives
   the optimizer no aliasing information, so a read from a local array can be
   served stale from a register. Use a `List` buffer — as `read_int` does.
3. **Keep the GL context owner alive past the last GL call.** Destroying a
   `GLWindow` tears down the context and every later GL call segfaults. Not
   this module's problem in a real loop, where the window is alive by
   construction, but it is what makes spikes and tests look signature-
   dependent.
"""

from std.ffi import _DLHandle
from std.sys.info import CompilationTarget


# ---------------------------------------------------------------- constants

comptime GL_FALSE: UInt8 = 0
comptime GL_TRUE: UInt8 = 1

comptime GL_NO_ERROR: UInt32 = 0
comptime GL_VERSION: UInt32 = 0x1F02
comptime GL_MAJOR_VERSION: UInt32 = 0x821B
comptime GL_MINOR_VERSION: UInt32 = 0x821C

comptime GL_COLOR_BUFFER_BIT: UInt32 = 0x00004000

comptime GL_BLEND: UInt32 = 0x0BE2
comptime GL_MULTISAMPLE: UInt32 = 0x809D
comptime GL_ZERO: UInt32 = 0
comptime GL_ONE: UInt32 = 1
comptime GL_SRC_ALPHA: UInt32 = 0x0302
comptime GL_ONE_MINUS_SRC_ALPHA: UInt32 = 0x0303
comptime GL_DST_COLOR: UInt32 = 0x0306
comptime GL_ONE_MINUS_DST_COLOR: UInt32 = 0x0307
comptime GL_FUNC_ADD: UInt32 = 0x8006
comptime GL_FUNC_REVERSE_SUBTRACT: UInt32 = 0x800B

comptime GL_ARRAY_BUFFER: UInt32 = 0x8892
comptime GL_STREAM_DRAW: UInt32 = 0x88E0

comptime GL_FLOAT: UInt32 = 0x1406
comptime GL_UNSIGNED_BYTE: UInt32 = 0x1401
comptime GL_TRIANGLES: UInt32 = 0x0004

comptime GL_VERTEX_SHADER: UInt32 = 0x8B31
comptime GL_FRAGMENT_SHADER: UInt32 = 0x8B30
comptime GL_COMPILE_STATUS: UInt32 = 0x8B81
comptime GL_LINK_STATUS: UInt32 = 0x8B82
comptime GL_INFO_LOG_LENGTH: UInt32 = 0x8B84

comptime GL_TEXTURE_2D: UInt32 = 0x0DE1
comptime GL_TEXTURE0: UInt32 = 0x84C0
comptime GL_TEXTURE1: UInt32 = 0x84C1
comptime GL_RGBA: UInt32 = 0x1908
comptime GL_RGBA8: Int32 = 0x8058
comptime GL_RED: UInt32 = 0x1903
comptime GL_R8: Int32 = 0x8229
comptime GL_TEXTURE_MIN_FILTER: UInt32 = 0x2801
comptime GL_TEXTURE_MAG_FILTER: UInt32 = 0x2800
comptime GL_TEXTURE_WRAP_S: UInt32 = 0x2802
comptime GL_TEXTURE_WRAP_T: UInt32 = 0x2803
comptime GL_LINEAR: Int32 = 0x2601
comptime GL_NEAREST: Int32 = 0x2600
comptime GL_CLAMP_TO_EDGE: Int32 = 0x812F
comptime GL_FRAMEBUFFER: UInt32 = 0x8D40
comptime GL_COLOR_ATTACHMENT0: UInt32 = 0x8CE0
comptime GL_FRAMEBUFFER_COMPLETE: UInt32 = 0x8CD5
comptime GL_PACK_ALIGNMENT: UInt32 = 0x0D05
comptime GL_UNPACK_ALIGNMENT: UInt32 = 0x0CF5


# ------------------------------------------------------------ pointer types

comptime _Bytes = Pointer[UInt8, MutUntrackedOrigin]
"""An untyped C buffer — GL's `void *`, and its `GLchar *` too."""

comptime _Ints = Pointer[Int32, MutUntrackedOrigin]
"""`GLint *` / `GLsizei *` — out-parameters, read back per rule 2."""

comptime _UInts = Pointer[UInt32, MutUntrackedOrigin]
"""`GLuint *` — the object-name out-parameters of the `glGen*` calls."""

comptime _Strings = Pointer[_Bytes, MutUntrackedOrigin]
"""`const GLchar * const *` — `glShaderSource`'s array of source strings."""

comptime _Address = Int
"""A C pointer argument GL is allowed to pass nothing for.

Mojo's `Pointer` is non-nullable by construction, so a parameter that GL
documents as nullable — `glBufferData`'s data, `glShaderSource`'s lengths —
or as a byte offset into the bound buffer rather than an address at all —
`glVertexAttribPointer`'s pointer — travels as a pointer-width integer. Same
ABI, and `0` means what C means by `NULL`."""


# ---------------------------------------------------- entry-point signatures

comptime _GetString = def(UInt32) thin abi("C") -> _Bytes
comptime _GetError = def() thin abi("C") -> UInt32
comptime _GetIntegerv = def(UInt32, _Ints) thin abi("C") -> None
comptime _Viewport = def(Int32, Int32, Int32, Int32) thin abi("C") -> None
comptime _ClearColor = def(Float32, Float32, Float32, Float32) thin abi(
    "C"
) -> None
comptime _Clear = def(UInt32) thin abi("C") -> None
comptime _Enable = def(UInt32) thin abi("C") -> None
comptime _BlendFunc = def(UInt32, UInt32) thin abi("C") -> None
comptime _BlendFuncSeparate = def(UInt32, UInt32, UInt32, UInt32) thin abi(
    "C"
) -> None
comptime _BlendEquationSeparate = def(UInt32, UInt32) thin abi("C") -> None

comptime _GenObjects = def(Int32, _UInts) thin abi("C") -> None
comptime _DeleteObjects = def(Int32, _UInts) thin abi("C") -> None
comptime _BindBuffer = def(UInt32, UInt32) thin abi("C") -> None
comptime _BufferData = def(UInt32, Int64, _Address, UInt32) thin abi(
    "C"
) -> None
comptime _BindVertexArray = def(UInt32) thin abi("C") -> None
comptime _VertexAttribPointer = def(
    UInt32, Int32, UInt32, UInt8, Int32, _Address
) thin abi("C") -> None
comptime _EnableVertexAttribArray = def(UInt32) thin abi("C") -> None

comptime _CreateShader = def(UInt32) thin abi("C") -> UInt32
comptime _ShaderSource = def(UInt32, Int32, _Strings, _Address) thin abi(
    "C"
) -> None
comptime _CompileShader = def(UInt32) thin abi("C") -> None
comptime _GetShaderiv = def(UInt32, UInt32, _Ints) thin abi("C") -> None
comptime _GetInfoLog = def(UInt32, Int32, _Address, _Bytes) thin abi(
    "C"
) -> None
comptime _CreateProgram = def() thin abi("C") -> UInt32
comptime _AttachShader = def(UInt32, UInt32) thin abi("C") -> None
comptime _LinkProgram = def(UInt32) thin abi("C") -> None
comptime _GetProgramiv = def(UInt32, UInt32, _Ints) thin abi("C") -> None
comptime _UseProgram = def(UInt32) thin abi("C") -> None
comptime _DeleteShader = def(UInt32) thin abi("C") -> None
comptime _DeleteProgram = def(UInt32) thin abi("C") -> None

comptime _GetUniformLocation = def(UInt32, _Bytes) thin abi("C") -> Int32
comptime _Uniform2f = def(Int32, Float32, Float32) thin abi("C") -> None
comptime _Uniform1i = def(Int32, Int32) thin abi("C") -> None

comptime _BindTexture = def(UInt32, UInt32) thin abi("C") -> None
comptime _TexImage2D = def(
    UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, _Address
) thin abi("C") -> None
comptime _TexSubImage2D = def(
    UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, _Bytes
) thin abi("C") -> None
comptime _TexParameteri = def(UInt32, UInt32, Int32) thin abi("C") -> None
comptime _ActiveTexture = def(UInt32) thin abi("C") -> None
comptime _PixelStorei = def(UInt32, Int32) thin abi("C") -> None

comptime _DrawArrays = def(UInt32, Int32, Int32) thin abi("C") -> None
comptime _GenFramebuffers = def(Int32, _UInts) thin abi("C") -> None
comptime _BindFramebuffer = def(UInt32, UInt32) thin abi("C") -> None
comptime _DeleteFramebuffers = def(Int32, _UInts) thin abi("C") -> None
comptime _FramebufferTexture2D = def(
    UInt32, UInt32, UInt32, UInt32, Int32
) thin abi("C") -> None
comptime _CheckFramebufferStatus = def(UInt32) thin abi("C") -> UInt32
comptime _ReadPixels = def(
    Int32, Int32, Int32, Int32, UInt32, UInt32, _Bytes
) thin abi("C") -> None


# ------------------------------------------------------------------ loading


def _sdl() raises -> _DLHandle:
    """SDL3, for its GL loader alone. Refcounted, so this handle is additive."""
    comptime if CompilationTarget.is_macos():
        return _DLHandle("libSDL3.dylib")
    else:
        return _DLHandle("libSDL3.so")


def _proc_address(lib: _DLHandle, name: String) raises -> Int:
    """Resolve one GL entry point, raising rather than returning null.

    `_ = name` is rule 1: without it the string may be destroyed before SDL
    reads it, and the null that comes back is indistinguishable from a symbol
    the driver genuinely lacks.

    A null here means no context is current, or a loader that reports absence
    honestly. It does **not** mean much on the other side: glX hands back a
    non-null stub for a name it has never heard of — verified on NVIDIA, where
    `"glNoSuchEntryPoint"` resolves — so this check cannot be what proves the
    entry points exist. `GL.__init__`'s version gate is what does that.
    """
    var addr = lib.call["SDL_GL_GetProcAddress", Int](name.unsafe_ptr())
    _ = name
    if addr == 0:
        raise Error(
            "GL function not available: " + name + " — is a GL context current?"
        )
    return addr


def _bind[T: TrivialRegisterPassable](lib: _DLHandle, name: String) raises -> T:
    """The resolved address, bitcast to its C-ABI function-pointer type."""
    var opaque = Pointer[NoneType, MutUntrackedOrigin](
        unsafe_from_address=_proc_address(lib, name)
    )
    return Pointer(to=opaque).unsafe_bitcast[T]()[]


struct GL(Movable):
    """Every GL entry point this backend uses, bound at construction.

    Binding eagerly, then checking the context version, means an inadequate
    driver fails once — here, with a version number in the message — rather
    than as a segfault at the first call, thousands of frames into a program.
    Every symbol in this table is core GL 3.3, so the version *is* the check:
    resolving each name proves nothing on its own, because glX stubs unknown
    names (see `_proc_address`).
    """

    var _lib: _DLHandle
    """SDL, kept alive for the life of the table. The GL pointers outlive
    their loader, but holding it costs nothing and removes the question."""

    var get_string: _GetString
    var get_error: _GetError
    var get_integerv: _GetIntegerv
    var viewport: _Viewport
    var clear_color: _ClearColor
    var clear: _Clear
    var enable: _Enable
    var disable: _Enable
    var blend_func: _BlendFunc
    var blend_func_separate: _BlendFuncSeparate
    var blend_equation_separate: _BlendEquationSeparate

    var gen_buffers: _GenObjects
    var bind_buffer: _BindBuffer
    var buffer_data: _BufferData
    var gen_vertex_arrays: _GenObjects
    var bind_vertex_array: _BindVertexArray
    var vertex_attrib_pointer: _VertexAttribPointer
    var enable_vertex_attrib_array: _EnableVertexAttribArray

    var create_shader: _CreateShader
    var shader_source: _ShaderSource
    var compile_shader: _CompileShader
    var get_shaderiv: _GetShaderiv
    var get_shader_info_log: _GetInfoLog
    var create_program: _CreateProgram
    var attach_shader: _AttachShader
    var link_program: _LinkProgram
    var get_programiv: _GetProgramiv
    var get_program_info_log: _GetInfoLog
    var use_program: _UseProgram
    var delete_shader: _DeleteShader
    var delete_program: _DeleteProgram

    var get_uniform_location: _GetUniformLocation
    var uniform_2f: _Uniform2f
    var uniform_1i: _Uniform1i

    var gen_textures: _GenObjects
    var bind_texture: _BindTexture
    var tex_image_2d: _TexImage2D
    var tex_sub_image_2d: _TexSubImage2D
    var tex_parameteri: _TexParameteri
    var active_texture: _ActiveTexture
    var pixel_storei: _PixelStorei

    var draw_arrays: _DrawArrays
    var gen_framebuffers: _GenFramebuffers
    var bind_framebuffer: _BindFramebuffer
    var delete_framebuffers: _DeleteFramebuffers
    var framebuffer_texture_2d: _FramebufferTexture2D
    var check_framebuffer_status: _CheckFramebufferStatus
    var read_pixels: _ReadPixels
    """Framebuffer objects and readback. No frame uses either — they exist
    for `tests/render/test_gl_parity.mojo`, which needs to render at an exact
    pixel size the window manager cannot veto, and to see what the GPU drew.
    """

    var delete_buffers: _DeleteObjects
    var delete_vertex_arrays: _DeleteObjects
    var delete_textures: _DeleteObjects

    def __init__(out self) raises:
        """Bind every entry point, then require a GL 3.3 or better context."""
        var lib = _sdl()
        self.get_string = _bind[_GetString](lib, "glGetString")
        self.get_error = _bind[_GetError](lib, "glGetError")
        self.get_integerv = _bind[_GetIntegerv](lib, "glGetIntegerv")
        self.viewport = _bind[_Viewport](lib, "glViewport")
        self.clear_color = _bind[_ClearColor](lib, "glClearColor")
        self.clear = _bind[_Clear](lib, "glClear")
        self.enable = _bind[_Enable](lib, "glEnable")
        self.disable = _bind[_Enable](lib, "glDisable")
        self.blend_func = _bind[_BlendFunc](lib, "glBlendFunc")
        self.blend_func_separate = _bind[_BlendFuncSeparate](
            lib, "glBlendFuncSeparate"
        )
        self.blend_equation_separate = _bind[_BlendEquationSeparate](
            lib, "glBlendEquationSeparate"
        )

        self.gen_buffers = _bind[_GenObjects](lib, "glGenBuffers")
        self.bind_buffer = _bind[_BindBuffer](lib, "glBindBuffer")
        self.buffer_data = _bind[_BufferData](lib, "glBufferData")
        self.gen_vertex_arrays = _bind[_GenObjects](lib, "glGenVertexArrays")
        self.bind_vertex_array = _bind[_BindVertexArray](
            lib, "glBindVertexArray"
        )
        self.vertex_attrib_pointer = _bind[_VertexAttribPointer](
            lib, "glVertexAttribPointer"
        )
        self.enable_vertex_attrib_array = _bind[_EnableVertexAttribArray](
            lib, "glEnableVertexAttribArray"
        )

        self.create_shader = _bind[_CreateShader](lib, "glCreateShader")
        self.shader_source = _bind[_ShaderSource](lib, "glShaderSource")
        self.compile_shader = _bind[_CompileShader](lib, "glCompileShader")
        self.get_shaderiv = _bind[_GetShaderiv](lib, "glGetShaderiv")
        self.get_shader_info_log = _bind[_GetInfoLog](lib, "glGetShaderInfoLog")
        self.create_program = _bind[_CreateProgram](lib, "glCreateProgram")
        self.attach_shader = _bind[_AttachShader](lib, "glAttachShader")
        self.link_program = _bind[_LinkProgram](lib, "glLinkProgram")
        self.get_programiv = _bind[_GetProgramiv](lib, "glGetProgramiv")
        self.get_program_info_log = _bind[_GetInfoLog](
            lib, "glGetProgramInfoLog"
        )
        self.use_program = _bind[_UseProgram](lib, "glUseProgram")
        self.delete_shader = _bind[_DeleteShader](lib, "glDeleteShader")
        self.delete_program = _bind[_DeleteProgram](lib, "glDeleteProgram")

        self.get_uniform_location = _bind[_GetUniformLocation](
            lib, "glGetUniformLocation"
        )
        self.uniform_2f = _bind[_Uniform2f](lib, "glUniform2f")
        self.uniform_1i = _bind[_Uniform1i](lib, "glUniform1i")

        self.gen_textures = _bind[_GenObjects](lib, "glGenTextures")
        self.bind_texture = _bind[_BindTexture](lib, "glBindTexture")
        self.tex_image_2d = _bind[_TexImage2D](lib, "glTexImage2D")
        self.tex_sub_image_2d = _bind[_TexSubImage2D](lib, "glTexSubImage2D")
        self.tex_parameteri = _bind[_TexParameteri](lib, "glTexParameteri")
        self.active_texture = _bind[_ActiveTexture](lib, "glActiveTexture")
        self.pixel_storei = _bind[_PixelStorei](lib, "glPixelStorei")

        self.draw_arrays = _bind[_DrawArrays](lib, "glDrawArrays")
        self.gen_framebuffers = _bind[_GenFramebuffers](
            lib, "glGenFramebuffers"
        )
        self.bind_framebuffer = _bind[_BindFramebuffer](
            lib, "glBindFramebuffer"
        )
        self.delete_framebuffers = _bind[_DeleteFramebuffers](
            lib, "glDeleteFramebuffers"
        )
        self.framebuffer_texture_2d = _bind[_FramebufferTexture2D](
            lib, "glFramebufferTexture2D"
        )
        self.check_framebuffer_status = _bind[_CheckFramebufferStatus](
            lib, "glCheckFramebufferStatus"
        )
        self.read_pixels = _bind[_ReadPixels](lib, "glReadPixels")

        self.delete_buffers = _bind[_DeleteObjects](lib, "glDeleteBuffers")
        self.delete_vertex_arrays = _bind[_DeleteObjects](
            lib, "glDeleteVertexArrays"
        )
        self.delete_textures = _bind[_DeleteObjects](lib, "glDeleteTextures")

        self._lib = lib^

        var major = self.read_int(GL_MAJOR_VERSION)
        var minor = self.read_int(GL_MINOR_VERSION)
        if major < 3 or (major == 3 and minor < 3):
            raise Error(
                "OpenGL 3.3 or better required, got "
                + String(major)
                + "."
                + String(minor)
                + " ("
                + self.version()
                + ")"
            )

    def version(self) -> String:
        """`GL_VERSION` as reported by the driver."""
        return String(unsafe_from_utf8_ptr=self.get_string(GL_VERSION))

    def read_int(self, name: UInt32) -> Int:
        """One `glGetIntegerv` value, read back through heap memory.

        Rule 2: a local `Array` here can read stale, because
        `MutUntrackedOrigin` tells the optimizer nothing about the write.
        """
        var buf = List[Int32](length=1, fill=-1)
        self.get_integerv(
            name, _Ints(unsafe_from_address=Int(buf.unsafe_ptr()))
        )
        return Int(buf[0])

    def check(self, site: String) raises:
        """Raise if GL flagged an error since the last check.

        Debug scaffolding, not a hot-path call: `glGetError` forces a
        round-trip to the driver, so this belongs at frame boundaries and in
        tests, never inside a batch loop.
        """
        var code = self.get_error()
        if code != GL_NO_ERROR:
            raise Error("GL error 0x" + hex(code) + " at " + site)
