"""Public `GLWindow` type — a Mojo-facing window with a current OpenGL
context, for consumers doing their own GL rendering. Companion to `Window`
(which provides a CPU pixel-buffer surface instead) -- pick whichever
rendering backend fits; a single process can't usefully mix the two on the
same native window.
"""

from ._sdl import (
    SDL,
    SDL_EVENT_SIZE,
    SDL_EVENT_QUIT,
    SDL_EVENT_WINDOW_RESIZED,
    SDL_GL_CONTEXT_MAJOR_VERSION,
    SDL_GL_CONTEXT_MINOR_VERSION,
    SDL_GL_CONTEXT_PROFILE_MASK,
    SDL_GL_CONTEXT_PROFILE_CORE,
    SDL_GL_DOUBLEBUFFER,
    SDL_GL_DEPTH_SIZE,
    SDL_GL_STENCIL_SIZE,
    SDL_GL_MULTISAMPLEBUFFERS,
    SDL_GL_MULTISAMPLESAMPLES,
    event_type,
    window_data1,
    window_data2,
)
from .event import Event, Quit, Resized, translate_event


struct GLWindow:
    var _sdl: SDL
    var _handle: Int
    var _context: Int
    var _open: Bool
    var _width: Int
    var _height: Int

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
        self._sdl = SDL()
        self._sdl.init_video()
        try:
            self._sdl.gl_set_attribute(
                SDL_GL_CONTEXT_MAJOR_VERSION, Int32(major_version)
            )
            self._sdl.gl_set_attribute(
                SDL_GL_CONTEXT_MINOR_VERSION, Int32(minor_version)
            )
            if core:
                self._sdl.gl_set_attribute(
                    SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE
                )
            self._sdl.gl_set_attribute(SDL_GL_DOUBLEBUFFER, 1)
            self._sdl.gl_set_attribute(SDL_GL_DEPTH_SIZE, 24)
            self._sdl.gl_set_attribute(SDL_GL_STENCIL_SIZE, 8)
            if msaa > 0:
                self._sdl.gl_set_attribute(SDL_GL_MULTISAMPLEBUFFERS, 1)
                self._sdl.gl_set_attribute(
                    SDL_GL_MULTISAMPLESAMPLES, Int32(msaa)
                )
        except e:
            self._sdl.quit_video()
            raise e
        try:
            self._handle = self._sdl.create_window(
                title,
                Int32(width),
                Int32(height),
                resizable,
                opengl=True,
                fullscreen=fullscreen,
                borderless=borderless,
                maximized=maximized,
            )
        except e:
            self._sdl.quit_video()
            raise e
        try:
            self._context = self._sdl.gl_create_context(self._handle)
        except e:
            self._sdl.destroy_window(self._handle)
            self._sdl.quit_video()
            raise e
        try:
            self._sdl.gl_make_current(self._handle, self._context)
        except e:
            self._sdl.gl_destroy_context(self._context)
            self._sdl.destroy_window(self._handle)
            self._sdl.quit_video()
            raise e
        self._open = True
        # Fullscreen and maximized make SDL ignore the requested size, so the
        # real one has to be queried -- same as `Window`, which needs it to
        # size a texture.
        # Here nothing is allocated from it, but `width()`/`height()` would
        # otherwise report the request until the first resize event.
        self._width = width
        self._height = height
        if fullscreen or maximized:
            try:
                self._width, self._height = self._sdl.get_window_size(
                    self._handle
                )
            except e:
                self._sdl.gl_destroy_context(self._context)
                self._sdl.destroy_window(self._handle)
                self._sdl.quit_video()
                raise e

    def __deinit__(deinit self):
        try:
            self._sdl.gl_destroy_context(self._context)
            self._sdl.destroy_window(self._handle)
            self._sdl.quit_video()
        except:
            pass

    def is_open(self) -> Bool:
        return self._open

    def close(mut self):
        self._open = False

    def ticks(self) raises -> Int:
        """Milliseconds since SDL library init."""
        return Int(self._sdl.get_ticks())

    def width(self) -> Int:
        return self._width

    def height(self) -> Int:
        return self._height

    def drawable_size(self) raises -> Tuple[Int, Int]:
        """Backing pixel size of the drawable, for `glViewport`.

        Not the same number as `width()`/`height()` under display scaling
        (HiDPI, Wayland fractional scale) -- those track the SDL logical
        window size, which is what resize events report. Query this after
        events are pumped and use it for `glViewport`; using the logical
        size there clips or stretches the rendered frame on a scaled
        display."""
        return self._sdl.get_window_size_in_pixels(self._handle)

    def make_current(mut self) raises:
        """Re-asserts this window's GL context as the current one.

        The constructor already makes it current; call this only if another
        context (a second `GLWindow`, or a library making its own calls) may
        have changed what's current since."""
        self._sdl.gl_make_current(self._handle, self._context)

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
        return self._sdl.gl_get_proc_address(name)

    def swap_buffers(mut self) raises:
        """Presents the back buffer -- call once per frame after drawing."""
        self._sdl.gl_swap_window(self._handle)

    def set_fullscreen(mut self, enabled: Bool) raises:
        """Enter or leave fullscreen after construction.

        The size follows asynchronously on some compositors, so read
        `drawable_size()` each frame rather than caching what this leaves
        behind."""
        self._sdl.set_window_fullscreen(self._handle, enabled)

    def set_swap_interval(mut self, interval: Int) raises:
        """0 = no vsync, 1 = vsync, -1 = adaptive vsync (if supported).

        Note this is a *global* SDL GL setting (`SDL_GL_SetSwapInterval`
        takes no window/context argument), unlike `Window.set_vsync`.
        """
        self._sdl.gl_set_swap_interval(interval)

    def events(mut self) raises -> List[Event]:
        """Drains all pending SDL events for this frame as translated `Event`s.

        A quit event also flips the window to closed. A resize event
        updates `width()`/`height()` only -- there is no pixel buffer or
        texture to reallocate for a GL-backed window.
        """
        var events: List[Event] = []
        var buf = Array[UInt8, SDL_EVENT_SIZE](fill=0)
        var ptr = buf.unsafe_ptr()
        while self._sdl.poll_event(ptr):
            var kind = event_type(ptr)
            if kind == SDL_EVENT_QUIT:
                self._open = False
                events.append(Event(Quit()))
            elif kind == SDL_EVENT_WINDOW_RESIZED:
                var new_width = Int(window_data1(ptr))
                var new_height = Int(window_data2(ptr))
                self._width = new_width
                self._height = new_height
                events.append(Event(Resized(new_width, new_height)))
            else:
                var translated = translate_event(kind, ptr)
                if translated:
                    events.append(translated.value())
        return events^
