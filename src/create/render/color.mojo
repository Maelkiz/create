from std.math import min, max, abs


def _channel(v: Float64) -> UInt8:
    """Round a 0..1 channel to a byte, clamped."""
    return UInt8(Int(min(max(v, 0.0), 1.0) * 255.0 + 0.5))


def _linear(v: UInt8) -> Float64:
    """Undo the sRGB transfer curve for one channel."""
    var c = Float64(Int(v)) / 255.0
    if c <= 0.03928:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def _hex_digit(byte: UInt8) -> Int:
    """One hex digit's value, or -1 if the byte is not a hex digit."""
    var c = Int(byte)
    if c >= 48 and c <= 57:  # '0'-'9'
        return c - 48
    if c >= 97 and c <= 102:  # 'a'-'f'
        return c - 87
    if c >= 65 and c <= 70:  # 'A'-'F'
        return c - 55
    return -1


def _mix(a: UInt8, b: UInt8, t: Float64) -> UInt8:
    var fa = Float64(Int(a))
    var fb = Float64(Int(b))
    return UInt8(Int(fa + (fb - fa) * t + 0.5))


struct Color(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    def __init__(out self, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255):
        self.r = r
        self.g = g
        self.b = b
        self.a = a

    def __init__(out self, gray: UInt8):
        self = Color(gray, gray, gray)

    def __eq__(self, other: Color) -> Bool:
        return (
            self.r == other.r
            and self.g == other.g
            and self.b == other.b
            and self.a == other.a
        )

    def __ne__(self, other: Color) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Color(", self.r, ", ", self.g, ", ", self.b, ", ", self.a, ")"
        )

    def luminance(self) -> Float64:
        """WCAG relative luminance, 0.0 (black) to 1.0 (white).

        Answers "is this background light or dark" — the usual caller picks
        black or white text against it, with 0.18 as the crossover.
        """
        return (
            0.2126 * _linear(self.r)
            + 0.7152 * _linear(self.g)
            + 0.0722 * _linear(self.b)
        )

    def to_hsv(self) -> Tuple[Float64, Float64, Float64]:
        """Inverse of `hsv`: hue in degrees, saturation and value in 0..1.

        Hue is 0.0 for grays, which have none.
        """
        var r = Float64(Int(self.r)) / 255.0
        var g = Float64(Int(self.g)) / 255.0
        var b = Float64(Int(self.b)) / 255.0
        var mx = max(r, max(g, b))
        var mn = min(r, min(g, b))
        var d = mx - mn
        var h = 0.0
        if d > 0.0:
            if mx == r:
                h = 60.0 * ((g - b) / d)
            elif mx == g:
                h = 60.0 * ((b - r) / d + 2.0)
            else:
                h = 60.0 * ((r - g) / d + 4.0)
            if h < 0.0:
                h += 360.0
        var s = 0.0 if mx == 0.0 else d / mx
        return (h, s, mx)

    def over(self, dst: Color) -> Color:
        """Composite this color over `dst`, source-over.

        `self.a` decides how much of `self` shows through. Compositing over an
        opaque color yields an opaque color, so this is what a canvas fill does
        against the framebuffer.
        """
        if self.a == 255:
            return self
        if self.a == 0:
            return dst
        var a = Int(self.a)
        var ia = 255 - a
        return Color(
            UInt8((Int(self.r) * a + Int(dst.r) * ia) // 255),
            UInt8((Int(self.g) * a + Int(dst.g) * ia) // 255),
            UInt8((Int(self.b) * a + Int(dst.b) * ia) // 255),
            UInt8(a + Int(dst.a) * ia // 255),
        )

    def with_alpha(self, a: UInt8) -> Color:
        """This color at a different opacity, 0 (invisible) to 255 (opaque).

        The RGB channels are carried over untouched, so a named constant or a
        computed color stays spelled once: `Color.RED.with_alpha(128)` rather
        than respelling all three channels to change the fourth.
        """
        return Color(self.r, self.g, self.b, a)

    @staticmethod
    def hex(rgb: Int) -> Color:
        """Build a color from a packed literal: `Color.hex(0x336699)`."""
        return Color(
            UInt8((rgb >> 16) & 0xFF),
            UInt8((rgb >> 8) & 0xFF),
            UInt8(rgb & 0xFF),
        )

    @staticmethod
    def hex(code: String) raises -> Color:
        """Build a color from a CSS hex string: `Color.hex("#336699")`.

        Accepts `#rgb`, `#rgba`, `#rrggbb` and `#rrggbbaa`; the leading `#` is
        optional and case does not matter. The short forms double each digit,
        as CSS does, so `"#f80"` is `"#ff8800"`. Alpha defaults to opaque.

        This is the form to paste into from a design tool, and the only one
        that carries alpha in a single token. `hex(Int)` stays the form for a
        literal written in source, since a parse can raise and so cannot run
        at compile time.

        Raises:
            If the string is not one of the four accepted lengths, or holds a
            character that is not a hex digit.
        """
        var bytes = code.as_bytes()
        var start = 0
        if len(bytes) > 0 and bytes[0] == 35:  # '#'
            start = 1
        var count = len(bytes) - start
        if count != 3 and count != 4 and count != 6 and count != 8:
            raise Error(
                "Color.hex: expected 3, 4, 6 or 8 hex digits, got '",
                code,
                "'",
            )
        var digits = List[Int]()
        for i in range(start, len(bytes)):
            var d = _hex_digit(bytes[i])
            if d < 0:
                raise Error("Color.hex: not a hex color: '", code, "'")
            digits.append(d)

        if count <= 4:
            var a = 255 if count == 3 else digits[3] * 17
            return Color(
                UInt8(digits[0] * 17),
                UInt8(digits[1] * 17),
                UInt8(digits[2] * 17),
                UInt8(a),
            )
        var a = 255 if count == 6 else (digits[6] << 4) | digits[7]
        return Color(
            UInt8((digits[0] << 4) | digits[1]),
            UInt8((digits[2] << 4) | digits[3]),
            UInt8((digits[4] << 4) | digits[5]),
            UInt8(a),
        )

    @staticmethod
    def hsv(h: Float64, s: Float64, v: Float64) -> Color:
        """Build a color from hue in degrees (wraps) and saturation/value in 0..1.

        Hue cycling is the point: `Color.hsv(Float64(frame) % 360.0, 1.0, 1.0)`
        sweeps the spectrum without hand-mixing channels.
        """
        var hh = h - 360.0 * Float64(Int(h / 360.0))
        if hh < 0.0:
            hh += 360.0
        var ss = min(max(s, 0.0), 1.0)
        var vv = min(max(v, 0.0), 1.0)
        var c = vv * ss
        var seg = hh / 60.0
        var f = seg - 2.0 * Float64(Int(seg / 2.0))
        var x = c * (1.0 - abs(f - 1.0))
        var m = vv - c
        var r = 0.0
        var g = 0.0
        var b = 0.0
        if hh < 60.0:
            r = c
            g = x
        elif hh < 120.0:
            r = x
            g = c
        elif hh < 180.0:
            g = c
            b = x
        elif hh < 240.0:
            g = x
            b = c
        elif hh < 300.0:
            r = x
            b = c
        else:
            r = c
            b = x
        return Color(_channel(r + m), _channel(g + m), _channel(b + m))

    @staticmethod
    def lerp(a: Color, b: Color, t: Float64) -> Color:
        """Blend two colors, `t` clamped to 0..1. Mixes in sRGB, like a paint
        program's gradient — not perceptually uniform, but what the eye expects
        from two swatches."""
        var tt = min(max(t, 0.0), 1.0)
        return Color(
            _mix(a.r, b.r, tt),
            _mix(a.g, b.g, tt),
            _mix(a.b, b.b, tt),
            _mix(a.a, b.a, tt),
        )

    comptime TRANSPARENT = Color(0, 0, 0, 0)

    comptime BLACK = Color(0)
    comptime WHITE = Color(255)

    comptime DARK_GRAY = Color(0x40)
    comptime GRAY = Color(0x80)
    comptime LIGHT_GRAY = Color(0xC0)

    comptime RED = Color(255, 0, 0)
    comptime GREEN = Color(0, 255, 0)
    comptime BLUE = Color(0, 0, 255)

    comptime CYAN = Color(0, 255, 255)
    comptime MAGENTA = Color(255, 0, 255)
    comptime YELLOW = Color(255, 255, 0)

    comptime ORANGE = Color(255, 128, 0)
    comptime PINK = Color(255, 128, 192)
    comptime PURPLE = Color(128, 0, 255)
    comptime BROWN = Color(128, 64, 0)
