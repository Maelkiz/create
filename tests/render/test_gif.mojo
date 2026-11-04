# The GIF writer behind canvas.start_recording, checked against the decoder in
# _gif_decode.mojo: LZW round trips at every code size (a full table cleared
# included), exact and quantised palettes, and a whole file's header,
# frames, delays and trailer.

from std.testing import TestSuite, assert_equal, assert_true

from create import *
from _gif_decode import decode_gif, lzw_decode
from create.render._gif import (
    GifWriter,
    encode_frame,
    lzw_encode,
    quantise,
)


def _random_bytes(count: Int, symbols: Int, seed: UInt64) -> List[UInt8]:
    var random = Random(seed)
    var out = List[UInt8]()
    for _ in range(count):
        out.append(UInt8(random.int(0, symbols)))
    return out^


def test_lzw_round_trips_at_every_code_size() raises -> None:
    for min_code_size in range(2, 9):
        var symbols = 1 << min_code_size
        # Long enough to fill the 4096-code table and clear it, and short
        # runs that hit the code width's first steps.
        for count in [1, 2, 7, 300, 40000]:
            var data = _random_bytes(count, symbols, UInt64(count))
            var back = lzw_decode(
                lzw_encode(data, min_code_size), min_code_size
            )
            assert_equal(len(back), count)
            for i in range(count):
                assert_equal(back[i], data[i])


def test_lzw_round_trips_repetitive_data() raises -> None:
    # Long runs grow long table entries, the opposite case to noise.
    var data = List[UInt8]()
    for i in range(60000):
        data.append(UInt8((i // 97) % 3))
    var back = lzw_decode(lzw_encode(data, 2), 2)
    assert_equal(len(back), len(data))
    for i in range(len(data)):
        assert_equal(back[i], data[i])


def _rgba[
    colour: def(Int, Int) thin -> Color
](width: Int, height: Int) -> List[UInt8]:
    var out = List[UInt8]()
    for y in range(height):
        for x in range(width):
            var c = colour(x, y)
            out.append(c.r)
            out.append(c.g)
            out.append(c.b)
            out.append(255)
    return out^


def _stripes(x: Int, y: Int) -> Color:
    var colors: List[Color] = [
        Color.RED,
        Color(12, 34, 56),
        Color.WHITE,
        Color(90, 170, 255),
        Color.BLACK,
    ]
    return colors[(x + 2 * y) % len(colors)]


def _ramp(x: Int, y: Int) -> Color:
    return Color(UInt8(x * 4), UInt8(y * 4), UInt8((x + y) * 2))


def test_few_colours_quantise_exactly() raises -> None:
    var pixels = _rgba[_stripes](20, 11)
    var q = quantise(pixels, 20, 11, dither=False)
    assert_equal(q.bits, 3)  # five colours, padded to eight
    for i in range(20 * 11):
        var index = Int(q.indices[i])
        for c in range(3):
            assert_equal(q.palette[index * 3 + c], pixels[i * 4 + c])


def _worst_error(
    pixels: List[UInt8],
    q_palette: List[UInt8],
    q_indices: List[UInt8],
    count: Int,
) -> Int:
    var worst = 0
    for i in range(count):
        var index = Int(q_indices[i])
        for c in range(3):
            var d = abs(Int(pixels[i * 4 + c]) - Int(q_palette[index * 3 + c]))
            worst = max(worst, d)
    return worst


def test_many_colours_quantise_closely() raises -> None:
    # 4096 distinct colours into 256: median cut keeps every pixel near.
    var pixels = _rgba[_ramp](64, 64)
    var q = quantise(pixels, 64, 64, dither=False)
    assert_equal(q.bits, 8)
    assert_true(_worst_error(pixels, q.palette, q.indices, 64 * 64) <= 24)


def test_dithering_keeps_the_average_colour() raises -> None:
    # Dithering trades a pixel's error for its neighbourhood's: a flat colour
    # between palette entries averages out to itself.
    var pixels = _rgba[_ramp](64, 64)
    var q = quantise(pixels, 64, 64, dither=True)
    var wanted = 0
    var got = 0
    for i in range(64 * 64):
        wanted += Int(pixels[i * 4])
        got += Int(q.palette[Int(q.indices[i]) * 3])
    assert_true(abs(wanted - got) <= 64 * 64)  # within a level on average


def test_a_written_gif_decodes_frame_by_frame() raises -> None:
    var path = String("/tmp/create_test_gif_frames.gif")
    var writer = GifWriter(path, 20, 11)
    writer.write_frame(encode_frame(_rgba[_stripes](20, 11), 20, 11, False), 3)
    writer.write_frame(encode_frame(_rgba[_ramp](20, 11), 20, 11, False), 7)
    writer.finish()

    var gif = decode_gif(path)
    assert_equal(gif.width, 20)
    assert_equal(gif.height, 11)
    assert_true(gif.loops)
    assert_equal(len(gif.frames), 2)
    assert_equal(gif.frames[0].delay, 3)
    assert_equal(gif.frames[1].delay, 7)
    var stripes = _rgba[_stripes](20, 11)
    for i in range(20 * 11):
        for c in range(3):
            assert_equal(gif.frames[0].pixels[i * 3 + c], stripes[i * 4 + c])


def test_a_gif_needs_an_area() raises -> None:
    var raised = False
    try:
        _ = GifWriter("/tmp/create_test_gif_empty.gif", 0, 10)
    except:
        raised = True
    assert_true(raised)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
