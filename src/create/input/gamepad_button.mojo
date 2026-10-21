struct GamepadButton(
    Copyable, Equatable, ImplicitlyCopyable, Movable, Writable
):
    """A gamepad button, for `Gamepad.button_down`/`button_pressed`/
    `button_released`.

    Matches SDL's own button numbering. The face buttons are named by
    position, not label, because the labels disagree: `SOUTH` is Xbox A,
    PlayStation Cross and Nintendo B alike — the button a thumb rests on, so
    the one to confirm with. `BACK`/`START` are the two small centre buttons
    (View/Menu, Share/Options, -/+), `GUIDE` the logo button between them.

    A wrapped button number rather than a bare `Int`, like `Key`, so a stray
    number cannot be passed where a button is expected.

    `NONE` is no button, what `Gamepad.button` reads before any press (SDL's
    invalid button, since `SOUTH` is 0); it is never down.
    """

    var value: Int

    comptime NONE = GamepadButton(-1)
    comptime SOUTH = GamepadButton(0)
    comptime EAST = GamepadButton(1)
    comptime WEST = GamepadButton(2)
    comptime NORTH = GamepadButton(3)
    comptime BACK = GamepadButton(4)
    comptime GUIDE = GamepadButton(5)
    comptime START = GamepadButton(6)
    comptime LEFT_STICK = GamepadButton(7)
    """Clicking the left stick in."""
    comptime RIGHT_STICK = GamepadButton(8)
    comptime LEFT_SHOULDER = GamepadButton(9)
    comptime RIGHT_SHOULDER = GamepadButton(10)
    comptime DPAD_UP = GamepadButton(11)
    comptime DPAD_DOWN = GamepadButton(12)
    comptime DPAD_LEFT = GamepadButton(13)
    comptime DPAD_RIGHT = GamepadButton(14)
    comptime MISC_1 = GamepadButton(15)
    """The extra centre button: Xbox Share, PlayStation microphone, Switch
    capture."""
    comptime RIGHT_PADDLE_1 = GamepadButton(16)
    comptime LEFT_PADDLE_1 = GamepadButton(17)
    comptime RIGHT_PADDLE_2 = GamepadButton(18)
    comptime LEFT_PADDLE_2 = GamepadButton(19)
    comptime TOUCHPAD = GamepadButton(20)
    """Pressing the PlayStation touchpad."""
    comptime MISC_2 = GamepadButton(21)
    comptime MISC_3 = GamepadButton(22)
    comptime MISC_4 = GamepadButton(23)
    comptime MISC_5 = GamepadButton(24)
    comptime MISC_6 = GamepadButton(25)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: GamepadButton) -> Bool:
        return self.value == other.value

    def __ne__(self, other: GamepadButton) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        comptime for i in range(len(_NAMED_BUTTONS)):
            comptime entry = _NAMED_BUTTONS[i]
            if self == entry[0]:
                writer.write("GamepadButton.", entry[1])
                return
        writer.write("GamepadButton(", self.value, ")")

    def _bit(self) -> Int:
        """This button's bit in `Gamepad`'s button masks; 0, never set, for
        `NONE` and for a number no mask can hold."""
        if 0 <= self.value < 64:
            return 1 << self.value
        return 0


# Every `GamepadButton` constant with its name, for printing.
comptime _NAMED_BUTTONS = [
    (GamepadButton.NONE, StaticString("NONE")),
    (GamepadButton.SOUTH, StaticString("SOUTH")),
    (GamepadButton.EAST, StaticString("EAST")),
    (GamepadButton.WEST, StaticString("WEST")),
    (GamepadButton.NORTH, StaticString("NORTH")),
    (GamepadButton.BACK, StaticString("BACK")),
    (GamepadButton.GUIDE, StaticString("GUIDE")),
    (GamepadButton.START, StaticString("START")),
    (GamepadButton.LEFT_STICK, StaticString("LEFT_STICK")),
    (GamepadButton.RIGHT_STICK, StaticString("RIGHT_STICK")),
    (GamepadButton.LEFT_SHOULDER, StaticString("LEFT_SHOULDER")),
    (GamepadButton.RIGHT_SHOULDER, StaticString("RIGHT_SHOULDER")),
    (GamepadButton.DPAD_UP, StaticString("DPAD_UP")),
    (GamepadButton.DPAD_DOWN, StaticString("DPAD_DOWN")),
    (GamepadButton.DPAD_LEFT, StaticString("DPAD_LEFT")),
    (GamepadButton.DPAD_RIGHT, StaticString("DPAD_RIGHT")),
    (GamepadButton.MISC_1, StaticString("MISC_1")),
    (GamepadButton.RIGHT_PADDLE_1, StaticString("RIGHT_PADDLE_1")),
    (GamepadButton.LEFT_PADDLE_1, StaticString("LEFT_PADDLE_1")),
    (GamepadButton.RIGHT_PADDLE_2, StaticString("RIGHT_PADDLE_2")),
    (GamepadButton.LEFT_PADDLE_2, StaticString("LEFT_PADDLE_2")),
    (GamepadButton.TOUCHPAD, StaticString("TOUCHPAD")),
    (GamepadButton.MISC_2, StaticString("MISC_2")),
    (GamepadButton.MISC_3, StaticString("MISC_3")),
    (GamepadButton.MISC_4, StaticString("MISC_4")),
    (GamepadButton.MISC_5, StaticString("MISC_5")),
    (GamepadButton.MISC_6, StaticString("MISC_6")),
]
