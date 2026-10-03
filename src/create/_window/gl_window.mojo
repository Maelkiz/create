"""Public `GLWindow` type — a Mojo-facing window with a current OpenGL
context, for consumers doing their own GL rendering. Companion to `Window`
(which provides a CPU pixel-buffer surface instead) -- pick whichever
rendering backend fits; a single process can't usefully mix the two on the
same native window.
"""

from ._sdl import (
    SDL_GL_CONTEXT_MAJOR_VERSION,
    SDL_GL_CONTEXT_MINOR_VERSION,
    SDL_GL_CONTEXT_PROFILE_MASK,
    SDL_GL_CONTEXT_PROFILE_CORE,
    SDL_GL_DOUBLEBUFFER,
    SDL_GL_DEPTH_SIZE,
    SDL_GL_STENCIL_SIZE,
    SDL_GL_MULTISAMPLEBUFFERS,
    SDL_GL_MULTISAMPLESAMPLES,
)
from ._sdl_window import NativeWindow, _SDLWindow
from .event import Event


struct GLWindow(NativeWindow):
    var _native: _SDLWindow
    var _context: Int

    def __init__(
        out self,
        title: String,
        width: Int,
        height: Int,
        major_version: Int = 3,
        minor_version: Int = 3,
        core: Bool = True,
        msaa: Int = 0,
        fullscreen: Bool = False,
        resizable: Bool = True,
        borderless: Bool = False,
        maximized: Bool = False,
    ) raises:
        """`core` requests a core profile (no legacy fixed-function GL); off
        by default it is not restricted, since some drivers reject a profile
        mask they'd otherwise accept unset. `msaa` is the sample count for
        multisampling (0 disables it) -- requested here, but a driver that
        refuses it fails context creation below rather than silently
        degrading; retrying at 0 after a failure is the caller's call, not
        this constructor's. `fullscreen` covers the display and, as with
        `Window`, makes SDL ignore the requested size -- `width()`/`height()`
        report what it actually got. `maximized` opens filling the desktop
        work area, and is subject to the same size substitution."""
        var attributes: List[Tuple[Int32, Int32]] = [
            (SDL_GL_CONTEXT_MAJOR_VERSION, Int32(major_version)),
            (SDL_GL_CONTEXT_MINOR_VERSION, Int32(minor_version)),
            (SDL_GL_DOUBLEBUFFER, Int32(1)),
            (SDL_GL_DEPTH_SIZE, Int32(24)),
            (SDL_GL_STENCIL_SIZE, Int32(8)),
        ]
        if core:
            attributes.append(
                (SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
            )
        if msaa > 0:
            attributes.append((SDL_GL_MULTISAMPLEBUFFERS, Int32(1)))
            attributes.append((SDL_GL_MULTISAMPLESAMPLES, Int32(msaa)))
        # A raise below destroys `_native`, and with it the window.
        self._native = _SDLWindow(
            title,
            width,
            height,
            resizable,
            fullscreen,
            borderless,
            maximized,
            opengl=True,
            gl_attributes=attributes^,
        )
        self._context = self._native.sdl.gl_create_context(self._native.handle)
        try:
            self._native.sdl.gl_make_current(self._native.handle, self._context)
        except e:
            self._native.sdl.gl_destroy_context(self._context)
            raise e

    def __deinit__(deinit self):
        # Before `_native` goes: the context belongs to its window.
        try:
            self._native.sdl.gl_destroy_context(self._context)
        except:
            pass

    def is_open(self) -> Bool:
        return self._native.open

    def close(mut self):
        self._native.open = False

    def ticks(self) raises -> Int:
        return Int(self._native.sdl.get_ticks())

    def width(self) -> Int:
        return self._native.width

    def height(self) -> Int:
        return self._native.height

    def drawable_size(self) raises -> Tuple[Int, Int]:
        """Backing pixel size of the drawable, for `glViewport`.

        Not the same number as `width()`/`height()` under display scaling
        (HiDPI, Wayland fractional scale) -- those track the SDL logical
        window size, which is what resize events report. Query this after
        events are pumped and use it for `glViewport`; using the logical
        size there clips or stretches the rendered frame on a scaled
        display."""
        return self._native.sdl.get_window_size_in_pixels(self._native.handle)

    def make_current(mut self) raises:
        """Re-asserts this window's GL context as the current one.

        The constructor already makes it current; call this only if another
        context (a second `GLWindow`, or a library making its own calls) may
        have changed what's current since."""
        self._native.sdl.gl_make_current(self._native.handle, self._context)

    def get_proc_address(self, name: String) raises -> Int:
        """Address of the GL function `name`, or 0 if unavailable.

        This repo does not know or validate GL function signatures --
        bitcast the address to your own C-ABI function-pointer type to call
        it, e.g.:

        ```mojo
        comptime GLClearFn = def(UInt32) thin abi("C") -> None
        var addr = gl_window.get_proc_address("glClear")
        var opaque = Pointer[NoneType, MutUntrackedOrigin](unsafe_from_address=addr)
        var gl_clear = Pointer(to=opaque).unsafe_bitcast[GLClearFn]()[]
        gl_clear(0x00004000)
        ```
        """
        return self._native.sdl.gl_get_proc_address(name)

    def swap_buffers(mut self) raises:
        """Presents the back buffer -- call once per frame after drawing."""
        self._native.sdl.gl_swap_window(self._native.handle)

    def set_fullscreen(mut self, enabled: Bool) raises:
        """Enter or leave fullscreen after construction.

        The size follows asynchronously on some compositors, so read
        `drawable_size()` each frame rather than caching what this leaves
        behind."""
        self._native.sdl.set_window_fullscreen(self._native.handle, enabled)

    def set_swap_interval(mut self, interval: Int) raises:
        """0 = no vsync, 1 = vsync, -1 = adaptive vsync (if supported).

        Note this is a *global* SDL GL setting (`SDL_GL_SetSwapInterval`
        takes no window/context argument), unlike `Window.set_vsync`.
        """
        self._native.sdl.gl_set_swap_interval(interval)

    def rumble_gamepad(
        self,
        id: Int,
        low_frequency: Float64,
        high_frequency: Float64,
        seconds: Float64,
    ) raises:
        self._native.rumble_gamepad(id, low_frequency, high_frequency, seconds)

    def events(mut self) raises -> List[Event]:
        """A resize updates `width()`/`height()` only -- there is no pixel
        buffer or texture to reallocate for a GL-backed window."""
        return self._native.events()
