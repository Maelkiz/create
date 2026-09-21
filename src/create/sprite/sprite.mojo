from std.atomic import Atomic
from std.ffi import _DLHandle, _Global

from create._bytes import le_uint, sign_extend_32


def _new_sprite_ids() -> Atomic[DType.int64]:
    return Atomic[DType.int64](0)


comptime _SPRITE_IDS = _Global["create_sprite_ids", _new_sprite_ids]
"""Process-wide counter behind `Sprite._id`.

Global rather than per-`Sprite` because the point is uniqueness *between*
sprites, and global rather than per-backend because a sprite may be rendered
through more than one.
"""


def _next_sprite_id() raises -> Int:
    """The next never-yet-used sprite identity. Starts at 1, so 0 stays free
    to mean "no image"."""
    return Int(_SPRITE_IDS.get_or_create_ptr()[].fetch_add(1)) + 1


def _read_u16(data: List[UInt8], off: Int) -> Int:
    return le_uint(data.unsafe_ptr(), off, 2)


def _read_i32(data: List[UInt8], off: Int) -> Int:
    return sign_extend_32(_read_u32(data, off))


def _read_u32(data: List[UInt8], off: Int) -> Int:
    return le_uint(data.unsafe_ptr(), off, 4)


def _jpeg_dimensions(data: List[UInt8]) raises -> Tuple[Int, Int]:
    """Parse width and height from JPEG SOF marker."""
    var i = 2  # skip SOI marker FF D8
    while i < len(data) - 8:
        if data[i] != 0xFF:
            raise Error("Invalid JPEG: expected marker byte")
        var marker = Int(data[i + 1])
        if marker == 0xD9:  # EOI
            break
        # SOF markers encode image dimensions
        if (
            (marker >= 0xC0 and marker <= 0xC3)
            or (marker >= 0xC5 and marker <= 0xC7)
            or (marker >= 0xC9 and marker <= 0xCB)
            or (marker >= 0xCD and marker <= 0xCF)
        ):
            var h = (Int(data[i + 5]) << 8) | Int(data[i + 6])
            var w = (Int(data[i + 7]) << 8) | Int(data[i + 8])
            return (w, h)
        var seg_len = (Int(data[i + 2]) << 8) | Int(data[i + 3])
        i += 2 + seg_len
    raise Error("No SOF marker found in JPEG")


