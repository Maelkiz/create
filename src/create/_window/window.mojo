"""Public `Window` type — the Mojo-facing wrapper over an SDL3 window."""

from ._sdl import (
    SDL,
    SDL_EVENT_SIZE,
    SDL_EVENT_QUIT,
    SDL_EVENT_WINDOW_RESIZED,
    event_type,
    window_data1,
    window_data2,
)
from .event import Event, Quit, Resized, translate_event

comptime _BYTES_PER_PIXEL = 4


struct Window:
    var _sdl: SDL
    var _handle: Int
    var _open: Bool
    var _width: Int
    var _height: Int
    var _renderer: Int
    var _texture: Int
    var _pixels: List[UInt8]

    def __init__(
        out self,
        title: String,
        width: Int,
        height: Int,
        fullscreen: Bool = False,
        resizable: Bool = True,
        borderless: Bool = False,
        maximized: Bool = False,
    ) raises:
        self._sdl = SDL()
        self._sdl.init_video()
        try:
            self._handle = self._sdl.create_window(
                title,
                Int32(width),
                Int32(height),
                resizable,
                fullscreen=fullscreen,
                borderless=borderless,
                maximized=maximized,
            )
        except e:
            self._sdl.quit_video()
            raise e
        self._open = True
        try:
            self._renderer = self._sdl.create_renderer(self._handle)
        except e:
            self._sdl.destroy_window(self._handle)
            self._sdl.quit_video()
            raise e
        # When fullscreen or maximized, SDL ignores the requested size and
        # uses the display or work area — query the real dimensions before
        # creating the texture.
        var actual_width = width
        var actual_height = height
        if fullscreen or maximized:
            try:
                actual_width, actual_height = self._sdl.get_window_size(
                    self._handle
                )
            except e:
                self._sdl.destroy_renderer(self._renderer)
                self._sdl.destroy_window(self._handle)
                self._sdl.quit_video()
                raise e
        self._width = actual_width
        self._height = actual_height
        try:
            self._sdl.set_render_vsync(self._renderer, True)
            self._texture = self._sdl.create_texture(
                self._renderer, Int32(actual_width), Int32(actual_height)
            )
        except e:
            self._sdl.destroy_renderer(self._renderer)
            self._sdl.destroy_window(self._handle)
            self._sdl.quit_video()
            raise e
        self._pixels = List[UInt8](
            length=actual_width * actual_height * _BYTES_PER_PIXEL, fill=0
        )

    def __deinit__(deinit self):
        try:
            self._sdl.destroy_texture(self._texture)
            self._sdl.destroy_renderer(self._renderer)
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

    def pixels(mut self) -> Pointer[UInt8, origin_of(self._pixels)]:
        """Mutable RGBA8 framebuffer, row-major top-down,
        `width() * height() * 4` bytes. Write into it, then call
        `present()` to show it. Reallocated (and cleared) on resize.
        """
        return self._pixels.unsafe_ptr()

    def present(mut self) raises:
        """Uploads the framebuffer and shows it in the window."""
        var pitch = Int32(self._width * _BYTES_PER_PIXEL)
        self._sdl.update_texture(
            self._texture, self._pixels.unsafe_ptr(), pitch
        )
        self._sdl.render_texture(self._renderer, self._texture)
        self._sdl.render_present(self._renderer)

    def set_vsync(mut self, enabled: Bool) raises:
        self._sdl.set_render_vsync(self._renderer, enabled)

    def set_fullscreen(mut self, enabled: Bool) raises:
        self._sdl.set_window_fullscreen(self._handle, enabled)

    def _resize(mut self, width: Int, height: Int) raises:
        if width == self._width and height == self._height:
            return
        var new_texture = self._sdl.create_texture(
            self._renderer, Int32(width), Int32(height)
        )
        self._sdl.destroy_texture(self._texture)
        self._texture = new_texture
        self._width = width
        self._height = height
        self._pixels = List[UInt8](
            length=width * height * _BYTES_PER_PIXEL, fill=0
        )

    def events(mut self) raises -> List[Event]:
        """Drains all pending SDL events for this frame as translated `Event`s.

        A quit event also flips the window to closed.
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
                self._resize(new_width, new_height)
                events.append(Event(Resized(new_width, new_height)))
            else:
                var translated = translate_event(kind, ptr)
                if translated:
                    events.append(translated.value())
        return events^
