from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from create.sprite.sprite import Sprite, _jpeg_dimensions


def test_solid_dimensions() raises -> None:
    var s = Sprite.solid(4, 3, 255, 0, 0)
    assert_equal(s.width, 4)
    assert_equal(s.height, 3)
    assert_equal(len(s.pixels), 4 * 3 * 4)


def test_solid_pixels_correct() raises -> None:
    var s = Sprite.solid(2, 2, 255, 0, 0)
    var ptr = s.pixels.unsafe_ptr()
    for i in range(4):
        var off = i * 4
        assert_equal(Int(ptr[unsafe_offset=off]), 255)  # R
        assert_equal(Int(ptr[unsafe_offset=off + 1]), 0)  # G
        assert_equal(Int(ptr[unsafe_offset=off + 2]), 0)  # B
        assert_equal(Int(ptr[unsafe_offset=off + 3]), 255)  # A


def test_solid_blue() raises -> None:
    var s = Sprite.solid(1, 1, 0, 0, 255)
    var ptr = s.pixels.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 0)  # R
    assert_equal(Int(ptr[unsafe_offset=1]), 0)  # G
    assert_equal(Int(ptr[unsafe_offset=2]), 255)  # B
    assert_equal(Int(ptr[unsafe_offset=3]), 255)  # A


def test_from_rgba_roundtrip() raises -> None:
    var data: List[UInt8] = [10, 20, 30, 128, 40, 50, 60, 200]
    var s = Sprite.from_rgba(2, 1, data)
    assert_equal(s.width, 2)
    assert_equal(s.height, 1)
    assert_equal(Int(s.pixels[0]), 10)
    assert_equal(Int(s.pixels[1]), 20)
    assert_equal(Int(s.pixels[2]), 30)
    assert_equal(Int(s.pixels[3]), 128)
    assert_equal(Int(s.pixels[4]), 40)
    assert_equal(Int(s.pixels[7]), 200)


def test_load_bmp_dimensions() raises -> None:
    var s = Sprite.load("tests/fixtures/test_2x2.bmp")
    assert_equal(s.width, 2)
    assert_equal(s.height, 2)
    assert_equal(len(s.pixels), 2 * 2 * 4)


def test_load_bmp_pixels() raises -> None:
    # test_2x2.bmp: top-left=red, top-right=white, bottom-left=blue, bottom-right=white
    var s = Sprite.load("tests/fixtures/test_2x2.bmp")
    var ptr = s.pixels.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 255)  # (0,0) R
    assert_equal(Int(ptr[unsafe_offset=1]), 0)  # (0,0) G
    assert_equal(Int(ptr[unsafe_offset=2]), 0)  # (0,0) B
    assert_equal(Int(ptr[unsafe_offset=3]), 255)  # (0,0) A
    assert_equal(Int(ptr[unsafe_offset=4]), 255)  # (1,0) R — white
    assert_equal(Int(ptr[unsafe_offset=5]), 255)
    assert_equal(Int(ptr[unsafe_offset=6]), 255)
    assert_equal(Int(ptr[unsafe_offset=8]), 0)  # (0,1) R — blue
    assert_equal(Int(ptr[unsafe_offset=9]), 0)
    assert_equal(Int(ptr[unsafe_offset=10]), 255)


