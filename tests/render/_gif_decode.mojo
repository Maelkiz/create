"""A GIF decoder for the tests, written from the format's description rather
than from the writer, so a test of one checks the other."""

from std.testing import assert_equal, assert_true


def lzw_decode(data: List[UInt8], min_code_size: Int) raises -> List[UInt8]:
    """The decoder's half of GIF's LZW: the table grows one entry per code
    after the first, and the code width steps up once the table is full at
    the current width."""
    var clear = 1 << min_code_size
    var end = clear + 1
    var table = List[List[UInt8]]()
    for i in range(clear):
        table.append([UInt8(i)])
    table.append(List[UInt8]())
    table.append(List[UInt8]())
    var width = min_code_size + 1
    var out = List[UInt8]()
    var previous = -1
    var bit = 0
    while True:
        if (bit + width) > len(data) * 8:
            raise Error("ran off the end of the code stream")
        var code = 0
        for i in range(width):
            var at = bit + i
            code |= ((Int(data[at // 8]) >> (at % 8)) & 1) << i
        bit += width
        if code == clear:
            table.resize(end + 1, List[UInt8]())
            width = min_code_size + 1
            previous = -1
            continue
        if code == end:
            return out^
        var entry: List[UInt8]
        if previous < 0:
            entry = table[code].copy()
        elif code < len(table):
            entry = table[code].copy()
            var grown = table[previous].copy()
            grown.append(entry[0])
            table.append(grown^)
        else:
            entry = table[previous].copy()
            entry.append(entry[0])
            table.append(entry.copy())
        out += entry.copy()
        previous = code
        if len(table) == (1 << width) and width < 12:
            width += 1


struct DecodedFrame(Copyable, Movable):
    var delay: Int
    var pixels: List[UInt8]
    """RGB a pixel."""

    def __init__(out self, delay: Int, var pixels: List[UInt8]):
        self.delay = delay
        self.pixels = pixels^


struct DecodedGif(Movable):
    var width: Int
    var height: Int
    var loops: Bool
    var frames: List[DecodedFrame]

    def __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        self.loops = False
        self.frames = List[DecodedFrame]()


def _u16(data: List[UInt8], at: Int) -> Int:
    return Int(data[at]) | (Int(data[at + 1]) << 8)


def _sub_blocks(data: List[UInt8], mut at: Int) -> List[UInt8]:
    var out = List[UInt8]()
    while data[at] != 0:
        var size = Int(data[at])
        for i in range(size):
            out.append(data[at + 1 + i])
        at += size + 1
    at += 1
    return out^


def decode_gif(path: String) raises -> DecodedGif:
    var data = List[UInt8](open(path, "r").read_bytes())
    var signature = String()
    for i in range(6):
        signature += chr(Int(data[i]))
    assert_equal(signature, "GIF89a")
    var gif = DecodedGif(_u16(data, 6), _u16(data, 8))
    assert_equal(Int(data[10]) & 0x80, 0)  # no global colour table
    var at = 13
    var delay = -1
    while True:
        var kind = data[at]
        if kind == 0x3B:
            assert_equal(at, len(data) - 1)
            return gif^
        if kind == 0x21:
            var label = data[at + 1]
            at += 2
            var body = _sub_blocks(data, at)
            if label == 0xF9:
                delay = _u16(body, 1)
            elif label == 0xFF and len(body) >= 11:
                gif.loops = True
            continue
        assert_equal(Int(kind), 0x2C)
        var w = _u16(data, at + 5)
        var h = _u16(data, at + 7)
        assert_equal(w, gif.width)
        assert_equal(h, gif.height)
        var flags = Int(data[at + 9])
        assert_true(flags & 0x80 != 0)
        var colors = 1 << ((flags & 7) + 1)
        var palette_at = at + 10
        at = palette_at + colors * 3
        var min_code_size = Int(data[at])
        at += 1
        var indices = lzw_decode(_sub_blocks(data, at), min_code_size)
        assert_equal(len(indices), w * h)
        var pixels = List[UInt8]()
        for index in indices:
            for c in range(3):
                pixels.append(data[palette_at + Int(index) * 3 + c])
        gif.frames.append(DecodedFrame(delay, pixels^))
        delay = -1
