"""Writing animated GIFs, frame by frame: what `canvas.start_recording` saves.

A GIF frame holds at most 256 colours, so each frame is quantised first:
exactly, when it has no more than 256 distinct colours (flat graphics stay
crisp), or by median cut over a 15-bit histogram otherwise, optionally with
Floyd-Steinberg dithering. The indices are then compressed with GIF's LZW,
and the frame is written with its own palette and display time.

The file is streamed: `GifWriter` writes the header when opened, each frame
as it is added, and the trailer at `finish`, so a long recording holds one
frame in memory, not all of them. It streams to a `.partial` file beside the
target and renames it into place at `finish`, so the target is only ever a
whole GIF, an older file there survives a `cancel`, and a crash leaves a
`.partial` behind rather than a broken GIF under the real name.
"""

from std.ffi import external_call
from std.math import clamp, sqrt
from std.os import remove

from create._bytes import cstr

comptime _HISTOGRAM = 1 << 15
"""Buckets in the quantiser's histogram: five bits a channel."""
comptime _MAX_COLORS = 256
comptime _MAX_CODE_BITS = 12


def _key15(r: Int, g: Int, b: Int) -> Int:
    """The histogram bucket of a colour: the top five bits of each channel."""
    return ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)


struct _Box(Copyable, Movable):
    """A median-cut box: some of the histogram's populated buckets."""

    var keys: List[Int]
    var count: Int
    """Pixels in the box, the weight it is split and averaged by."""

    def __init__(out self, var keys: List[Int], counts: List[Int]):
        self.count = 0
        for key in keys:
            self.count += counts[key]
        self.keys = keys^


def _channel(key: Int, channel: Int) -> Int:
    """Channel `channel` (0 red, 1 green, 2 blue) of a bucket, 0 to 31."""
    return (key >> (10 - 5 * channel)) & 31


def _widest(box: _Box) -> Tuple[Int, Int]:
    """The channel `box` spans furthest, and that span."""
    var best_channel = 0
    var best_span = -1
    for channel in range(3):
        var low = 31
        var high = 0
        for key in box.keys:
            var value = _channel(key, channel)
            low = min(low, value)
            high = max(high, value)
        if high - low > best_span:
            best_span = high - low
            best_channel = channel
    return (best_channel, best_span)


def _median_cut(counts: List[Int]) -> List[_Box]:
    """Up to 256 boxes covering every populated bucket, each split from the
    one spanning furthest at the median of its pixels."""
    var populated = List[Int]()
    for key in range(_HISTOGRAM):
        if counts[key] > 0:
            populated.append(key)
    var boxes = List[_Box]()
    boxes.append(_Box(populated^, counts))
    while len(boxes) < _MAX_COLORS:
        var pick = -1
        var pick_score = 0
        var pick_channel = 0
        for i in range(len(boxes)):
            if len(boxes[i].keys) < 2:
                continue
            var widest = _widest(boxes[i])
            # Wide and well-used boxes first: a big span over few pixels
            # matters less than a moderate one over many.
            var score = widest[1] * Int(sqrt(Float64(boxes[i].count)) + 1.0)
            if widest[1] > 0 and score > pick_score:
                pick = i
                pick_score = score
                pick_channel = widest[0]
        if pick < 0:
            break
        var box = boxes.pop(pick)
        var by_value = List[List[Int]](length=32, fill=List[Int]())
        for key in box.keys:
            by_value[_channel(key, pick_channel)].append(key)
        var low = List[Int]()
        var high = List[Int]()
        var seen = 0
        for value in range(32):
            for key in by_value[value]:
                # Below the median, or the first bucket at all, goes low; so
                # neither half is ever empty.
                if seen * 2 < box.count or len(low) == 0:
                    low.append(key)
                    seen += counts[key]
                else:
                    high.append(key)
        if len(high) == 0:
            high.append(low.pop())
        boxes.append(_Box(low^, counts))
        boxes.append(_Box(high^, counts))
    return boxes^