def test_load_bmp_32bit_pixels_and_alpha() raises -> None:
    # test_2x2_32bit.bmp: same colour layout as test_2x2.bmp (TL=red,
    # TR=white, BL=blue, BR=white) but 32-bit BI_RGB with four distinct,
    # file-supplied alpha values -- the only decode path that reads alpha
    # from disk rather than synthesising it.
    var s = Sprite.load("tests/fixtures/test_2x2_32bit.bmp")
    assert_equal(s.width, 2)
    assert_equal(s.height, 2)
    var ptr = s.pixels.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 255)  # (0,0) R -- red
    assert_equal(Int(ptr[unsafe_offset=1]), 0)
    assert_equal(Int(ptr[unsafe_offset=2]), 0)
    assert_equal(Int(ptr[unsafe_offset=3]), 0)  # (0,0) A
    assert_equal(Int(ptr[unsafe_offset=4]), 255)  # (1,0) -- white
    assert_equal(Int(ptr[unsafe_offset=5]), 255)
    assert_equal(Int(ptr[unsafe_offset=6]), 255)
    assert_equal(Int(ptr[unsafe_offset=7]), 85)  # (1,0) A
    assert_equal(Int(ptr[unsafe_offset=8]), 0)  # (0,1) -- blue
    assert_equal(Int(ptr[unsafe_offset=9]), 0)
    assert_equal(Int(ptr[unsafe_offset=10]), 255)
    assert_equal(Int(ptr[unsafe_offset=11]), 170)  # (0,1) A
    assert_equal(Int(ptr[unsafe_offset=12]), 255)  # (1,1) -- white
    assert_equal(Int(ptr[unsafe_offset=13]), 255)
    assert_equal(Int(ptr[unsafe_offset=14]), 255)
    assert_equal(Int(ptr[unsafe_offset=15]), 255)  # (1,1) A


def test_load_topdown_bmp_matches_bottom_up() raises -> None:
    # test_2x2_topdown.bmp carries a negative height and top-down row order,
    # but the same final image as test_2x2.bmp. Identical output here is the
    # only proof the row flip fires for one file and not the other.
    var top_down = Sprite.load("tests/fixtures/test_2x2_topdown.bmp")
    var bottom_up = Sprite.load("tests/fixtures/test_2x2.bmp")
    assert_equal(top_down.width, bottom_up.width)
    assert_equal(top_down.height, bottom_up.height)
    var a = top_down.pixels.unsafe_ptr()
    var b = bottom_up.pixels.unsafe_ptr()
    for i in range(2 * 2 * 4):
        assert_equal(Int(a[unsafe_offset=i]), Int(b[unsafe_offset=i]))


def test_load_png() raises -> None:
    var s = Sprite.load("tests/assets/sprite.png")
    assert_equal(s.width, 500)
    assert_equal(s.height, 500)
    assert_equal(len(s.pixels), 500 * 500 * 4)


def test_load_jpeg() raises -> None:
    var s = Sprite.load("tests/assets/sprite.jpeg")
    assert_equal(s.width, 500)
    assert_equal(s.height, 500)
    assert_equal(len(s.pixels), 500 * 500 * 4)


def test_load_png_pixels() raises -> None:
    # test_2x2.png: top-left=red, top-right=green, bottom-left=blue,
    # bottom-right=white. Source has no alpha channel -- decoder must
    # synthesise 255.
    var s = Sprite.load("tests/fixtures/test_2x2.png")
    var ptr = s.pixels.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 255)  # (0,0) R -- red
    assert_equal(Int(ptr[unsafe_offset=1]), 0)
    assert_equal(Int(ptr[unsafe_offset=2]), 0)
    assert_equal(Int(ptr[unsafe_offset=3]), 255)  # synthesised alpha
    assert_equal(Int(ptr[unsafe_offset=4]), 0)  # (1,0) -- green
    assert_equal(Int(ptr[unsafe_offset=5]), 255)
    assert_equal(Int(ptr[unsafe_offset=6]), 0)
    assert_equal(Int(ptr[unsafe_offset=8]), 0)  # (0,1) -- blue
    assert_equal(Int(ptr[unsafe_offset=9]), 0)
    assert_equal(Int(ptr[unsafe_offset=10]), 255)
    assert_equal(Int(ptr[unsafe_offset=12]), 255)  # (1,1) -- white
    assert_equal(Int(ptr[unsafe_offset=13]), 255)
    assert_equal(Int(ptr[unsafe_offset=14]), 255)


def _assert_close(got: Int, want: Int, tolerance: Int) raises:
    var diff = got - want if got > want else want - got
    assert_true(diff <= tolerance)


