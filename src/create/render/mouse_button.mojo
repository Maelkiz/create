struct MouseButton:
    """Names for `is_mouse_down`/`was_mouse_pressed`/`was_mouse_released`.

    Matches SDL's own button numbering, not named after it: `BACK`/`FORWARD`
    are the side thumb buttons (SDL's X1/X2) — named for what a mouse driver
    or browser calls them, not SDL's internal label, since nobody looks at
    their mouse and thinks "that's my X1 button."
    """

    comptime LEFT = 1
    comptime MIDDLE = 2
    comptime RIGHT = 3
    comptime BACK = 4
    comptime FORWARD = 5
