"""Public `Window` type — the Mojo-facing wrapper over an SDL3 window."""

from ._sdl_window import NativeWindow, _SDLWindow
from .event import Event

comptime _BYTES_PER_PIXEL = 4


struct Window(NativeWindow):
    var _native: _SDLWindow
    var _width: Int
    """The pixel buffer's size. Follows `_native`'s after every `events()`."""
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
        # A raise below destroys `_native`, and with it the window.
        self._native = _SDLWindow(
            title, width, height, resizable, fullscreen, borderless, maximized
        )
        self._width = self._native.width
        self._height = self._native.height
        self._renderer = self._native.sdl.create_renderer(self._native.handle)
        try:
            self._native.sdl.set_render_vsync(self._renderer, True)
            self._texture = self._native.sdl.create_texture(
                self._renderer, Int32(self._width), Int32(self._height)
            )
        except e:
            self._native.sdl.destroy_renderer(self._renderer)
            raise e
        self._pixels = List[UInt8](
            length=self._width * self._height * _BYTES_PER_PIXEL, fill=0
        )

    def __deinit__(deinit self):
        # Before `_native` goes: the renderer belongs to its window.
        try:
            self._native.sdl.destroy_texture(self._texture)
            self._native.sdl.destroy_renderer(self._renderer)
        except:
            pass

    def is_open(self) -> Bool:
        return self._native.open

    def close(mut self):
        self._native.open = False

    def ticks(self) raises -> Int:
        return Int(self._native.sdl.get_ticks())

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
        self._native.sdl.update_texture(
            self._texture, self._pixels.unsafe_ptr(), pitch
        )
        self._native.sdl.render_texture(self._renderer, self._texture)
        self._native.sdl.render_present(self._renderer)

    def set_vsync(mut self, enabled: Bool) raises:
        self._native.sdl.set_render_vsync(self._renderer, enabled)

    def set_fullscreen(mut self, enabled: Bool) raises:
        self._native.sdl.set_window_fullscreen(self._native.handle, enabled)

    def set_title(mut self, title: String) raises:
        self._native.set_title(title)

    def set_resizable(mut self, enabled: Bool) raises:
        self._native.set_resizable(enabled)

    def set_mode(
        mut self, fullscreen: Bool, borderless: Bool, maximized: Bool
    ) raises:
        self._native.set_mode(fullscreen, borderless, maximized)

    def _resize(mut self, width: Int, height: Int) raises:
        if width == self._width and height == self._height:
            return
        var new_texture = self._native.sdl.create_texture(
            self._renderer, Int32(width), Int32(height)
        )
        self._native.sdl.destroy_texture(self._texture)
        self._texture = new_texture
        self._width = width
        self._height = height
        self._pixels = List[UInt8](
            length=width * height * _BYTES_PER_PIXEL, fill=0
        )

    def rumble_gamepad(
        self,
        id: Int,
        low_frequency: Float64,
        high_frequency: Float64,
        seconds: Float64,
    ) raises:
        self._native.rumble_gamepad(id, low_frequency, high_frequency, seconds)

    def events(mut self) raises -> List[Event]:
        """A resize also reallocates the pixel buffer, once for the frame."""
        var events = self._native.events()
        self._resize(self._native.width, self._native.height)
        return events^