def test_load_jpeg_pixels() raises -> None:
    # test_2x2.jpeg: same layout as test_2x2.png, encoded at quality 100 with
    # no chroma subsampling. Lossy, so compare within a band far tighter than
    # the gap between any two of these colours -- a red/blue channel swap
    # would blow well past this tolerance.
    var s = Sprite.load("tests/fixtures/test_2x2.jpeg")
    var ptr = s.pixels.unsafe_ptr()
    var tol = 16
    _assert_close(Int(ptr[unsafe_offset=0]), 255, tol)  # (0,0) -- red
    _assert_close(Int(ptr[unsafe_offset=1]), 0, tol)
    _assert_close(Int(ptr[unsafe_offset=2]), 0, tol)
    _assert_close(Int(ptr[unsafe_offset=4]), 0, tol)  # (1,0) -- green
    _assert_close(Int(ptr[unsafe_offset=5]), 255, tol)
    _assert_close(Int(ptr[unsafe_offset=6]), 0, tol)
    _assert_close(Int(ptr[unsafe_offset=8]), 0, tol)  # (0,1) -- blue
    _assert_close(Int(ptr[unsafe_offset=9]), 0, tol)
    _assert_close(Int(ptr[unsafe_offset=10]), 255, tol)
    _assert_close(Int(ptr[unsafe_offset=12]), 255, tol)  # (1,1) -- white
    _assert_close(Int(ptr[unsafe_offset=13]), 255, tol)
    _assert_close(Int(ptr[unsafe_offset=14]), 255, tol)


def test_load_with_dimensions() raises -> None:
    var s = Sprite.load("tests/fixtures/test_2x2.bmp", 4, 4)
    assert_equal(s.width, 4)
    assert_equal(s.height, 4)


def test_load_nonexistent_path_raises() raises -> None:
    with assert_raises():
        _ = Sprite.load("tests/fixtures/does_not_exist.bmp")


def test_load_bmp_too_small_raises() raises -> None:
    with assert_raises(contains="too small"):
        _ = Sprite.load("tests/fixtures/bmp_too_small.bmp")


def test_load_bmp_bad_magic_raises() raises -> None:
    with assert_raises(contains="Not a BMP"):
        _ = Sprite.load("tests/fixtures/bmp_bad_magic.bmp")


def test_load_bmp_bad_dib_header_raises() raises -> None:
    with assert_raises(contains="DIB header"):
        _ = Sprite.load("tests/fixtures/bmp_bad_dib.bmp")


def test_load_bmp_bad_bpp_raises() raises -> None:
    with assert_raises(contains="24-bit or 32-bit"):
        _ = Sprite.load("tests/fixtures/bmp_bad_bpp.bmp")


def test_load_bmp_rle_compression_raises() raises -> None:
    with assert_raises(contains="Compressed BMP"):
        _ = Sprite.load("tests/fixtures/bmp_rle_compressed.bmp")


def test_load_bmp_bitfields_compression_raises() raises -> None:
    with assert_raises(contains="Compressed BMP"):
        _ = Sprite.load("tests/fixtures/bmp_bitfields_compressed.bmp")


def test_resize_dimensions() raises -> None:
    var s = Sprite.solid(4, 4, 255, 0, 0)
    s.resize(2, 2)
    assert_equal(s.width, 2)
    assert_equal(s.height, 2)
    assert_equal(len(s.pixels), 2 * 2 * 4)


def test_resize_uniform_sprite_stays_uniform() raises -> None:
    # A uniform-colour source can't reveal which source pixel nearest-neighbour
    # sampled -- only that whichever it picked was the same colour everywhere.
    var s = Sprite.solid(4, 4, 255, 0, 0)
    s.resize(2, 2)
    var ptr = s.pixels.unsafe_ptr()
    for i in range(4):  # 2×2 = 4 pixels
        var off = i * 4
        assert_equal(Int(ptr[unsafe_offset=off]), 255)  # R
        assert_equal(Int(ptr[unsafe_offset=off + 1]), 0)  # G
        assert_equal(Int(ptr[unsafe_offset=off + 2]), 0)  # B
        assert_equal(Int(ptr[unsafe_offset=off + 3]), 255)  # A