struct _Quantised(Movable):
    var palette: List[UInt8]
    """Red, green and blue a colour, padded to a power of two colours."""
    var indices: List[UInt8]
    var bits: Int
    """log2 of the palette's length in colours, at least 1."""

    def __init__(out self, var palette: List[UInt8], var indices: List[UInt8]):
        var colors = len(palette) // 3
        self.bits = 1
        while (1 << self.bits) < colors:
            self.bits += 1
        while len(palette) < (1 << self.bits) * 3:
            palette.append(0)
        self.palette = palette^
        self.indices = indices^


def _exact(pixels: List[UInt8], count: Int) raises -> Optional[_Quantised]:
    """The frame's own colours as its palette, if it has no more than 256."""
    var index = Dict[Int, Int]()
    var palette = List[UInt8]()
    var indices = List[UInt8](length=count, fill=0)
    for i in range(count):
        var o = i * 4
        var rgb = (
            (Int(pixels[o]) << 16)
            | (Int(pixels[o + 1]) << 8)
            | Int(pixels[o + 2])
        )
        var found = index.get(rgb)
        if found:
            indices[i] = UInt8(found.value())
            continue
        if len(index) == _MAX_COLORS:
            return None
        index[rgb] = len(index)
        indices[i] = UInt8(len(index) - 1)
        palette.append(pixels[o])
        palette.append(pixels[o + 1])
        palette.append(pixels[o + 2])
    return _Quantised(palette^, indices^)


