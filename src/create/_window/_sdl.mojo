"""Raw SDL3 bindings via `std.ffi._DLHandle`.

Internal only — nothing here is re-exported from the package `__init__`.
`_DLHandle` is a private stdlib API (no public `DLHandle` exists in this
Mojo release); isolating all use of it in this one file means a future
stdlib rename only touches this module.

`_DLHandle.call` requires its `return_type` to be `RegisterPassable`, which
rules out returning pointer types directly. SDL handles (`SDL_Window *`)
and pointer results we don't need to dereference are therefore treated as
opaque `Int` addresses. Where we do need to read through a pointer (error
strings), `Pointer[T, MutUntrackedOrigin]` is used — `MutUntrackedOrigin`
is the concrete origin the stdlib itself uses for FFI-returned pointers.

Every handle kind (window, renderer, texture, GL context) is this same
opaque `Int` — nothing here stops passing a texture handle where a
renderer handle is expected; the compiler can't catch a mixup. Distinct
nominal wrapper types per handle kind would close that gap, at the cost of
touching every `SDL` method signature plus both `Window` and `GLWindow`.
Deliberately deferred: real gap, but a compile-time-safety nicety rather
than a correctness bug, so not worth the refactor churn until something
actually trips over it.
"""

from std.ffi import _DLHandle
from std.sys.info import CompilationTarget

comptime _SDL_ABI_MAJOR_VERSION: Int32 = 3
"""Major version this file's `SDL_Event` byte offsets were verified
against (concretely 3.4.14, conda-forge) -- checked at runtime in
`SDL.__init__` via `SDL_GetVersion`. SDL's own versioning policy
guarantees ABI/API stability across the whole 3.x line, so this only
guards against an unexpected major bump (e.g. a future SDL4 conda
package satisfying `pixi.toml`'s `sdl3` dependency name), not against
the minor/patch range moving."""

comptime SDL_INIT_VIDEO: UInt32 = 0x00000020
comptime SDL_WINDOW_FULLSCREEN: UInt64 = 0x0000000000000001
comptime SDL_WINDOW_BORDERLESS: UInt64 = 0x0000000000000010
comptime SDL_WINDOW_RESIZABLE: UInt64 = 0x0000000000000020
comptime SDL_WINDOW_MAXIMIZED: UInt64 = 0x0000000000000080
comptime SDL_WINDOW_OPENGL: UInt64 = 0x0000000000000002

# SDL_GLAttr enum values (positional, per SDL_video.h).
comptime SDL_GL_DOUBLEBUFFER: Int32 = 5
comptime SDL_GL_DEPTH_SIZE: Int32 = 6
comptime SDL_GL_STENCIL_SIZE: Int32 = 7
comptime SDL_GL_MULTISAMPLEBUFFERS: Int32 = 13
comptime SDL_GL_MULTISAMPLESAMPLES: Int32 = 14
comptime SDL_GL_CONTEXT_MAJOR_VERSION: Int32 = 17
comptime SDL_GL_CONTEXT_MINOR_VERSION: Int32 = 18
comptime SDL_GL_CONTEXT_PROFILE_MASK: Int32 = 20

comptime SDL_GL_CONTEXT_PROFILE_CORE: Int32 = 0x0001

comptime SDL_EVENT_QUIT: UInt32 = 0x100
comptime SDL_EVENT_WINDOW_RESIZED: UInt32 = 0x206
comptime SDL_EVENT_KEY_DOWN: UInt32 = 0x300
comptime SDL_EVENT_KEY_UP: UInt32 = 0x301
comptime SDL_EVENT_MOUSE_MOTION: UInt32 = 0x400
comptime SDL_EVENT_MOUSE_BUTTON_DOWN: UInt32 = 0x401
comptime SDL_EVENT_MOUSE_BUTTON_UP: UInt32 = 0x402
comptime SDL_EVENT_MOUSE_WHEEL: UInt32 = 0x403

comptime SDL_EVENT_SIZE = 128
"""Size in bytes of SDL_Event — the union is padded to this size for ABI stability."""

