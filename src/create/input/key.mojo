struct Key(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A key, for the `Key` overloads of the `Input` queries.

    The string overloads cover the same keys by name and read better --
    `input.key_down("up")` -- so these are for a program storing a key in a
    field or a table, where a name would have to be re-parsed each frame.
    `from_name` is the one mapping between the two forms.

    A wrapped SDL keycode rather than a bare `Int`, so a stray number cannot
    be passed where a key is expected. `Key(keycode)` names any key SDL can
    send, the ones without a constant included.
    """

    var value: Int

    # Modifier keys
    comptime LEFT_CTRL = Key(1073742048)
    comptime RIGHT_CTRL = Key(1073742052)
    comptime LEFT_SHIFT = Key(1073742049)
    comptime RIGHT_SHIFT = Key(1073742053)
    comptime LEFT_ALT = Key(1073742050)
    comptime RIGHT_ALT = Key(1073742054)
    comptime LEFT_SUPER = Key(1073742051)
    comptime RIGHT_SUPER = Key(1073742055)

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

    # Number keys
    comptime NUM_0 = Key(48)
    comptime NUM_1 = Key(49)
    comptime NUM_2 = Key(50)
    comptime NUM_3 = Key(51)
    comptime NUM_4 = Key(52)
    comptime NUM_5 = Key(53)
    comptime NUM_6 = Key(54)
    comptime NUM_7 = Key(55)
    comptime NUM_8 = Key(56)
    comptime NUM_9 = Key(57)

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
        `"page_up"`, `"f1"`, `"left_ctrl"`, `"a"`, `"num_0"`. `None` for an
        unknown name.

        Single source for named-key lookups: `Input`'s string overloads call
        this instead of holding their own copy of the codes.
        """
        var upper = name.upper()
        comptime for i in range(len(_NAMED_KEYS)):
            comptime entry = _NAMED_KEYS[i]
            if upper == entry[1]:
                return entry[0]
        return None


# Every `Key` constant with its name, for printing and `from_name`.
comptime _NAMED_KEYS = [
    (Key.LEFT_CTRL, StaticString("LEFT_CTRL")),
    (Key.RIGHT_CTRL, StaticString("RIGHT_CTRL")),
    (Key.LEFT_SHIFT, StaticString("LEFT_SHIFT")),
    (Key.RIGHT_SHIFT, StaticString("RIGHT_SHIFT")),
    (Key.LEFT_ALT, StaticString("LEFT_ALT")),
    (Key.RIGHT_ALT, StaticString("RIGHT_ALT")),
    (Key.LEFT_SUPER, StaticString("LEFT_SUPER")),
    (Key.RIGHT_SUPER, StaticString("RIGHT_SUPER")),
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
    (Key.NUM_0, StaticString("NUM_0")),
    (Key.NUM_1, StaticString("NUM_1")),
    (Key.NUM_2, StaticString("NUM_2")),
    (Key.NUM_3, StaticString("NUM_3")),
    (Key.NUM_4, StaticString("NUM_4")),
    (Key.NUM_5, StaticString("NUM_5")),
    (Key.NUM_6, StaticString("NUM_6")),
    (Key.NUM_7, StaticString("NUM_7")),
    (Key.NUM_8, StaticString("NUM_8")),
    (Key.NUM_9, StaticString("NUM_9")),
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
        if not self.test(key):
            self._keys.append(key)

    def clear(mut self, key: Key):
        for i in range(len(self._keys)):
            if self._keys[i] == key:
                _ = self._keys.pop(i)
                return

    def test(self, key: Key) -> Bool:
        for held in self._keys:
            if held == key:
                return True
        return False

    def clear_all(mut self):
        self._keys.clear()
