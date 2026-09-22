from std.ffi import _DLHandle
from std.math import abs

from create._bytes import le_uint, sign_extend_32
from .color import Color

# The two packaged faces, loaded lazily on the first text render: Noto Sans for
# text, Noto Sans Symbols for codepoints the first face has no glyph for.
#
# Both are *relative* paths, resolved against the process CWD rather than the
# source file, so `frame.text` only works when a program is run from the repo
# root. Anywhere else, every text render raises "FT_New_Face failed — font not
# found".
comptime FONT_DEFAULT_PATH = "defaults/fonts/NotoSans.ttf"
comptime FONT_FALLBACK_PATH = "defaults/fonts/NotoSansSymbols.ttf"


struct FontWeight:
    """Named stroke weights for `frame.font_weight`.

    Design-space values on the packaged variable faces, so they interpolate
    rather than selecting a file — any number in 100..900 is valid, these are
    just the ones with names.
    """

    comptime THIN = 100
    comptime LIGHT = 300
    comptime REGULAR = 400
    comptime MEDIUM = 500
    comptime BOLD = 700
    comptime BLACK = 900


# FT_FaceRec offsets
comptime _FACE_GLYPH = 152
comptime _FACE_SIZE = 160  # FT_Size* pointer

# FT_SizeRec: face(8) + generic(16) = metrics at offset 24
# FT_Size_Metrics: x_ppem(2)+y_ppem(2)+pad(4)+x_scale(8)+y_scale(8) = ascender at +24, descender at +32
comptime _SIZE_METRICS = 24
comptime _METRICS_ASC = 24
comptime _METRICS_DESC = 32

# FT_MM_Var offsets (64-bit layout: 3×UInt(4)+pad(4)+pointer(8))
comptime _MM_NUM_AXIS = 0
comptime _MM_AXIS = 16

# FT_Var_Axis offsets (64-bit layout: ptr(8)+3×Fixed(8)+ULong(8)+UInt(4)+pad(4) = 48 bytes)
comptime _AXIS_DEF = 16  # FT_Fixed default design value (16.16)
comptime _AXIS_TAG = 32  # FT_ULong 4-char tag
comptime _AXIS_SIZE = 48  # sizeof(FT_Var_Axis)

comptime _TAG_WGHT = 0x77676874  # 'wght'

# FT_GlyphSlotRec offsets
comptime _GLYPH_ADVANCE = 128  # FT_Vector: x = first FT_Pos (8 bytes)
comptime _GLYPH_BITMAP = 152  # FT_Bitmap struct
comptime _GLYPH_BMP_LEFT = 192  # FT_Int (signed, 4 bytes)
comptime _GLYPH_BMP_TOP = 196  # FT_Int (signed, 4 bytes)

# FT_Bitmap field offsets (relative to bitmap start)
comptime _BMP_ROWS = 0
comptime _BMP_WIDTH = 4
comptime _BMP_PITCH = 8
comptime _BMP_BUFFER = 16

comptime _FT_LOAD_DEFAULT = 0
comptime _FT_RENDER_MODE_NORMAL = 0


# These wrap `le_uint` rather than being replaced by it: reading a C struct
# field means copying it out of foreign memory first, and a leaf module has no
# business linking libc for one caller's sake. The copy is what differs from
# the image decoders; the assembly is not, so only that is shared.


def _read_u32(addr: Int) raises -> Int:
    var buf = Array[UInt8, 4](fill=0)
    _ = _DLHandle("libc.so.6").call["memcpy", Int](buf.unsafe_ptr(), addr, 4)
    return le_uint(buf.unsafe_ptr(), 0, 4)


def _read_i32(addr: Int) raises -> Int:
    return sign_extend_32(_read_u32(addr))


def _read_ptr(addr: Int) raises -> Int:
    var buf = Array[UInt8, 8](fill=0)
    _ = _DLHandle("libc.so.6").call["memcpy", Int](buf.unsafe_ptr(), addr, 8)
    return le_uint(buf.unsafe_ptr(), 0, 8)


struct _GlyphInfo(Movable):
    """One rendered glyph: its coverage mask and where to put it.

    The mask is alpha only — the colour comes from the style at blit time, so
    one cached glyph serves every colour it is ever rendered in. `TextRenderer`
    keeps them, keyed by codepoint, pixel size and weight; a `Font` renders
    one and forgets it.
    """

    var pixels: List[UInt8]  # 8-bit grayscale alpha, row-major
    var width: Int
    var height: Int
    var bearing_x: Int  # horizontal offset from pen to glyph left edge
    var bearing_y: Int  # vertical offset from baseline to glyph top
    var advance_x: Int  # horizontal pen advance in pixels

    def __init__(
        out self,
        width: Int,
        height: Int,
        bearing_x: Int,
        bearing_y: Int,
        advance_x: Int,
    ):
        self.pixels = List[UInt8](length=width * height, fill=0)
        self.width = width
        self.height = height
        self.bearing_x = bearing_x
        self.bearing_y = bearing_y
        self.advance_x = advance_x


