from std.math import floor

from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from .key import Key, _KeyBits


struct Input(Copyable, Movable):
    """Keyboard and mouse state for one frame, read as `context.input`.

    The whole input surface — there are no event callbacks, because every
    window event either lands on a field here or is already reflected in
    `Canvas` (`canvas.width`/`height` are rebuilt every frame, so a resize needs
    no notification of its own).

    A field on `Context` rather than a parameter of its own, alongside `time`
    and for the same reason: both are readings the loop takes each frame, and
    reaching them the same way is one thing less to remember. It is the loop's
    own `Input`, not a copy — held keys and buttons persist in it from frame to
    frame, and `_new_frame` clears only the edges. So read it and don't write
    it: a write to held state carries into the next frame.

    Being a plain struct, it is also how input becomes scriptable: a test fills
    in `context.input` and calls `step` directly, driving click- or key-driven behaviour
    with no window involved.

    `mouse` is in screen coordinates, so it is negative left of and below the
    origin — camera-independent, since the loop folds a frame's events before
    the `Canvas` (and any `Camera` it sets) exists. Convert with
    `Camera.to_world` where a program uses one. It and `mouse_press_pos` are
    `Point2D` because they are locations; `wheel` stays a `Vector2D` because a
    scroll delta is a displacement.
    """

    var mouse_x: Int
    var mouse_y: Int
    var mouse: Point2D
    var mouse_pressed: Bool
    var mouse_button: Int
    # This frame's scroll delta — zeroed at the start of every frame, same
    # lifecycle as the just-pressed/just-released key bits.
    var wheel: Vector2D
    # World position at the most recent press this frame. Captured at the
    # MouseButtonDown event itself rather than read off `mouse`, because a
    # MouseMoved later in the same frame would otherwise overwrite it before
    # a program ever sees where the click actually started.
    var mouse_press_pos: Point2D
    var _held_keys: _KeyBits
    var _just_pressed: _KeyBits
    var _just_released: _KeyBits
    # Mouse buttons are a handful of small ints (1..5), not the ~500-wide
    # keycode space `_KeyBits` is sized for — a plain bitmask is enough.
    var _held_buttons: Int
    var _pressed_buttons: Int
    var _released_buttons: Int

    def __init__(out self):
        self.mouse_x = 0
        self.mouse_y = 0
        self.mouse = Point2D(0, 0)
        self.mouse_pressed = False
        self.mouse_button = 0
        self.wheel = Vector2D(0, 0)
        self.mouse_press_pos = Point2D(0, 0)
        self._held_keys = _KeyBits()
        self._just_pressed = _KeyBits()
        self._just_released = _KeyBits()
        self._held_buttons = 0
        self._pressed_buttons = 0
        self._released_buttons = 0

    def _new_frame(mut self):
        """Clears the per-frame edge state: just-pressed/released keys and
        buttons, and the scroll delta. Called once per frame before events are
        processed, so a press held across frames stays in `_held_keys`/
        `_held_buttons` but drops out of the "just" bits after the frame it
        happened in."""
        self._just_pressed.clear_all()
        self._just_released.clear_all()
        self.wheel = Vector2D(0, 0)
        self._pressed_buttons = 0
        self._released_buttons = 0

    def _set_mouse(mut self, x: Float64, y: Float64):
        """Record a screen-space pointer position.

        The single writer of `mouse`, `mouse_x` and `mouse_y`, so the three
        event arms that report a position cannot disagree about which of them
        a position updates. Screen space is centred, so both coordinates go
        negative and the Int forms floor rather than truncate — truncation
        would round the left and bottom halves of the screen the wrong way.
        """
        self.mouse = Point2D(x, y)
        self.mouse_x = Int(floor(x))
        self.mouse_y = Int(floor(y))

    def _check(self, key: String, bits: _KeyBits) -> Bool:
        """Resolve a key name against `bits`.

        Accepts a single character (`"a"`, `"7"`, `"/"`) or a named key
        (`"up"`, `"space"`, `"f1"`). Case is folded, so `"A"` and `"a"` are the
        same key — a key is a physical thing and shift is queried separately.

        A bare modifier name matches either side (`"ctrl"` is left or right),
        with `"left_ctrl"`/`"right_ctrl"` and friends to tell them apart. An
        unknown name is `False` rather than an error, so a typo is a key that
        never fires.
        """
        var k = key.lower()

        # Single printable char — SDL keycode == ASCII for a-z, 0-9, punctuation
        if key.byte_length() == 1:
            return bits.test(ord(k))

        # Modifier keys — bare name matches either side
        if k == "ctrl":
            return bits.test(Key.LEFT_CTRL) or bits.test(Key.RIGHT_CTRL)
        if k == "left_ctrl":
            return bits.test(Key.LEFT_CTRL)
        if k == "right_ctrl":
            return bits.test(Key.RIGHT_CTRL)
        if k == "shift":
            return bits.test(Key.LEFT_SHIFT) or bits.test(Key.RIGHT_SHIFT)
        if k == "left_shift":
            return bits.test(Key.LEFT_SHIFT)
        if k == "right_shift":
            return bits.test(Key.RIGHT_SHIFT)
        if k == "alt":
            return bits.test(Key.LEFT_ALT) or bits.test(Key.RIGHT_ALT)
        if k == "left_alt":
            return bits.test(Key.LEFT_ALT)
        if k == "right_alt":
            return bits.test(Key.RIGHT_ALT)
        if k == "super":
            return bits.test(Key.LEFT_SUPER) or bits.test(Key.RIGHT_SUPER)
        if k == "left_super":
            return bits.test(Key.LEFT_SUPER)
        if k == "right_super":
            return bits.test(Key.RIGHT_SUPER)

        var code = Key.from_name(k)
        if code == -1:
            return False
        return bits.test(code)

    def is_key_down(self, keycode: Int) -> Bool:
        """Whether this key is held right now — true every frame it stays
        down, which is what continuous movement wants."""
        return self._held_keys.test(keycode)

    def is_key_down(self, key: String) -> Bool:
        """Whether this key is held right now. See `_check` for the names."""
        return self._check(key, self._held_keys)

    def just_pressed(self, keycode: Int) -> Bool:
        """Whether this key went down this frame — true once per press."""
        return self._just_pressed.test(keycode)

    def just_pressed(self, key: String) -> Bool:
        """Whether this key went down this frame. See `_check` for the names."""
        return self._check(key, self._just_pressed)

    def just_released(self, keycode: Int) -> Bool:
        """Whether this key came up this frame — true once per release."""
        return self._just_released.test(keycode)

    def just_released(self, key: String) -> Bool:
        """Whether this key came up this frame. See `_check` for the names."""
        return self._check(key, self._just_released)

    def is_mouse_down(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button is held right now.

        Defaults to `MouseButton.LEFT`, so the common case needs no argument.
        Name the rest through `MouseButton` rather than passing a raw int — the
        numbering is not what anyone guesses (`RIGHT` is 3, not 2).
        """
        return (self._held_buttons & (1 << button)) != 0

    def mouse_just_pressed(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button went down this frame — true once per
        click. `mouse_press_pos` is where it happened."""
        return (self._pressed_buttons & (1 << button)) != 0

    def mouse_just_released(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button came up this frame — true once."""
        return (self._released_buttons & (1 << button)) != 0


struct MouseButton:
    """Names for `is_mouse_down`/`mouse_just_pressed`/`mouse_just_released`.

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
