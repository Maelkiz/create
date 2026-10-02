struct GamepadButton:
    """Names for `Gamepad.button_down`/`button_pressed`/`button_released`.

    Matches SDL's own button numbering. The face buttons are named by
    position, not label, because the labels disagree: `SOUTH` is Xbox A,
    PlayStation Cross and Nintendo B alike — the button a thumb rests on, so
    the one to confirm with. `BACK`/`START` are the two small centre buttons
    (View/Menu, Share/Options, -/+), `GUIDE` the logo button between them.
    """

    comptime SOUTH = 0
    comptime EAST = 1
    comptime WEST = 2
    comptime NORTH = 3
    comptime BACK = 4
    comptime GUIDE = 5
    comptime START = 6
    comptime LEFT_STICK = 7
    """Clicking the left stick in."""
    comptime RIGHT_STICK = 8
    comptime LEFT_SHOULDER = 9
    comptime RIGHT_SHOULDER = 10
    comptime DPAD_UP = 11
    comptime DPAD_DOWN = 12
    comptime DPAD_LEFT = 13
    comptime DPAD_RIGHT = 14
    comptime MISC_1 = 15
    """The extra centre button: Xbox Share, PlayStation microphone, Switch
    capture."""
    comptime RIGHT_PADDLE_1 = 16
    comptime LEFT_PADDLE_1 = 17
    comptime RIGHT_PADDLE_2 = 18
    comptime LEFT_PADDLE_2 = 19
    comptime TOUCHPAD = 20
    """Pressing the PlayStation touchpad."""
    comptime MISC_2 = 21
    comptime MISC_3 = 22
    comptime MISC_4 = 23
    comptime MISC_5 = 24
    comptime MISC_6 = 25
