"""Writing an RGBA buffer out as a PNG file.

The encoder half of what `Image._load_png` already does for decoding:
libpng's *simplified* API, reached through `_DLHandle`, with the 104-byte
`png_image` control struct laid out by hand. Nothing here knows what the
pixels mean — it takes a buffer, its extent and a path, which is what keeps it
usable both by the design-size capture and by a raw framebuffer
screenshot whose bytes were never a `MemorySurface`.

Its own module rather than a member of `surface.mojo` because a file format is
not a framebuffer.
"""

from std.ffi import _DLHandle

from create._bytes import cstr

comptime _PNG_IMAGE_VERSION = 1

comptime _PNG_FORMAT_RGBA = 3
"""`PNG_FORMAT_FLAG_COLOR | PNG_FORMAT_FLAG_ALPHA` — the same value
`Image._load_png` asks for on the way in."""

comptime _PNG_IMAGE_SIZE = 104
"""`sizeof(png_image)`: an opaque pointer, seven `png_uint_32` fields, then a
64-byte message buffer.

    0   opaque       8   version   12  width   16  height
    20  format      24  flags      28  colormap_entries
    32  warning_or_error           36  message[64]
"""

comptime _MESSAGE_OFFSET = 36


def _put_u32(mut buf: List[UInt8], off: Int, value: Int):
    """Write one `png_uint_32` field of the control struct, little-endian —
    the counterpart of `le_uint`, which is how the read path gets them back.
    """
    for i in range(4):
        buf[off + i] = UInt8((value >> (8 * i)) & 0xFF)


def _message(buf: List[UInt8]) -> String:
    """libpng's own explanation of a failure, out of the struct's tail."""
    var out = String()
    for i in range(64):
        var c = buf[_MESSAGE_OFFSET + i]
        if c == 0:
            break
        out += chr(Int(c))
    return out^


def write_png(
    pixels: List[UInt8], width: Int, height: Int, path: String
) raises:
    """Write `width` x `height` RGBA bytes to `path` as a PNG.

    `pixels` is row-major with the top row first and four bytes per pixel —
    the layout every `Surface` in this library uses, and the one libpng's
    packed `row_stride=0` assumes.

    Raises rather than warning: a save is something the program asked for
    explicitly, so a silent no-op would be the worse failure.
    """
    if width <= 0 or height <= 0:
        raise Error("cannot write a PNG with no area: " + path)
    var need = width * height * 4
    if len(pixels) < need:
        raise Error(
            "buffer holds "
            + String(len(pixels))
            + " bytes, need "
            + String(need)
            + " for "
            + String(width)
            + "x"
            + String(height)
        )

    var lib = _DLHandle("libpng16.so")
    var img = List[UInt8](length=_PNG_IMAGE_SIZE, fill=0)
    _put_u32(img, 8, _PNG_IMAGE_VERSION)
    _put_u32(img, 12, width)
    _put_u32(img, 16, height)
    _put_u32(img, 20, _PNG_FORMAT_RGBA)
    var cpath = cstr(path)

    var ok = lib.call["png_image_write_to_file", Int](
        img.unsafe_ptr(),
        cpath.unsafe_ptr(),
        Int(0),  # convert_to_8bit: the buffer is already 8-bit
        pixels.unsafe_ptr(),
        Int(0),  # row_stride: rows are packed
        Int(0),  # colormap: none
    )
    var why = _message(img)
    # FFI rule 1: every buffer whose pointer went to C must outlive the call,
    # and passing the pointer by value tells the optimizer nothing about that.
    _ = cpath^
    _ = pixels
    _ = img^
    if ok == 0:
        raise Error("failed to write PNG " + path + ": " + why)
