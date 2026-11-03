struct Key(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A key, what the `Input` queries take: `input.key_down(Key.UP)`.

    `from_name` maps a key's name (`"up"`, `"page_up"`, `"a"`) to it, for a
    binding read from a file; a misspelled constant fails to compile, where
    a name could only fail to match.

    A wrapped SDL keycode rather than a bare `Int`, so a stray number cannot
    be passed where a key is expected. `Key(keycode)` names any key SDL can
    send, the ones without a constant included.

    `NONE` is no key (SDL's unknown keycode), what `Input.key` reads before
    any press; it is never down.

    `CTRL`, `SHIFT`, `ALT` and `SUPER` are either side of a modifier: down
    while the left or the right one is. They are queries only, never a key
    SDL sends, so `Input.key` is always the side that was pressed.
    """

    var value: Int

    comptime NONE = Key(0)

    # Modifier keys
    comptime LEFT_CTRL = Key(1073742048)
    comptime RIGHT_CTRL = Key(1073742052)
    comptime LEFT_SHIFT = Key(1073742049)
    comptime RIGHT_SHIFT = Key(1073742053)
    comptime LEFT_ALT = Key(1073742050)
    comptime RIGHT_ALT = Key(1073742054)
    comptime LEFT_SUPER = Key(1073742051)
    comptime RIGHT_SUPER = Key(1073742055)

    # Either side of a modifier. Negative, so no SDL keycode collides.
    comptime CTRL = Key(-1)
    comptime SHIFT = Key(-2)
    comptime ALT = Key(-3)
    comptime SUPER = Key(-4)

    # Arrow keys
    comptime UP = Key(1073741906)
    comptime DOWN = Key(1073741905)
    comptime LEFT = Key(1073741904)
    comptime RIGHT = Key(1073741903)

    # Navigation
    comptime INSERT = Key(1073741897)
    comptime HOME = Key(1073741898)
    comptime PAGE_UP = Key(1073741899)
    comptime PAGE_DOWN = Key(1073741902)
    comptime END = Key(1073741901)

    # Common keys
    comptime ENTER = Key(13)
    comptime ESCAPE = Key(27)
    comptime BACKSPACE = Key(8)
    comptime TAB = Key(9)
    comptime SPACE = Key(32)
    comptime DELETE = Key(127)
    comptime CAPS_LOCK = Key(1073741881)

    # Function keys
    comptime F1 = Key(1073741882)
    comptime F2 = Key(1073741883)
    comptime F3 = Key(1073741884)
    comptime F4 = Key(1073741885)
    comptime F5 = Key(1073741886)
    comptime F6 = Key(1073741887)
    comptime F7 = Key(1073741888)
    comptime F8 = Key(1073741889)
    comptime F9 = Key(1073741890)
    comptime F10 = Key(1073741891)
    comptime F11 = Key(1073741892)
    comptime F12 = Key(1073741893)

    # Letter keys (SDL keycodes match lowercase ASCII)
    comptime A = Key(97)
    comptime B = Key(98)
    comptime C = Key(99)
    comptime D = Key(100)
    comptime E = Key(101)
    comptime F = Key(102)
    comptime G = Key(103)
    comptime H = Key(104)
    comptime I = Key(105)
    comptime J = Key(106)
    comptime K = Key(107)
    comptime L = Key(108)
    comptime M = Key(109)
    comptime N = Key(110)
    comptime O = Key(111)
    comptime P = Key(112)
    comptime Q = Key(113)
    comptime R = Key(114)
    comptime S = Key(115)
    comptime T = Key(116)
    comptime U = Key(117)
    comptime V = Key(118)
    comptime W = Key(119)
    comptime X = Key(120)
    comptime Y = Key(121)
    comptime Z = Key(122)

    # Digits on the main row, named in words as the punctuation keys are.
    comptime ZERO = Key(48)
    comptime ONE = Key(49)
    comptime TWO = Key(50)
    comptime THREE = Key(51)
    comptime FOUR = Key(52)
    comptime FIVE = Key(53)
    comptime SIX = Key(54)
    comptime SEVEN = Key(55)
    comptime EIGHT = Key(56)
    comptime NINE = Key(57)

    # Punctuation: the unshifted character, so `MINUS` is also `_` with
    # shift held. Positions follow the keyboard layout, as letters do.
    comptime MINUS = Key(45)
    comptime EQUALS = Key(61)
    comptime LEFT_BRACKET = Key(91)
    comptime RIGHT_BRACKET = Key(93)
    comptime BACKSLASH = Key(92)
    comptime SEMICOLON = Key(59)
    comptime APOSTROPHE = Key(39)
    comptime GRAVE = Key(96)
    comptime COMMA = Key(44)
    comptime PERIOD = Key(46)
    comptime SLASH = Key(47)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: Key) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Key) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        comptime for i in range(len(_NAMED_KEYS)):
            comptime entry = _NAMED_KEYS[i]
            if self == entry[0]:
                writer.write("Key.", entry[1])
                return
        writer.write("Key(", self.value, ")")

    @staticmethod
    def from_name(name: String) -> Optional[Key]:
        """The key whose constant is `name`, case folded: `"up"`,
        `"page_up"`, `"f1"`, `"left_ctrl"`, `"a"`, `"zero"`, `"slash"`.
        A single character is the key that types it unshifted, so `"/"`,
        `"7"` and `"A"` work too. `None` for an unknown name.
        """
        var upper = name.upper()
        comptime for i in range(len(_NAMED_KEYS)):
            comptime entry = _NAMED_KEYS[i]
            if upper == entry[1]:
                return entry[0]
        if name.byte_length() == 1:
            return Key(ord(name.lower()))
        return None


# Every `Key` constant with its name, for printing and `from_name`.
comptime _NAMED_KEYS = [
    (Key.NONE, StaticString("NONE")),
    (Key.LEFT_CTRL, StaticString("LEFT_CTRL")),
    (Key.RIGHT_CTRL, StaticString("RIGHT_CTRL")),
    (Key.LEFT_SHIFT, StaticString("LEFT_SHIFT")),
    (Key.RIGHT_SHIFT, StaticString("RIGHT_SHIFT")),
    (Key.LEFT_ALT, StaticString("LEFT_ALT")),
    (Key.RIGHT_ALT, StaticString("RIGHT_ALT")),
    (Key.LEFT_SUPER, StaticString("LEFT_SUPER")),
    (Key.RIGHT_SUPER, StaticString("RIGHT_SUPER")),
    (Key.CTRL, StaticString("CTRL")),
    (Key.SHIFT, StaticString("SHIFT")),
    (Key.ALT, StaticString("ALT")),
    (Key.SUPER, StaticString("SUPER")),
    (Key.UP, StaticString("UP")),
    (Key.DOWN, StaticString("DOWN")),
    (Key.LEFT, StaticString("LEFT")),
    (Key.RIGHT, StaticString("RIGHT")),
    (Key.INSERT, StaticString("INSERT")),
    (Key.HOME, StaticString("HOME")),
    (Key.PAGE_UP, StaticString("PAGE_UP")),
    (Key.PAGE_DOWN, StaticString("PAGE_DOWN")),
    (Key.END, StaticString("END")),
    (Key.ENTER, StaticString("ENTER")),
    (Key.ESCAPE, StaticString("ESCAPE")),
    (Key.BACKSPACE, StaticString("BACKSPACE")),
    (Key.TAB, StaticString("TAB")),
    (Key.SPACE, StaticString("SPACE")),
    (Key.DELETE, StaticString("DELETE")),
    (Key.CAPS_LOCK, StaticString("CAPS_LOCK")),
    (Key.F1, StaticString("F1")),
    (Key.F2, StaticString("F2")),
    (Key.F3, StaticString("F3")),
    (Key.F4, StaticString("F4")),
    (Key.F5, StaticString("F5")),
    (Key.F6, StaticString("F6")),
    (Key.F7, StaticString("F7")),
    (Key.F8, StaticString("F8")),
    (Key.F9, StaticString("F9")),
    (Key.F10, StaticString("F10")),
    (Key.F11, StaticString("F11")),
    (Key.F12, StaticString("F12")),
    (Key.A, StaticString("A")),
    (Key.B, StaticString("B")),
    (Key.C, StaticString("C")),
    (Key.D, StaticString("D")),
    (Key.E, StaticString("E")),
    (Key.F, StaticString("F")),
    (Key.G, StaticString("G")),
    (Key.H, StaticString("H")),
    (Key.I, StaticString("I")),
    (Key.J, StaticString("J")),
    (Key.K, StaticString("K")),
    (Key.L, StaticString("L")),
    (Key.M, StaticString("M")),
    (Key.N, StaticString("N")),
    (Key.O, StaticString("O")),
    (Key.P, StaticString("P")),
    (Key.Q, StaticString("Q")),
    (Key.R, StaticString("R")),
    (Key.S, StaticString("S")),
    (Key.T, StaticString("T")),
    (Key.U, StaticString("U")),
    (Key.V, StaticString("V")),
    (Key.W, StaticString("W")),
    (Key.X, StaticString("X")),
    (Key.Y, StaticString("Y")),
    (Key.Z, StaticString("Z")),
    (Key.ZERO, StaticString("ZERO")),
    (Key.ONE, StaticString("ONE")),
    (Key.TWO, StaticString("TWO")),
    (Key.THREE, StaticString("THREE")),
    (Key.FOUR, StaticString("FOUR")),
    (Key.FIVE, StaticString("FIVE")),
    (Key.SIX, StaticString("SIX")),
    (Key.SEVEN, StaticString("SEVEN")),
    (Key.EIGHT, StaticString("EIGHT")),
    (Key.NINE, StaticString("NINE")),
    (Key.MINUS, StaticString("MINUS")),
    (Key.EQUALS, StaticString("EQUALS")),
    (Key.LEFT_BRACKET, StaticString("LEFT_BRACKET")),
    (Key.RIGHT_BRACKET, StaticString("RIGHT_BRACKET")),
    (Key.BACKSLASH, StaticString("BACKSLASH")),
    (Key.SEMICOLON, StaticString("SEMICOLON")),
    (Key.APOSTROPHE, StaticString("APOSTROPHE")),
    (Key.GRAVE, StaticString("GRAVE")),
    (Key.COMMA, StaticString("COMMA")),
    (Key.PERIOD, StaticString("PERIOD")),
    (Key.SLASH, StaticString("SLASH")),
]


struct _KeySet(Copyable, Movable):
    """A set of keys, held as a short list.

    SDL3 keycodes are sparse 32-bit values: a character key is its Unicode
    codepoint (anything up to 0x10FFFF on a non-Latin layout), a
    non-character key is its scancode with bit 30 set (scancodes run to
    511, AltGr's `MODE` among them), and a few extended keys carry bit 29.
    No fixed-width bitmask covers that without being huge, while only a
    handful of keys are ever down at once — so a linear scan over a list
    stays cheap and accepts every keycode SDL can send.
    """

    var _keys: List[Key]

    def __init__(out self):
        self._keys = []

    def set(mut self, key: Key):
        if not self._has(key):
            self._keys.append(key)

    def clear(mut self, key: Key):
        for i in range(len(self._keys)):
            if self._keys[i] == key:
                _ = self._keys.pop(i)
                return

    def test(self, key: Key) -> Bool:
        """Whether `key` is in the set; an either-side modifier is if
        either of its sides is."""
        if key == Key.CTRL:
            return self._has(Key.LEFT_CTRL) or self._has(Key.RIGHT_CTRL)
        if key == Key.SHIFT:
            return self._has(Key.LEFT_SHIFT) or self._has(Key.RIGHT_SHIFT)
        if key == Key.ALT:
            return self._has(Key.LEFT_ALT) or self._has(Key.RIGHT_ALT)
        if key == Key.SUPER:
            return self._has(Key.LEFT_SUPER) or self._has(Key.RIGHT_SUPER)
        return self._has(key)

    def _has(self, key: Key) -> Bool:
        for held in self._keys:
            if held == key:
                return True
        return False

    def clear_all(mut self):
        self._keys.clear()