def test_resize_downscale_nearest_neighbour() raises -> None:
    # A 4x4 source with four distinct quadrant colours, downscaled to 2x2 --
    # each destination pixel must land in the matching source quadrant, which
    # a uniform-colour source could never prove.
    var s = Sprite(4, 4)
    var ptr = s.pixels.unsafe_ptr()
    for row in range(4):
        for col in range(4):
            var off = (row * 4 + col) * 4
            if row < 2 and col < 2:
                ptr[unsafe_offset=off] = 255  # top-left red
            elif row < 2:
                ptr[unsafe_offset=off + 1] = 255  # top-right green
            elif col < 2:
                ptr[unsafe_offset=off + 2] = 255  # bottom-left blue
            else:
                ptr[unsafe_offset=off] = 255  # bottom-right white
                ptr[unsafe_offset=off + 1] = 255
                ptr[unsafe_offset=off + 2] = 255
            ptr[unsafe_offset=off + 3] = 255
    s.resize(2, 2)
    var dst = s.pixels.unsafe_ptr()
    assert_equal(Int(dst[unsafe_offset=0]), 255)  # (0,0) red
    assert_equal(Int(dst[unsafe_offset=1]), 0)
    assert_equal(Int(dst[unsafe_offset=4]), 0)  # (1,0) green
    assert_equal(Int(dst[unsafe_offset=5]), 255)
    assert_equal(Int(dst[unsafe_offset=8]), 0)  # (0,1) blue
    assert_equal(Int(dst[unsafe_offset=9]), 0)
    assert_equal(Int(dst[unsafe_offset=10]), 255)
    assert_equal(Int(dst[unsafe_offset=12]), 255)  # (1,1) white
    assert_equal(Int(dst[unsafe_offset=13]), 255)
    assert_equal(Int(dst[unsafe_offset=14]), 255)


def test_resize_upscale_block_replication() raises -> None:
    # Nearest-neighbour upscaling replicates each source pixel into a block --
    # a 2x2 source blown up to 4x4 must show each quadrant colour unchanged
    # across its whole 2x2 destination block, not blended or interpolated.
    var s = Sprite(2, 2)
    var ptr = s.pixels.unsafe_ptr()
    ptr[unsafe_offset=0] = 255  # (0,0) red
    ptr[unsafe_offset=3] = 255
    ptr[unsafe_offset=5] = 255  # (1,0) green
    ptr[unsafe_offset=7] = 255
    ptr[unsafe_offset=10] = 255  # (0,1) blue
    ptr[unsafe_offset=11] = 255
    for i in range(4):
        ptr[unsafe_offset=12 + i] = 255  # (1,1) white
    s.resize(4, 4)
    var dst = s.pixels.unsafe_ptr()
    for row in range(2):
        for col in range(2):
            var off = (row * 4 + col) * 4
            assert_equal(Int(dst[unsafe_offset=off]), 255)  # red block
            assert_equal(Int(dst[unsafe_offset=off + 1]), 0)
            assert_equal(Int(dst[unsafe_offset=off + 2]), 0)
    for row in range(2):
        for col in range(2, 4):
            var off = (row * 4 + col) * 4
            assert_equal(Int(dst[unsafe_offset=off]), 0)  # green block
            assert_equal(Int(dst[unsafe_offset=off + 1]), 255)
            assert_equal(Int(dst[unsafe_offset=off + 2]), 0)
    for row in range(2, 4):
        for col in range(2, 4):
            var off = (row * 4 + col) * 4
            assert_equal(Int(dst[unsafe_offset=off]), 255)  # white block
            assert_equal(Int(dst[unsafe_offset=off + 1]), 255)
            assert_equal(Int(dst[unsafe_offset=off + 2]), 255)


def test_resize_upscale() raises -> None:
    var s = Sprite.solid(2, 2, 0, 255, 0)
    s.resize(4, 4)
    assert_equal(s.width, 4)
    assert_equal(s.height, 4)
    assert_equal(len(s.pixels), 4 * 4 * 4)


def test_resize_to_1x1() raises -> None:
    var s = Sprite.solid(100, 100, 255, 255, 255)
    s.resize(1, 1)
    assert_equal(s.width, 1)
    assert_equal(s.height, 1)
    assert_equal(len(s.pixels), 4)


