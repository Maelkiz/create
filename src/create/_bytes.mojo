"""Little-endian integer decoding, shared by the file and FFI readers.

A leaf module: it imports nothing and nothing re-exports it. Both the image
decoders in `sprite` and the freetype struct readers in `render` need to
assemble bytes into an `Int`, and neither may depend on the other, so the one
copy of that loop lives here.

Deliberately absent from every `__init__.mojo` — this is internal, not part of
the public surface.
"""


def le_uint[o: Origin](p: Pointer[UInt8, o], off: Int, count: Int) -> Int:
    """Read `count` little-endian bytes at `off` as an unsigned integer.

    Takes a bare pixel-style pointer rather than a buffer type, for the same
    reason `raster` does: the caller may hold a `List`, an `Array`, or
    memory copied out of a C struct, and none of that matters here.
    """
    var v = 0
    for i in range(count):
        v |= Int(p[unsafe_offset=off + i]) << (i * 8)
    return v


def sign_extend_32(v: Int) -> Int:
    """Reinterpret a 32-bit unsigned value as signed two's complement."""
    return v - 0x100000000 if v >= 0x80000000 else v


def cstr(s: String) -> List[UInt8]:
    """A NUL-terminated byte buffer for `s`, for passing to C.

    `String.unsafe_ptr()` is not guaranteed NUL-terminated at `len(s)`, so a C
    API that scans for the terminator can read past the buffer into whatever
    follows it. Building the terminator explicitly sidesteps that.

    Here rather than beside any one FFI wrapper because `audio`, `render` and
    `sprite` all hand paths to C libraries and none of them may depend on the
    others.
    """
    var bytes = List[UInt8]()
    for b in s.as_bytes():
        bytes.append(b)
    bytes.append(0)
    return bytes^