struct Sprite(Movable):
    """An owned RGBA pixel buffer, row-major, 8 bits per channel.

    Decoded once at load — `Sprite.load` picks a BMP, PNG or JPEG decoder by
    file extension — and blitted many times afterwards. `Sprite.solid` and
    `Sprite.from_rgba` build one without a file, and `resize` resamples in
    place.

    Deliberately not a render type: `raster.blit_sprite` takes a pixel pointer
    with a width and a height rather than this struct, so the image decoders
    stay out of the render path and the rasteriser is written against no layout
    but its own.
    """

    var pixels: List[UInt8]
    var width: Int
    var height: Int
    var _id: Int
    """This image's identity, unique for the life of the process.

    A backend caches a copy or a GPU texture per sprite and needs a key that
    cannot collide. The pixel buffer's address cannot serve: free one sprite,
    allocate another, and the second inherits the first's cached image. A
    counter can only run out, and it never does at 63 bits.

    Bumped by `resize`, which replaces the pixels — so a resized sprite is a
    new image to a cache, which is exactly what it is.
    """

    def __init__(out self, width: Int, height: Int) raises:
        """Raises only if the process-wide identity counter cannot be reached,
        which is why every construction path here raises."""
        self.width = width
        self.height = height
        self.pixels = List[UInt8](length=width * height * 4, fill=0)
        self._id = _next_sprite_id()

    @staticmethod
    def solid(
        width: Int,
        height: Int,
        r: UInt8,
        g: UInt8,
        b: UInt8,
        a: UInt8 = 255,
    ) raises -> Sprite:
        var s = Sprite(width, height)
        var ptr = s.pixels.unsafe_ptr()
        for i in range(width * height):
            var off = i * 4
            ptr[unsafe_offset=off] = r
            ptr[unsafe_offset=off + 1] = g
            ptr[unsafe_offset=off + 2] = b
            ptr[unsafe_offset=off + 3] = a
        return s^

    @staticmethod
    def from_rgba(width: Int, height: Int, data: List[UInt8]) raises -> Sprite:
        """Precondition: `data` holds at least `width * height * 4` bytes — not bounds-checked.
        """
        var s = Sprite(width, height)
        var src = data.unsafe_ptr()
        var dst = s.pixels.unsafe_ptr()
        for i in range(width * height * 4):
            dst[unsafe_offset=i] = src[unsafe_offset=i]
        return s^

    def resize(mut self, new_w: Int, new_h: Int) raises:
        """Resize pixel buffer in place using nearest-neighbour sampling.

        Takes a fresh identity: the pixels are not the ones a backend may
        already have cached under the old one.
        """
        self._id = _next_sprite_id()
        var dst = List[UInt8](length=new_w * new_h * 4, fill=0)
        if self.width == 0 or self.height == 0:
            # No source pixel to sample -- leave the zero-filled buffer as is
            # rather than computing an offset into an empty source.
            self.pixels = dst^
            self.width = new_w
            self.height = new_h
            return
        var src_ptr = self.pixels.unsafe_ptr()
        var dst_ptr = dst.unsafe_ptr()
        for row in range(new_h):
            var src_row = row * self.height // new_h
            for col in range(new_w):
                var src_col = col * self.width // new_w
                var s = (src_row * self.width + src_col) * 4
                var d = (row * new_w + col) * 4
                dst_ptr[unsafe_offset=d] = src_ptr[unsafe_offset=s]
                dst_ptr[unsafe_offset=d + 1] = src_ptr[unsafe_offset=s + 1]
                dst_ptr[unsafe_offset=d + 2] = src_ptr[unsafe_offset=s + 2]
                dst_ptr[unsafe_offset=d + 3] = src_ptr[unsafe_offset=s + 3]
        self.pixels = dst^
        self.width = new_w
        self.height = new_h

    @staticmethod
    def load(path: String, width: Int, height: Int) raises -> Sprite:
        """Load an image file and resize to the given dimensions."""
        var s = Sprite.load(path)
        s.resize(width, height)
        return s^

    @staticmethod
    def _stem_end(path: String) -> Int:
        """Index of the last `.` in `path`, or its length when it has none.

        Where the stem ends and any extension begins. Shared with the frame
        ordering in `animation`, which needs the same split to find the number
        a name ends in. Scans the whole path, not just the last segment, so
        `assets/v1.2/sprite` reports the dot in the directory -- long-standing
        behaviour, pinned by test.
        """
        var bytes = path.as_bytes()
        var end = len(bytes)
        for i in range(len(bytes)):
            if bytes[i] == 46:  # '.'
                end = i
        return end

    @staticmethod
    def _extension(path: String) -> String:
        var bytes = path.as_bytes()
        var dot = Sprite._stem_end(path)
        if dot == len(bytes):
            return ""
        var ext = String()
        for i in range(dot + 1, len(bytes)):
            ext += String(chr(Int(bytes[i]) | 32))  # lowercase
        return ext

    @staticmethod
    def supports_extension(ext: String) -> Bool:
        """Whether `load` has a decoder for this lowercase extension.

        The one list of formats the library reads. `from_folder` filters a
        directory with it; keep it in step with `load`'s dispatch below.
        """
        return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "bmp"

    @staticmethod
    def _load_png(data: List[UInt8]) raises -> Sprite:
        var lib = _DLHandle("libpng16.so")
        var img = InlineArray[UInt8, 104](fill=0)
        img[8] = 1  # PNG_IMAGE_VERSION

        var ok = lib.call["png_image_begin_read_from_memory", Int](
            img.unsafe_ptr(), data.unsafe_ptr(), len(data)
        )
        if ok == 0:
            raise Error("Failed to begin reading PNG")

        var w = le_uint(img.unsafe_ptr(), 12, 4)
        var h = le_uint(img.unsafe_ptr(), 16, 4)
        img[20] = 3  # PNG_FORMAT_RGBA

        var s = Sprite(w, h)
        var ok2 = lib.call["png_image_finish_read", Int](
            img.unsafe_ptr(), Int(0), s.pixels.unsafe_ptr(), Int(0), Int(0)
        )
        lib.call["png_image_free"](img.unsafe_ptr())

        if ok2 == 0:
            raise Error("Failed to decode PNG")
        return s^

    @staticmethod
    def _load_jpeg(data: List[UInt8]) raises -> Sprite:
        var dims = _jpeg_dimensions(data)
        var w = dims[0]
        var h = dims[1]

        var lib = _DLHandle("libturbojpeg.so")
        var handle = lib.call["tjInitDecompress", Int]()
        if handle == 0:
            raise Error("Failed to init JPEG decompressor")

        var s = Sprite(w, h)
        var result = lib.call["tjDecompress2", Int32](
            handle,
            data.unsafe_ptr(),
            len(data),
            s.pixels.unsafe_ptr(),
            Int32(w),
            Int32(0),
            Int32(h),
            Int32(7),  # TJPF_RGBA
            Int32(0),
        )
        lib.call["tjDestroy"](handle)

        if result != 0:
            raise Error("Failed to decode JPEG")
        return s^

    @staticmethod
    def load(path: String) raises -> Sprite:
        """Load an image file. Supports BMP, PNG, and JPEG."""
        var ext = Sprite._extension(path)
        with open(path, "r") as f:
            var data = f.read_bytes()

            if ext == "png":
                return Sprite._load_png(data)
            if ext == "jpg" or ext == "jpeg":
                return Sprite._load_jpeg(data)

            if len(data) < 54:
                raise Error("BMP file too small: " + path)
            if data[0] != 66 or data[1] != 77:  # "BM"
                raise Error("Not a BMP file: " + path)

            var pixel_offset = _read_u32(data, 10)
            var dib_size = _read_u32(data, 14)
            if dib_size < 40:
                raise Error("Unsupported BMP DIB header: " + path)

            var w = _read_i32(data, 18)
            var raw_h = _read_i32(data, 22)
            var top_down = raw_h < 0
            var h = -raw_h if top_down else raw_h
            var bpp = _read_u16(data, 28)
            var compression = _read_u32(data, 30)

            if bpp != 24 and bpp != 32:
                raise Error("BMP must be 24-bit or 32-bit, got: " + path)
            if compression != 0:
                raise Error("Compressed BMP not supported: " + path)

            var s = Sprite(w, h)
            var dst = s.pixels.unsafe_ptr()

            # 24- and 32-bit differ only in the source stride and where alpha
            # comes from. Rows are padded to a 4-byte boundary, which the
            # stride formula already gives as exactly `w * 4` at 32-bit.
            var bytes_per_px = bpp // 8
            var row_stride = ((w * bytes_per_px + 3) // 4) * 4
            for row in range(h):
                # Bottom-up is the BMP default; a negative height means the
                # rows were stored top-down instead.
                var src_row = (h - 1 - row) if not top_down else row
                var src_base = pixel_offset + src_row * row_stride
                for col in range(w):
                    var src = src_base + col * bytes_per_px
                    var d = (row * w + col) * 4
                    dst[unsafe_offset=d] = data[src + 2]  # R
                    dst[unsafe_offset=d + 1] = data[src + 1]  # G
                    dst[unsafe_offset=d + 2] = data[src]  # B
                    dst[unsafe_offset=d + 3] = (
                        data[src + 3] if bytes_per_px == 4 else 255
                    )

            return s^