def test_solid_1x1() raises -> None:
    var s = Sprite.solid(1, 1, 0, 255, 0)
    assert_equal(s.width, 1)
    assert_equal(s.height, 1)
    assert_equal(len(s.pixels), 4)
    var ptr = s.pixels.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 0)  # R
    assert_equal(Int(ptr[unsafe_offset=1]), 255)  # G
    assert_equal(Int(ptr[unsafe_offset=2]), 0)  # B
    assert_equal(Int(ptr[unsafe_offset=3]), 255)  # A


def test_from_rgba_ignores_trailing_bytes() raises -> None:
    # from_rgba trusts the caller's dimensions and copies exactly width*height*4
    # bytes -- extra bytes past that must be ignored, not appended.
    var data: List[UInt8] = [1, 2, 3, 4, 99, 99, 99, 99]
    var s = Sprite.from_rgba(1, 1, data)
    assert_equal(len(s.pixels), 4)
    assert_equal(Int(s.pixels[0]), 1)
    assert_equal(Int(s.pixels[1]), 2)
    assert_equal(Int(s.pixels[2]), 3)
    assert_equal(Int(s.pixels[3]), 4)


def test_sprite_zero_dimensions() raises -> None:
    var s = Sprite(0, 0)
    assert_equal(s.width, 0)
    assert_equal(s.height, 0)
    assert_equal(len(s.pixels), 0)


def test_resize_to_zero_dimension() raises -> None:
    var s = Sprite.solid(4, 4, 255, 0, 0)
    s.resize(0, 4)
    assert_equal(s.width, 0)
    assert_equal(s.height, 4)
    assert_equal(len(s.pixels), 0)


def test_resize_from_zero_width_stays_blank() raises -> None:
    # A zero-width source has no pixel to sample -- the guard must skip the
    # offset arithmetic entirely rather than dividing by/indexing an empty
    # buffer, and leave the destination zero-filled.
    var s = Sprite(0, 4)
    s.resize(2, 2)
    assert_equal(s.width, 2)
    assert_equal(s.height, 2)
    assert_equal(len(s.pixels), 2 * 2 * 4)
    var ptr = s.pixels.unsafe_ptr()
    for i in range(2 * 2 * 4):
        assert_equal(Int(ptr[unsafe_offset=i]), 0)


def test_extension_simple() raises -> None:
    assert_equal(Sprite._extension("sprite.png"), "png")


def test_extension_uppercase_is_lowercased() raises -> None:
    assert_equal(Sprite._extension("SPRITE.PNG"), "png")


def test_extension_no_dot() raises -> None:
    assert_equal(Sprite._extension("sprite"), "")


def test_extension_trailing_dot() raises -> None:
    assert_equal(Sprite._extension("sprite."), "")


def test_extension_dot_in_directory_no_file_extension() raises -> None:
    assert_equal(Sprite._extension("assets/v1.2/sprite"), "2/sprite")


def test_extension_double_extension() raises -> None:
    assert_equal(Sprite._extension("archive.tar.gz"), "gz")


def test_jpeg_dimensions_sof0() raises -> None:
    # SOI, then a baseline SOF0 marker (FF C0) with an 8-byte segment
    # encoding precision=8, height=0x0010, width=0x0020, 0 components.
    var data: List[UInt8] = [
        0xFF,
        0xD8,
        0xFF,
        0xC0,
        0x00,
        0x08,
        0x08,
        0x00,
        0x10,
        0x00,
        0x20,
        0x00,
    ]
    var dims = _jpeg_dimensions(data)
    assert_equal(dims[0], 0x20)
    assert_equal(dims[1], 0x10)


def test_jpeg_dimensions_sof2_progressive() raises -> None:
    # A leading non-SOF segment (a 4-byte APP0-like marker) must be skipped
    # via its own length before the SOF2 (FF C2) marker is found.
    var data: List[UInt8] = [
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x04,
        0x00,
        0x00,
        0xFF,
        0xC2,
        0x00,
        0x08,
        0x08,
        0x00,
        0x05,
        0x00,
        0x07,
        0x00,
    ]
    var dims = _jpeg_dimensions(data)
    assert_equal(dims[0], 0x07)
    assert_equal(dims[1], 0x05)


