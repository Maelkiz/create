struct MouseButton(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A mouse button, for `mouse_down`/`mouse_pressed`/`mouse_released`.

    Matches SDL's own button numbering, not named after it: `BACK`/`FORWARD`
    are the side thumb buttons (SDL's X1/X2) — named for what a mouse driver
    or browser calls them, not SDL's internal label, since nobody looks at
    their mouse and thinks "that's my X1 button."

    A wrapped button number rather than a bare `Int`, like `Key`, so a stray
    number cannot be passed where a button is expected — the numbering is not
    what anyone guesses (`RIGHT` is 3, not 2). `MouseButton(n)` names a
    button past `FORWARD` on a mouse that has one.

    `NONE` is no button, what `Input.mouse_button` reads before any press;
    it is never down.
    """

    var value: Int

    comptime NONE = MouseButton(0)
    comptime LEFT = MouseButton(1)
    comptime MIDDLE = MouseButton(2)
    comptime RIGHT = MouseButton(3)
    comptime BACK = MouseButton(4)
    comptime FORWARD = MouseButton(5)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: MouseButton) -> Bool:
        return self.value == other.value

    def __ne__(self, other: MouseButton) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        if self == MouseButton.NONE:
            writer.write("MouseButton.NONE")
        elif self == MouseButton.LEFT:
            writer.write("MouseButton.LEFT")
        elif self == MouseButton.MIDDLE:
            writer.write("MouseButton.MIDDLE")
        elif self == MouseButton.RIGHT:
            writer.write("MouseButton.RIGHT")
        elif self == MouseButton.BACK:
            writer.write("MouseButton.BACK")
        elif self == MouseButton.FORWARD:
            writer.write("MouseButton.FORWARD")
        else:
            writer.write("MouseButton(", self.value, ")")

    def _bit(self) -> Int:
        """This button's bit in `Input`'s button masks; 0, never set, for
        `NONE` and for a number no mask can hold."""
        if 1 <= self.value < 64:
            return 1 << self.value
        return 0