comptime SDL_PIXELFORMAT_RGBA32: UInt32 = 0x16762004
"""`SDL_PIXELFORMAT_ABGR8888` on little-endian (the only platform this
package targets — see `pixi.toml`'s `platforms`); SDL defines
`SDL_PIXELFORMAT_RGBA32` as a byte-order-dependent alias, so this is the
concrete value, not the byte-order-generic macro."""

comptime SDL_TEXTUREACCESS_STREAMING: Int32 = 1

# Byte offsets into an SDL_Event buffer, shared by every event struct
# variant (SDL_CommonEvent header: type@0, reserved@4, timestamp@8).
comptime _OFF_WINDOW_ID = 16
comptime _OFF_WINDOW_DATA1 = 20
comptime _OFF_WINDOW_DATA2 = 24

comptime _OFF_KEY_SCANCODE = 24
comptime _OFF_KEY_KEYCODE = 28
comptime _OFF_KEY_MOD = 32
comptime _OFF_KEY_REPEAT = 37

comptime _OFF_MOTION_X = 28
comptime _OFF_MOTION_Y = 32

comptime _OFF_BUTTON_INDEX = 24
comptime _OFF_BUTTON_X = 28
comptime _OFF_BUTTON_Y = 32

comptime _OFF_WHEEL_X = 24
comptime _OFF_WHEEL_Y = 28