struct Font(Movable):
    """One loaded face, rendered through freetype over the C ABI.

    A face is a heavy handle, not a per-frame value — `TextRenderer` loads the
    packaged faces once and caches what they render; `frame.font` swaps in
    another and it survives the frame in `PersistentFrameState`.

    Size and weight are sticky state on the face rather than arguments to
    `render`, which is why both setters return early when nothing changed:
    re-scaling a face or re-solving its variation axes per glyph would be paid
    on every character of every string.
    """

    var _lib: Int  # FT_Library opaque pointer
    var _face: Int  # FT_Face opaque pointer
    var _size: Int  # last set pixel height
    var _weight: Int  # last set design-space weight (100–900)
    var ascender: Int  # pixels above baseline (positive)
    var descender: Int  # pixels below baseline (negative)

    def __init__(out self, path: String, size: Int, weight: Int = 400) raises:
        var ft = _DLHandle("libfreetype.so.6")

        var lib_buf = Array[UInt8, 8](fill=0)
        if ft.call["FT_Init_FreeType", Int32](lib_buf.unsafe_ptr()) != 0:
            raise Error("FT_Init_FreeType failed")
        self._lib = _read_ptr(Int(lib_buf.unsafe_ptr()))

        var face_buf = Array[UInt8, 8](fill=0)
        if (
            ft.call["FT_New_Face", Int32](
                self._lib, path.unsafe_ptr(), Int(0), face_buf.unsafe_ptr()
            )
            != 0
        ):
            _ = ft.call["FT_Done_FreeType", Int32](self._lib)
            raise Error("FT_New_Face failed — font not found: " + path)
        self._face = _read_ptr(Int(face_buf.unsafe_ptr()))
        self._size = 0
        self._weight = 0
        self.ascender = 0
        self.descender = 0
        self._set_size(ft, size)
        self._set_weight(weight)

    def _set_size(mut self, ft: _DLHandle, size: Int) raises:
        if size == self._size:
            return
        _ = ft.call["FT_Set_Pixel_Sizes", Int32](
            self._face, UInt32(0), UInt32(size)
        )
        self._size = size
        var size_ptr = _read_ptr(self._face + _FACE_SIZE)
        var m = size_ptr + _SIZE_METRICS
        self.ascender = _read_ptr(m + _METRICS_ASC) >> 6
        self.descender = _read_ptr(m + _METRICS_DESC) >> 6

    def _set_weight(mut self, weight: Int) raises:
        if weight == self._weight:
            return
        var ft = _DLHandle("libfreetype.so.6")
        var master_buf = Array[UInt8, 8](fill=0)
        if (
            ft.call["FT_Get_MM_Var", Int32](self._face, master_buf.unsafe_ptr())
            != 0
        ):
            return
        var master = _read_ptr(Int(master_buf.unsafe_ptr()))
        var num_axis = _read_u32(master + _MM_NUM_AXIS)
        var axis_ptr = _read_ptr(master + _MM_AXIS)

        # Build coord array: num_axis FT_Fixed values (8 bytes each, little-endian)
        var coords = List[UInt8](length=num_axis * 8, fill=0)
        for i in range(num_axis):
            var a = axis_ptr + i * _AXIS_SIZE
            var tag = _read_ptr(a + _AXIS_TAG)
            var val = weight << 16 if tag == _TAG_WGHT else _read_ptr(
                a + _AXIS_DEF
            )
            var v = val
            for b in range(8):
                coords[i * 8 + b] = UInt8(v & 0xFF)
                v >>= 8

        _ = ft.call["FT_Set_Var_Design_Coordinates", Int32](
            self._face, UInt32(num_axis), coords.unsafe_ptr()
        )
        self._weight = weight
        _ = ft.call["FT_Done_MM_Var", Int32](self._lib, master)

    def has_glyph(self, codepoint: Int) raises -> Bool:
        """Whether this face can render this codepoint — how `TextRenderer`
        decides to fall back to the symbols face."""
        var ft = _DLHandle("libfreetype.so.6")
        return (
            ft.call["FT_Get_Char_Index", UInt32](self._face, Int(codepoint))
            != 0
        )

    def render(mut self, codepoint: Int, size: Int) raises -> _GlyphInfo:
        """Rasterise one glyph at `size` pixels.

        A codepoint this face cannot load or render yields an empty glyph that
        still advances the pen, so a missing character leaves a gap rather than
        collapsing the line or raising mid-string.
        """
        var ft = _DLHandle("libfreetype.so.6")
        self._set_size(ft, size)

        if (
            ft.call["FT_Load_Char", Int32](
                self._face, codepoint, Int32(_FT_LOAD_DEFAULT)
            )
            != 0
        ):
            return _GlyphInfo(0, 0, 0, 0, size)

        if (
            ft.call["FT_Render_Glyph", Int32](
                _read_ptr(self._face + _FACE_GLYPH),
                Int32(_FT_RENDER_MODE_NORMAL),
            )
            != 0
        ):
            return _GlyphInfo(0, 0, 0, 0, size)

        var glyph = _read_ptr(self._face + _FACE_GLYPH)
        var bmp = glyph + _GLYPH_BITMAP
        var rows = _read_u32(bmp + _BMP_ROWS)
        var width = _read_u32(bmp + _BMP_WIDTH)
        var pitch = _read_i32(bmp + _BMP_PITCH)
        var buf_ptr = _read_ptr(bmp + _BMP_BUFFER)
        var bmp_left = _read_i32(glyph + _GLYPH_BMP_LEFT)
        var bmp_top = _read_i32(glyph + _GLYPH_BMP_TOP)
        var advance_x = (
            _read_ptr(glyph + _GLYPH_ADVANCE) >> 6
        )  # 26.6 fixed-point

        var g = _GlyphInfo(width, rows, bmp_left, bmp_top, advance_x)
        if buf_ptr != 0 and width > 0 and rows > 0:
            var stride = abs(pitch)
            var libc = _DLHandle("libc.so.6")
            for row in range(rows):
                _ = libc.call["memcpy", Int](
                    Int(g.pixels.unsafe_ptr()) + row * width,
                    buf_ptr + row * stride,
                    width,
                )
        return g^
