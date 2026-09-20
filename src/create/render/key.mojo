struct Key:
    """Named SDL keycodes for the `Int` overloads of the `Input` queries.

    The string overloads cover the same keys by name and read better --
    `input.is_key_down("up")` -- so these are for a program storing a keycode
    in a field or a table, where a name would have to be re-parsed each frame.
    `from_name` is the one mapping between the two forms.
    """

    # Modifier keys
    comptime LEFT_CTRL = 1073742048
    comptime RIGHT_CTRL = 1073742052
    comptime LEFT_SHIFT = 1073742049
    comptime RIGHT_SHIFT = 1073742053
    comptime LEFT_ALT = 1073742050
    comptime RIGHT_ALT = 1073742054
    comptime LEFT_SUPER = 1073742051
    comptime RIGHT_SUPER = 1073742055

    # Arrow keys
    comptime UP = 1073741906
    comptime DOWN = 1073741905
    comptime LEFT = 1073741904
    comptime RIGHT = 1073741903

    # Navigation
    comptime INSERT = 1073741897
    comptime HOME = 1073741898
    comptime PAGE_UP = 1073741899
    comptime PAGE_DOWN = 1073741902
    comptime END = 1073741901

    # Common keys
    comptime ENTER = 13
    comptime ESCAPE = 27
    comptime BACKSPACE = 8
    comptime TAB = 9
    comptime SPACE = 32
    comptime DELETE = 127
    comptime CAPS_LOCK = 1073741881

    # Function keys
    comptime F1 = 1073741882
    comptime F2 = 1073741883
    comptime F3 = 1073741884
    comptime F4 = 1073741885
    comptime F5 = 1073741886
    comptime F6 = 1073741887
    comptime F7 = 1073741888
    comptime F8 = 1073741889
    comptime F9 = 1073741890
    comptime F10 = 1073741891
    comptime F11 = 1073741892
    comptime F12 = 1073741893

    # Letter keys (SDL keycodes match lowercase ASCII)
    comptime A = 97
    comptime B = 98
    comptime C = 99
    comptime D = 100
    comptime E = 101
    comptime F = 102
    comptime G = 103
    comptime H = 104
    comptime I = 105
    comptime J = 106
    comptime K = 107
    comptime L = 108
    comptime M = 109
    comptime N = 110
    comptime O = 111
    comptime P = 112
    comptime Q = 113
    comptime R = 114
    comptime S = 115
    comptime T = 116
    comptime U = 117
    comptime V = 118
    comptime W = 119
    comptime X = 120
    comptime Y = 121
    comptime Z = 122

    # Number keys
    comptime NUM_0 = 48
    comptime NUM_1 = 49
    comptime NUM_2 = 50
    comptime NUM_3 = 51
    comptime NUM_4 = 52
    comptime NUM_5 = 53
    comptime NUM_6 = 54
    comptime NUM_7 = 55
    comptime NUM_8 = 56
    comptime NUM_9 = 57

    # Single source for named-key lookups — Input._check calls this instead of
    # holding its own copy of these codes. Returns -1 for an unknown name.
    @staticmethod
    def from_name(name: String) -> Int:
        if name == "up":
            return Key.UP
        if name == "down":
            return Key.DOWN
        if name == "left":
            return Key.LEFT
        if name == "right":
            return Key.RIGHT

        if name == "insert":
            return Key.INSERT
        if name == "home":
            return Key.HOME
        if name == "page_up":
            return Key.PAGE_UP
        if name == "page_down":
            return Key.PAGE_DOWN
        if name == "end":
            return Key.END

        if name == "enter":
            return Key.ENTER
        if name == "escape":
            return Key.ESCAPE
        if name == "backspace":
            return Key.BACKSPACE
        if name == "tab":
            return Key.TAB
        if name == "space":
            return Key.SPACE
        if name == "delete":
            return Key.DELETE
        if name == "caps_lock":
            return Key.CAPS_LOCK

        if name == "f1":
            return Key.F1
        if name == "f2":
            return Key.F2
        if name == "f3":
            return Key.F3
        if name == "f4":
            return Key.F4
        if name == "f5":
            return Key.F5
        if name == "f6":
            return Key.F6
        if name == "f7":
            return Key.F7
        if name == "f8":
            return Key.F8
        if name == "f9":
            return Key.F9
        if name == "f10":
            return Key.F10
        if name == "f11":
            return Key.F11
        if name == "f12":
            return Key.F12

        return -1


struct _KeyBits(Copyable, Movable):
    """512-bit membership set over keycodes: printable ASCII (0-127) map
    directly, SDL scancode-based keys (arrows, F-keys, modifiers, nav —
    all >= 1 << 30, spanning a ~230-wide band) map via an offset into the
    upper half of the same word array."""

    var _words: InlineArray[UInt64, 8]

    def __init__(out self):
        self._words = InlineArray[UInt64, 8](fill=0)

    def _index(self, keycode: Int) -> Int:
        if keycode >= 1073741824:
            return 256 + (keycode - 1073741824)
        return keycode

    def set(mut self, keycode: Int):
        var i = self._index(keycode)
        self._words[i // 64] |= UInt64(1) << UInt64(i % 64)

    def clear(mut self, keycode: Int):
        var i = self._index(keycode)
        self._words[i // 64] &= ~(UInt64(1) << UInt64(i % 64))

    def test(self, keycode: Int) -> Bool:
        var i = self._index(keycode)
        return (self._words[i // 64] & (UInt64(1) << UInt64(i % 64))) != 0

    def clear_all(mut self):
        self._words = InlineArray[UInt64, 8](fill=0)
