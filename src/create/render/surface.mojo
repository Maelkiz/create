from std.memory import unsafe_memcpy

from .color import Color
from ._png import write_png


def _force_opaque(mut pixels: List[UInt8]):
    """Set every alpha byte in an RGBA buffer to 255, in place.

    The one owner of that rule. A framebuffer's alpha byte is frequently 0 —
    it is the unused channel of an opaque window — so a capture written out
    verbatim opens fully transparent, which is the obvious trap. Both capture
    paths force it: `MemorySurface.save` on a copy, the GL readback on the
    buffer it already owns.
    """
    var px = pixels.unsafe_ptr()
    for i in range(len(pixels) // 4):
        px[unsafe_offset=i * 4 + 3] = 255


struct Surface[origin: Origin[mut=True]](Copyable, ImplicitlyCopyable, Movable):
    """A borrowed RGBA framebuffer: a pixel pointer plus its dimensions.

    Deliberately a plain value rather than a trait. Every raster loop needs
    exactly these three things, and nothing here knows where the memory came
    from — an SDL window, an owned `MemorySurface`, or anything else that can
    hand out a row-major RGBA buffer.
    """

    var px: Pointer[UInt8, Self.origin]
    var width: Int
    var height: Int

    def __init__(
        out self, px: Pointer[UInt8, Self.origin], width: Int, height: Int
    ):
        self.px = px
        self.width = width
        self.height = height

    def offset(self, x: Int, y: Int) -> Int:
        """Byte offset of pixel `(x, y)` — row-major, four bytes per pixel."""
        return (y * self.width + x) * 4


struct MemorySurface(Movable):
    """An RGBA framebuffer backed by owned memory, for rendering without a
    window.

    Holds the pixels so a `Surface` can borrow them; `pixel` reads one back so
    a test can assert on what was rendered.
    """

    var data: List[UInt8]
    var width: Int
    var height: Int

    def __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        self.data = List[UInt8](length=width * height * 4, fill=0)

    def surface(mut self) -> Surface[origin_of(self.data)]:
        """Borrow this buffer as a `Surface` for the raster primitives."""
        return Surface(self.data.unsafe_ptr(), self.width, self.height)

    def save(self, path: String, opaque: Bool = True) raises:
        """Write this buffer to `path` as a PNG.

        `opaque` runs `_force_opaque` over a copy first, which is the right
        default for anything that came off a framebuffer. Pass `opaque=False`
        only when the alpha channel is meant — a capture that deliberately
        left its background clear.
        """
        if not opaque:
            write_png(self.data, self.width, self.height, path)
            return
        var n = self.width * self.height
        var out = List[UInt8](length=n * 4, fill=0)
        unsafe_memcpy(
            dest=out.unsafe_ptr(), src=self.data.unsafe_ptr(), count=n * 4
        )
        _force_opaque(out)
        write_png(out, self.width, self.height, path)

    def pixel(self, x: Int, y: Int) -> Color:
        var off = (y * self.width + x) * 4
        return Color(
            self.data[off],
            self.data[off + 1],
            self.data[off + 2],
            self.data[off + 3],
        )