def _nearest(palette: List[UInt8], r: Int, g: Int, b: Int) -> Int:
    var best = 0
    var best_distance = Int.MAX
    for i in range(len(palette) // 3):
        var dr = r - Int(palette[i * 3])
        var dg = g - Int(palette[i * 3 + 1])
        var db = b - Int(palette[i * 3 + 2])
        var distance = dr * dr + dg * dg + db * db
        if distance < best_distance:
            best_distance = distance
            best = i
    return best


def quantise(
    pixels: List[UInt8], width: Int, height: Int, dither: Bool
) raises -> _Quantised:
    """Reduce `width` x `height` RGBA pixels (alpha ignored) to a palette of
    at most 256 colours and an index a pixel."""
    var count = width * height
    var exact = _exact(pixels, count)
    if exact:
        return exact.take()

    var counts = List[Int](length=_HISTOGRAM, fill=0)
    var sums = List[Int](length=_HISTOGRAM * 3, fill=0)
    for i in range(count):
        var o = i * 4
        var key = _key15(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
        counts[key] += 1
        sums[key * 3] += Int(pixels[o])
        sums[key * 3 + 1] += Int(pixels[o + 1])
        sums[key * 3 + 2] += Int(pixels[o + 2])

    # Each box's colour is the mean of the pixels in it, and every bucket
    # maps to its own box's colour.
    var boxes = _median_cut(counts)
    var palette = List[UInt8]()
    var lookup = List[Int](length=_HISTOGRAM, fill=-1)
    for b in range(len(boxes)):
        var r = 0
        var g = 0
        var bl = 0
        for key in boxes[b].keys:
            r += sums[key * 3]
            g += sums[key * 3 + 1]
            bl += sums[key * 3 + 2]
            lookup[key] = b
        var n = max(boxes[b].count, 1)
        palette.append(UInt8((r + n // 2) // n))
        palette.append(UInt8((g + n // 2) // n))
        palette.append(UInt8((bl + n // 2) // n))

    var indices = List[UInt8](length=count, fill=0)
    if not dither:
        for i in range(count):
            var o = i * 4
            indices[i] = UInt8(
                lookup[
                    _key15(
                        Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])
                    )
                ]
            )
        return _Quantised(palette^, indices^)

    # Floyd-Steinberg: each pixel's rounding error is spread over the pixels
    # right of and below it, so a smooth ramp becomes a fine mix of palette
    # colours rather than bands. A dithered colour can land in a bucket no
    # pixel had, so a bucket's nearest colour is found when first needed.
    var error = List[Float64](length=(width + 2) * 2 * 3, fill=0.0)
    for y in range(height):
        var row = (y % 2) * (width + 2) * 3
        var next = ((y + 1) % 2) * (width + 2) * 3
        for x in range(width + 2):
            for c in range(3):
                error[next + x * 3 + c] = 0.0
        for x in range(width):
            var o = (y * width + x) * 4
            var wanted = List[Int](length=3, fill=0)
            for c in range(3):
                var value = (
                    Float64(pixels[o + c]) + error[row + (x + 1) * 3 + c]
                )
                wanted[c] = Int(clamp(value, 0.0, 255.0) + 0.5)
            var key = _key15(wanted[0], wanted[1], wanted[2])
            if lookup[key] < 0:
                lookup[key] = _nearest(
                    palette,
                    (key >> 10) * 8 + 4,
                    ((key >> 5) & 31) * 8 + 4,
                    (key & 31) * 8 + 4,
                )
            var chosen = lookup[key]
            indices[y * width + x] = UInt8(chosen)
            for c in range(3):
                var off = Float64(wanted[c] - Int(palette[chosen * 3 + c]))
                error[row + (x + 2) * 3 + c] += off * 7.0 / 16.0
                error[next + x * 3 + c] += off * 3.0 / 16.0
                error[next + (x + 1) * 3 + c] += off * 5.0 / 16.0
                error[next + (x + 2) * 3 + c] += off * 1.0 / 16.0
    return _Quantised(palette^, indices^)


struct _BitWriter(Movable):
    """Codes packed least significant bit first, as GIF packs them."""

    var bytes: List[UInt8]
    var _accumulator: Int
    var _filled: Int

    def __init__(out self):
        self.bytes = List[UInt8]()
        self._accumulator = 0
        self._filled = 0

    def write(mut self, code: Int, width: Int):
        self._accumulator |= code << self._filled
        self._filled += width
        while self._filled >= 8:
            self.bytes.append(UInt8(self._accumulator & 0xFF))
            self._accumulator >>= 8
            self._filled -= 8

    def finish(deinit self) -> List[UInt8]:
        """The bytes, the last one padded with zero bits."""
        var bytes = self.bytes^
        if self._filled > 0:
            bytes.append(UInt8(self._accumulator & 0xFF))
        return bytes^


def lzw_encode(indices: List[UInt8], min_code_size: Int) raises -> List[UInt8]:
    """`indices` compressed with GIF's LZW, as the code stream's bytes.

    Code widths grow as the classic encoders grow them: a code is written at
    the current width, and the width steps up once the next code to be
    assigned no longer fits it. A full table of 4096 codes is cleared.
    """
    var clear = 1 << min_code_size
    var end = clear + 1
    var out = _BitWriter()
    var width = min_code_size + 1
    var next = end + 1
    var table = Dict[Int, Int]()
    out.write(clear, width)
    if len(indices) == 0:
        out.write(end, width)
        return out^.finish()
    var prefix = Int(indices[0])
    for i in range(1, len(indices)):
        var symbol = Int(indices[i])
        var key = (prefix << 8) | symbol
        var found = table.get(key)
        if found:
            prefix = found.value()
            continue
        out.write(prefix, width)
        if next > (1 << width) - 1 and width < _MAX_CODE_BITS:
            width += 1
        if next < (1 << _MAX_CODE_BITS):
            table[key] = next
            next += 1
        else:
            out.write(clear, width)
            table = Dict[Int, Int]()
            next = end + 1
            width = min_code_size + 1
        prefix = symbol
    out.write(prefix, width)
    if next > (1 << width) - 1 and width < _MAX_CODE_BITS:
        width += 1
    out.write(end, width)
    return out^.finish()


def _u16(mut bytes: List[UInt8], value: Int):
    bytes.append(UInt8(value & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))


def encode_frame(
    pixels: List[UInt8], width: Int, height: Int, dither: Bool
) raises -> List[UInt8]:
    """A whole-image GIF frame of `width` x `height` RGBA pixels: its
    descriptor, its own palette and its compressed indices, but not the
    delay, which `GifWriter.write_frame` puts in front of it."""
    var q = quantise(pixels, width, height, dither)
    var bytes = List[UInt8]()
    bytes.append(0x2C)  # image descriptor
    _u16(bytes, 0)
    _u16(bytes, 0)
    _u16(bytes, width)
    _u16(bytes, height)
    bytes.append(UInt8(0x80 | (q.bits - 1)))  # a local colour table
    bytes += q.palette.copy()
    var min_code_size = max(2, q.bits)
    bytes.append(UInt8(min_code_size))
    var data = lzw_encode(q.indices, min_code_size)
    var at = 0
    while at < len(data):
        var size = min(255, len(data) - at)
        bytes.append(UInt8(size))
        for i in range(size):
            bytes.append(data[at + i])
        at += size
    bytes.append(0)  # the data's terminator
    return bytes^


struct GifWriter(Movable):
    """An animated GIF being written, looping forever when played."""

    var _file: FileHandle
    var path: String
    """Where the GIF ends up; it is written to `path + ".partial"` until
    `finish`."""
    var width: Int
    var height: Int
    var frames: Int
    """Frames written so far."""

    def __init__(out self, path: String, width: Int, height: Int) raises:
        if width <= 0 or height <= 0:
            raise Error("cannot record a GIF with no area: " + path)
        if width > 65535 or height > 65535:
            raise Error("a GIF is at most 65535 pixels a side: " + path)
        self._file = open(path + ".partial", "w")
        self.path = path
        self.width = width
        self.height = height
        self.frames = 0
        var header = List[UInt8]()
        for c in "GIF89a".as_bytes():
            header.append(c)
        _u16(header, width)
        _u16(header, height)
        header.append(0)  # no global colour table: each frame has its own
        header.append(0)  # background colour
        header.append(0)  # pixel aspect ratio
        # The NETSCAPE2.0 extension: loop forever.
        header.append(0x21)
        header.append(0xFF)
        header.append(11)
        for c in "NETSCAPE2.0".as_bytes():
            header.append(c)
        header.append(3)
        header.append(1)
        _u16(header, 0)
        header.append(0)
        self._file.write_bytes(Span(header))

    def write_frame(mut self, frame: List[UInt8], delay: Int) raises:
        """Write a frame from `encode_frame`, shown for `delay` hundredths of
        a second."""
        var control = List[UInt8]()
        control.append(0x21)  # graphic control extension
        control.append(0xF9)
        control.append(4)
        control.append(0x04)  # dispose: leave the frame in place
        _u16(control, max(delay, 0))
        control.append(0)  # no transparent colour
        control.append(0)
        self._file.write_bytes(Span(control))
        self._file.write_bytes(Span(frame))
        self.frames += 1

    def finish(mut self) raises:
        """Write the trailer, close the file and move it to `path`, replacing
        any file there."""
        var trailer: List[UInt8] = [0x3B]
        self._file.write_bytes(Span(trailer))
        self._file.close()
        var partial = cstr(self.path + ".partial")
        var final = cstr(self.path)
        # The standard library has no rename; C's replaces the target in one
        # step, as it is in the same folder.
        var failed = external_call["rename", Int32](
            partial.unsafe_ptr(), final.unsafe_ptr()
        )
        _ = partial^
        _ = final^
        if failed != 0:
            raise Error(
                "could not move the finished recording into place: " + self.path
            )

    def cancel(mut self) raises:
        """Close and delete the file, leaving `path` as it was."""
        self._file.close()
        remove(self.path + ".partial")