struct SDL:
    """Thin wrapper over the dynamically-loaded SDL3 library."""

    var lib: _DLHandle

    def __init__(out self) raises:
        comptime if CompilationTarget.is_macos():
            self.lib = _DLHandle("libSDL3.dylib")
        else:
            self.lib = _DLHandle("libSDL3.so")
        var major = self.get_version() // 1000000
        if major != _SDL_ABI_MAJOR_VERSION:
            raise Error(
                "linked SDL3 major version "
                + String(major)
                + ", expected "
                + String(_SDL_ABI_MAJOR_VERSION)
                + " -- SDL_Event field offsets in _sdl.mojo were verified"
                + " against 3.4.14 and are not safe to use against a"
                + " different major version"
            )

    def get_version(self) raises -> Int32:
        """Linked SDL3 library version, encoded as
        `major*1000000 + minor*1000 + micro` (SDL's own `SDL_VERSIONNUM`
        convention). Safe to call before `init_video()`.
        """
        return self.lib.call["SDL_GetVersion", Int32]()

    def get_error(self) raises -> String:
        var ptr = self.lib.call[
            "SDL_GetError", Pointer[UInt8, MutUntrackedOrigin]
        ]()
        return String(unsafe_from_utf8_ptr=ptr)

    def init_video(self) raises:
        if not self.lib.call["SDL_Init", Bool](SDL_INIT_VIDEO):
            raise Error("SDL_Init(SDL_INIT_VIDEO) failed: " + self.get_error())

    def quit(self) raises:
        self.lib.call["SDL_Quit"]()

    def quit_video(self) raises:
        """Decrement the video subsystem's SDL-internal ref count.

        SDL_Init/SDL_InitSubSystem ref-count each subsystem internally; the
        subsystem only actually shuts down once every matching
        SDL_QuitSubSystem call has landed. `Window` relies on this instead
        of tracking its own live-window count (which this Mojo release has
        no global mutable state to hold outside a function body).
        """
        self.lib.call["SDL_QuitSubSystem"](SDL_INIT_VIDEO)

    def create_window(
        self,
        title: String,
        width: Int32,
        height: Int32,
        resizable: Bool,
        opengl: Bool = False,
        fullscreen: Bool = False,
        borderless: Bool = False,
        maximized: Bool = False,
    ) raises -> Int:
        var flags: UInt64 = 0
        if resizable:
            flags |= SDL_WINDOW_RESIZABLE
        if opengl:
            flags |= SDL_WINDOW_OPENGL
        if fullscreen:
            flags |= SDL_WINDOW_FULLSCREEN
        if borderless:
            flags |= SDL_WINDOW_BORDERLESS
        if maximized:
            flags |= SDL_WINDOW_MAXIMIZED
        var window = self.lib.call["SDL_CreateWindow", Int](
            title.unsafe_ptr(), width, height, flags
        )
        if window == 0:
            raise Error("SDL_CreateWindow failed: " + self.get_error())
        return window

    def destroy_window(self, window: Int) raises:
        self.lib.call["SDL_DestroyWindow"](window)

    def poll_event(self, buf: Pointer[UInt8, _]) raises -> Bool:
        return self.lib.call["SDL_PollEvent", Bool](buf)

    def push_event(self, buf: Pointer[UInt8, _]) raises -> Bool:
        """Queues a caller-built `SDL_Event` buffer for the next `poll_event`.

        Test-only entry point (used by `tests/test_event_translation.mojo`
        to exercise the real poll -> translate path instead of just the
        offset readers) — not used by `Window` itself.
        """
        return self.lib.call["SDL_PushEvent", Bool](buf)

    def get_ticks(self) raises -> UInt64:
        return self.lib.call["SDL_GetTicks", UInt64]()

    def get_window_size(self, window: Int) raises -> Tuple[Int, Int]:
        var w = List[Int32](length=1, fill=0)
        var h = List[Int32](length=1, fill=0)
        self.lib.call["SDL_GetWindowSize"](
            window, w.unsafe_ptr(), h.unsafe_ptr()
        )
        return Int(w[0]), Int(h[0])

    def get_window_size_in_pixels(self, window: Int) raises -> Tuple[Int, Int]:
        """Drawable size in pixels -- differs from `get_window_size` under
        display scaling (HiDPI, Wayland fractional scale), where the window's
        logical size and its backing pixel size are not the same number."""
        var w = List[Int32](length=1, fill=0)
        var h = List[Int32](length=1, fill=0)
        self.lib.call["SDL_GetWindowSizeInPixels"](
            window, w.unsafe_ptr(), h.unsafe_ptr()
        )
        return Int(w[0]), Int(h[0])

    def create_renderer(self, window: Int) raises -> Int:
        # `name=0` (NULL) lets SDL auto-select the best available driver,
        # same as any normal app would get.
        var renderer = self.lib.call["SDL_CreateRenderer", Int](window, Int(0))
        if renderer == 0:
            raise Error("SDL_CreateRenderer failed: " + self.get_error())
        return renderer

    def destroy_renderer(self, renderer: Int) raises:
        self.lib.call["SDL_DestroyRenderer"](renderer)

    def create_texture(
        self, renderer: Int, width: Int32, height: Int32
    ) raises -> Int:
        var texture = self.lib.call["SDL_CreateTexture", Int](
            renderer,
            SDL_PIXELFORMAT_RGBA32,
            SDL_TEXTUREACCESS_STREAMING,
            width,
            height,
        )
        if texture == 0:
            raise Error("SDL_CreateTexture failed: " + self.get_error())
        return texture

    def destroy_texture(self, texture: Int) raises:
        self.lib.call["SDL_DestroyTexture"](texture)

    def update_texture(
        self, texture: Int, pixels: Pointer[UInt8, _], pitch: Int32
    ) raises:
        # `rect=0` (NULL) updates the whole texture.
        if not self.lib.call["SDL_UpdateTexture", Bool](
            texture, Int(0), pixels, pitch
        ):
            raise Error("SDL_UpdateTexture failed: " + self.get_error())

    def render_texture(self, renderer: Int, texture: Int) raises:
        # `srcrect=0, dstrect=0` (NULL) draws the whole texture, stretched
        # to fill the whole render target.
        if not self.lib.call["SDL_RenderTexture", Bool](
            renderer, texture, Int(0), Int(0)
        ):
            raise Error("SDL_RenderTexture failed: " + self.get_error())

    def render_present(self, renderer: Int) raises:
        if not self.lib.call["SDL_RenderPresent", Bool](renderer):
            raise Error("SDL_RenderPresent failed: " + self.get_error())

    def set_render_vsync(self, renderer: Int, enabled: Bool) raises:
        var vsync: Int32 = 1 if enabled else 0
        if not self.lib.call["SDL_SetRenderVSync", Bool](renderer, vsync):
            raise Error("SDL_SetRenderVSync failed: " + self.get_error())

    def set_window_fullscreen(self, window: Int, enabled: Bool) raises:
        if not self.lib.call["SDL_SetWindowFullscreen", Bool](window, enabled):
            raise Error("SDL_SetWindowFullscreen failed: " + self.get_error())

    def gl_set_attribute(self, attr: Int32, value: Int32) raises:
        if not self.lib.call["SDL_GL_SetAttribute", Bool](attr, value):
            raise Error("SDL_GL_SetAttribute failed: " + self.get_error())

    def gl_create_context(self, window: Int) raises -> Int:
        var context = self.lib.call["SDL_GL_CreateContext", Int](window)
        if context == 0:
            raise Error("SDL_GL_CreateContext failed: " + self.get_error())
        return context

    def gl_make_current(self, window: Int, context: Int) raises:
        if not self.lib.call["SDL_GL_MakeCurrent", Bool](window, context):
            raise Error("SDL_GL_MakeCurrent failed: " + self.get_error())

    def gl_swap_window(self, window: Int) raises:
        if not self.lib.call["SDL_GL_SwapWindow", Bool](window):
            raise Error("SDL_GL_SwapWindow failed: " + self.get_error())

    def gl_destroy_context(self, context: Int) raises:
        self.lib.call["SDL_GL_DestroyContext"](context)

    def gl_set_swap_interval(self, interval: Int) raises:
        if not self.lib.call["SDL_GL_SetSwapInterval", Bool](Int32(interval)):
            raise Error("SDL_GL_SetSwapInterval failed: " + self.get_error())

    def gl_get_proc_address(self, name: String) raises -> Int:
        return self.lib.call["SDL_GL_GetProcAddress", Int](name.unsafe_ptr())


