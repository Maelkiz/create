from create.math.vector2d import Vector2D

# SDL's axis numbering, as `GamepadAxisMoved` carries it.
comptime _LEFT_X = 0
comptime _LEFT_Y = 1
comptime _RIGHT_X = 2
comptime _RIGHT_Y = 3
comptime _LEFT_TRIGGER = 4
comptime _RIGHT_TRIGGER = 5


struct Gamepad(Copyable, ImplicitlyCopyable, Movable, Writable):
    """One gamepad's state for one frame, read as `context.input.gamepad(i)`.

    Buttons follow the key and mouse vocabulary: *down* is held right now,
    *pressed*/*released* are the edges, true only in the frame the button
    went down or came up. Name buttons through `GamepadButton`.

    Sticks are `Vector2D`s in screen orientation — y up, like every other
    direction in the library — inside the unit circle, so
    `position += pad.left_stick * speed * context.time.delta` moves at
    `speed` at full tilt and never faster on a diagonal. Each has a radial
    dead zone of `STICK_DEAD_ZONE`, rescaled so the stick still eases up
    from zero past it: a resting stick reads exactly `Vector2D.ZERO` rather
    than drifting. Triggers are 0 (released) to 1 (pulled all the way).

    A slot that holds no gamepad reads all zero and `connected` False, so a
    program can read player two's pad before one is plugged in.
    `connected_this_frame` and `disconnected_this_frame` are the edges of
    `connected`, true only in the frame the pad arrived or left — the frame
    to show "Player 2 joined" or to pause. In the frame a pad leaves, its
    slot still has its `name`, so the message can say which.
    """

    comptime STICK_DEAD_ZONE = 0.2
    """How far a stick moves before it reads anything, as a fraction of full
    tilt. A resting stick sits up to about a quarter of the way off centre on
    a worn pad; 0.2 hides that on most without making small moves sluggish.
    """

    var connected: Bool
    var connected_this_frame: Bool
    var disconnected_this_frame: Bool
    # The product name, e.g. "Xbox Series X Controller" — for showing, not
    # for telling layouts apart. Empty when SDL knows none.
    var name: String
    var left_stick: Vector2D
    var right_stick: Vector2D
    var left_trigger: Float64
    var right_trigger: Float64
    # The most recent button pressed, compared against `GamepadButton` (-1
    # before any, since `SOUTH` is 0). Kept until the next press.
    var button: Int
    # SDL's id for the pad in this slot, matched against each event's.
    var _id: Int
    # Stick positions as reported, before the dead zone, y up. The dead zone
    # needs both axes of a stick and each event brings one.
    var _left_raw: Vector2D
    var _right_raw: Vector2D
    # 26 buttons, one bit each.
    var _held_buttons: Int
    var _pressed_buttons: Int
    var _released_buttons: Int

    def __init__(out self):
        self.connected = False
        self.connected_this_frame = False
        self.disconnected_this_frame = False
        self.name = ""
        self.left_stick = Vector2D.ZERO
        self.right_stick = Vector2D.ZERO
        self.left_trigger = 0.0
        self.right_trigger = 0.0
        self.button = -1
        self._id = -1
        self._left_raw = Vector2D.ZERO
        self._right_raw = Vector2D.ZERO
        self._held_buttons = 0
        self._pressed_buttons = 0
        self._released_buttons = 0

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "Gamepad(connected=",
            self.connected,
            ", connected_this_frame=",
            self.connected_this_frame,
            ", disconnected_this_frame=",
            self.disconnected_this_frame,
            ", name=",
            repr(self.name),
            ", left_stick=",
            self.left_stick,
            ", right_stick=",
            self.right_stick,
            ", left_trigger=",
            self.left_trigger,
            ", right_trigger=",
            self.right_trigger,
            ", button=",
            self.button,
            ")",
        )

    def button_down(self, button: Int) -> Bool:
        """Whether this button is held right now."""
        return (self._held_buttons & (1 << button)) != 0

    def button_pressed(self, button: Int) -> Bool:
        """Whether this button went down this frame — true once per press."""
        return (self._pressed_buttons & (1 << button)) != 0

    def button_released(self, button: Int) -> Bool:
        """Whether this button came up this frame — true once per release."""
        return (self._released_buttons & (1 << button)) != 0

    def _new_frame(mut self):
        self._pressed_buttons = 0
        self._released_buttons = 0
        self.connected_this_frame = False
        self.disconnected_this_frame = False
        # Kept through the frame the pad left in, for saying which one.
        if not self.connected:
            self.name = ""

    def _press(mut self, button: Int):
        if not self.button_down(button):
            self.button = button
            self._held_buttons |= 1 << button
            self._pressed_buttons |= 1 << button

    def _release(mut self, button: Int):
        self._held_buttons &= ~(1 << button)
        self._released_buttons |= 1 << button

    def _set_axis(mut self, axis: Int, value: Float64):
        """Record one axis reading, `value` as `GamepadAxisMoved` carries it:
        y positive down, which is flipped here."""
        if axis == _LEFT_X:
            self._left_raw.x = value
        elif axis == _LEFT_Y:
            self._left_raw.y = -value
        elif axis == _RIGHT_X:
            self._right_raw.x = value
        elif axis == _RIGHT_Y:
            self._right_raw.y = -value
        elif axis == _LEFT_TRIGGER:
            self.left_trigger = value
        elif axis == _RIGHT_TRIGGER:
            self.right_trigger = value
        self.left_stick = _dead_zone(self._left_raw)
        self.right_stick = _dead_zone(self._right_raw)


def _dead_zone(raw: Vector2D) -> Vector2D:
    """`raw` with the inner `STICK_DEAD_ZONE` cut out and the rest stretched
    back over 0..1, capped at the unit circle — a square-gated stick reaches
    past it on the diagonals."""
    var length = raw.mag()
    if length <= Gamepad.STICK_DEAD_ZONE:
        return Vector2D.ZERO
    var scaled = min(
        (length - Gamepad.STICK_DEAD_ZONE) / (1.0 - Gamepad.STICK_DEAD_ZONE),
        1.0,
    )
    return raw * (scaled / length)
