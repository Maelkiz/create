from create.color.color import Color


struct PixelBuffer(Movable):
    """Pixels being built one at a time, to become an `Image`.

    The mutable half of an image: `set` writes a pixel, `pixel` reads one
    back, and `Image(buffer^)` takes the pixels over without copying them.
    An `Image` is never changed after that, so this is where an image built
    pixel by pixel is built.

    Image coordinates, as `Image.pixel`: column `x` of row `y`, counted from
    the top-left corner, y down — not the canvas's screen space. Off the
    buffer, reads are transparent and writes do nothing. A new buffer is
    transparent.
    """

    var _data: List[UInt8]
    """RGBA, row-major from the top, 8 bits per channel. `Image` takes it
    over as its own pixels; the decoders fill it straight through its
    pointer."""
    var width: Int
    var height: Int

    def __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        self._data = List[UInt8](length=width * height * 4, fill=0)

    def _take_data(deinit self) -> List[UInt8]:
        """The pixels, consuming the buffer: how `Image` takes them over
        without a copy."""
        return self._data^

    def pixel(self, x: Int, y: Int) -> Color:
        """The pixel in column `x` of row `y`, counted from the top-left
        corner. Outside the buffer it is `Color.TRANSPARENT`."""
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return Color.TRANSPARENT
        var off = (y * self.width + x) * 4
        return Color(
            self._data[off],
            self._data[off + 1],
            self._data[off + 2],
            self._data[off + 3],
        )

    def set(mut self, x: Int, y: Int, color: Color):
        """Replace the pixel in column `x` of row `y`, counted from the
        top-left corner. Outside the buffer it does nothing."""
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        var off = (y * self.width + x) * 4
        self._data[off] = color.r
        self._data[off + 1] = color.g
        self._data[off + 2] = color.b
        self._data[off + 3] = color.a