# --- SDL_Event field readers -------------------------------------------
#
# Each takes a pointer to an `SDL_EVENT_SIZE`-byte buffer previously filled
# by `SDL.poll_event` and reads the field at its fixed byte offset. Which
# reader is valid depends on `event_type(buf)` — same layout SDL itself
# uses for the `SDL_Event` union.


def event_type(buf: Pointer[UInt8, _]) -> UInt32:
    return buf.unsafe_bitcast[UInt32]()[]


def window_id(buf: Pointer[UInt8, _]) -> UInt32:
    return buf.unsafe_offset(_OFF_WINDOW_ID).unsafe_bitcast[UInt32]()[]


def window_data1(buf: Pointer[UInt8, _]) -> Int32:
    return buf.unsafe_offset(_OFF_WINDOW_DATA1).unsafe_bitcast[Int32]()[]


def window_data2(buf: Pointer[UInt8, _]) -> Int32:
    return buf.unsafe_offset(_OFF_WINDOW_DATA2).unsafe_bitcast[Int32]()[]


def key_scancode(buf: Pointer[UInt8, _]) -> UInt32:
    return buf.unsafe_offset(_OFF_KEY_SCANCODE).unsafe_bitcast[UInt32]()[]


def key_keycode(buf: Pointer[UInt8, _]) -> UInt32:
    return buf.unsafe_offset(_OFF_KEY_KEYCODE).unsafe_bitcast[UInt32]()[]


def key_mod(buf: Pointer[UInt8, _]) -> UInt16:
    return buf.unsafe_offset(_OFF_KEY_MOD).unsafe_bitcast[UInt16]()[]


def key_repeat(buf: Pointer[UInt8, _]) -> Bool:
    return buf.unsafe_offset(_OFF_KEY_REPEAT).unsafe_bitcast[UInt8]()[] != 0


def mouse_x(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_MOTION_X).unsafe_bitcast[Float32]()[]


def mouse_y(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_MOTION_Y).unsafe_bitcast[Float32]()[]


def button_index(buf: Pointer[UInt8, _]) -> UInt8:
    return buf.unsafe_offset(_OFF_BUTTON_INDEX).unsafe_bitcast[UInt8]()[]


def button_x(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_BUTTON_X).unsafe_bitcast[Float32]()[]


def button_y(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_BUTTON_Y).unsafe_bitcast[Float32]()[]


def wheel_x(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_WHEEL_X).unsafe_bitcast[Float32]()[]


def wheel_y(buf: Pointer[UInt8, _]) -> Float32:
    return buf.unsafe_offset(_OFF_WHEEL_Y).unsafe_bitcast[Float32]()[]