def test_jpeg_dimensions_no_sof_raises() raises -> None:
    # SOI immediately followed by EOI -- no SOF marker ever appears.
    var data: List[UInt8] = [
        0xFF,
        0xD8,
        0xFF,
        0xD9,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
    ]
    with assert_raises(contains="No SOF marker"):
        _ = _jpeg_dimensions(data)


def test_jpeg_dimensions_bad_marker_raises() raises -> None:
    # Byte 2 is 0x00 instead of the required 0xFF marker-lead byte. Padded to
    # 12 bytes so the loop's `i < len(data) - 8` guard still lets it execute.
    var data: List[UInt8] = [0xFF, 0xD8, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    with assert_raises(contains="expected marker byte"):
        _ = _jpeg_dimensions(data)


def test_load_bmp_alpha_channel() raises -> None:
    var s = Sprite.load("tests/fixtures/test_2x2.bmp")
    var ptr = s.pixels.unsafe_ptr()
    # BMP has no alpha — loader should set alpha=255 for all pixels
    assert_equal(Int(ptr[unsafe_offset=3]), 255)  # (0,0) A
    assert_equal(Int(ptr[unsafe_offset=7]), 255)  # (1,0) A
    assert_equal(Int(ptr[unsafe_offset=11]), 255)  # (0,1) A
    assert_equal(Int(ptr[unsafe_offset=15]), 255)  # (1,1) A


def test_supports_extension_accepts_every_decoded_format() raises -> None:
    assert_true(Sprite.supports_extension("png"))
    assert_true(Sprite.supports_extension("jpg"))
    assert_true(Sprite.supports_extension("jpeg"))
    assert_true(Sprite.supports_extension("bmp"))


def test_supports_extension_rejects_other_formats() raises -> None:
    assert_false(Sprite.supports_extension("gif"))
    assert_false(Sprite.supports_extension("txt"))
    assert_false(Sprite.supports_extension(""))


def test_supports_extension_pairs_with_extension() raises -> None:
    # The two are used together -- `_extension` lowercases, so the list needs
    # no uppercase spellings of its own.
    assert_true(Sprite.supports_extension(Sprite._extension("frame_01.PNG")))
    assert_false(Sprite.supports_extension(Sprite._extension("notes.md")))


def test_stem_end_finds_the_last_dot() raises -> None:
    assert_equal(Sprite._stem_end("sprite.png"), 6)
    assert_equal(Sprite._stem_end("archive.tar.gz"), 11)


def test_stem_end_without_a_dot_is_the_length() raises -> None:
    # No dot means the stem is the whole name -- what the frame-number scan
    # needs so it can walk back from the end.
    assert_equal(Sprite._stem_end("sprite"), 6)
    assert_equal(Sprite._stem_end(""), 0)


def test_every_sprite_gets_its_own_identity() raises -> None:
    # A backend caches one image per id, so two sprites sharing one would make
    # the second render the first's pixels.
    var a = Sprite(2, 2)
    var b = Sprite(2, 2)
    var c = Sprite.solid(1, 1, 255, 0, 0)
    var d = Sprite.from_rgba(1, 1, List[UInt8](length=4, fill=255))
    assert_true(a._id != b._id)
    assert_true(b._id != c._id)
    assert_true(c._id != d._id)
    assert_true(a._id > 0, "0 is reserved for no image")


def test_a_moved_sprite_keeps_its_identity() raises -> None:
    var a = Sprite(2, 2)
    var want = a._id
    var moved = a^
    assert_equal(moved._id, want)


def test_resizing_takes_a_fresh_identity() raises -> None:
    # The pixels are replaced, so anything cached under the old id is stale.
    var s = Sprite.solid(2, 2, 255, 0, 0)
    var before = s._id
    s.resize(4, 4)
    assert_true(s._id != before)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
