from std.math import floor

from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from .key import Key, _KeySet
from .mouse_button import MouseButton
from .gamepad import Gamepad


struct Input(Copyable, Movable):
    """Keyboard, mouse and gamepad state for one frame, read as
    `context.input`.

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
    `Camera.to_world` where a program uses one. It and
    `mouse_press_position` are `Point2D` because they are locations;
    `mouse_wheel` stays a `Vector2D` because a scroll delta is a displacement.

    Keys and mouse buttons share one vocabulary: *down* is held right now,
    true every frame it stays held (`key_down`, `mouse_down`);
    *pressed* and *released* are the edges, true only in the frame the key or
    button went down or came up (`key_pressed`, `mouse_released`).
    Unlike Processing, where `mousePressed` means held: here *pressed* is only
    ever the edge. Keys add *typed*: pressed, or auto-repeated while held
    (`key_typed`) — what an editing key like Backspace acts on.

    `text` is what those keys wrote, as characters rather than keys: shift,
    the keyboard layout and any IME already applied. A text field appends
    `text` and handles Backspace, Enter and the arrows through `key_typed`.

    Gamepads are read by player through `gamepad(player)`. Each pad takes the
    lowest free slot as it connects and keeps it until it disconnects, so
    unplugging player one leaves player two where they were.
    """

    # Keycode of the most recent key press, compared against `Key` (0 before
    # any). Kept until the next press, like `mouse_button`; auto-repeat of a
    # held key does not count as a press.
    var key: Int
    # The text typed this frame, UTF-8 — empty on most frames, several
    # characters when typing outpaces the frame rate. Zeroed every frame.
    var text: String
    var mouse_x: Int
    var mouse_y: Int
    var mouse: Point2D
    # The most recent button pressed, compared against `MouseButton` (0
    # before any). Kept until the next press.
    var mouse_button: Int
    # This frame's scroll delta — zeroed at the start of every frame, same
    # lifecycle as the pressed/released key bits.
    var mouse_wheel: Vector2D
    # World position at the most recent press this frame. Captured at the
    # MouseButtonDown event itself rather than read off `mouse`, because a
    # MouseMoved later in the same frame would otherwise overwrite it before
    # a program ever sees where the click actually started.
    var mouse_press_position: Point2D
    var _held_keys: _KeySet
    var _pressed_keys: _KeySet
    var _released_keys: _KeySet
    var _typed_keys: _KeySet
    # Mouse buttons are a handful of small ints (1..5), not the sparse 32-bit
    # keycode space `_KeySet` handles — a plain bitmask is enough.
    var _held_buttons: Int
    var _pressed_buttons: Int
    var _released_buttons: Int
    # One slot per player; a disconnected pad leaves a `Gamepad()` behind
    # for the next one to connect.
    var _gamepads: List[Gamepad]

    def __init__(out self):
        self.key = 0
        self.text = ""
        self.mouse_x = 0
        self.mouse_y = 0
        self.mouse = Point2D(0, 0)
        self.mouse_button = 0
        self.mouse_wheel = Vector2D(0, 0)
        self.mouse_press_position = Point2D(0, 0)
        self._held_keys = _KeySet()
        self._pressed_keys = _KeySet()
        self._released_keys = _KeySet()
        self._typed_keys = _KeySet()
        self._held_buttons = 0
        self._pressed_buttons = 0
        self._released_buttons = 0
        self._gamepads = []

    def _new_frame(mut self):
        """Clears the per-frame edge state: pressed/released/typed keys and
        buttons (gamepads' too), the typed text and the scroll delta. Called once per frame before events are
        processed, so a press held across frames stays in `_held_keys`/
        `_held_buttons` but drops out of the pressed bits after the frame it
        happened in."""
        self._pressed_keys.clear_all()
        self._released_keys.clear_all()
        self._typed_keys.clear_all()
        self.text = ""
        self.mouse_wheel = Vector2D(0, 0)
        self._pressed_buttons = 0
        self._released_buttons = 0
        for i in range(len(self._gamepads)):
            self._gamepads[i]._new_frame()

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

    def _check(self, key: String, bits: _KeySet) -> Bool:
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

    def key_down(self, keycode: Int) -> Bool:
        """Whether this key is held right now — true every frame it stays down.
        """
        return self._held_keys.test(keycode)

    def key_down(self, key: String) -> Bool:
        """Whether this key is held right now. See `_check` for the names."""
        return self._check(key, self._held_keys)

    def key_pressed(self, keycode: Int) -> Bool:
        """Whether this key went down this frame — true once per press."""
        return self._pressed_keys.test(keycode)

    def key_pressed(self, key: String) -> Bool:
        """Whether this key went down this frame. See `_check` for the names."""
        return self._check(key, self._pressed_keys)

    def key_released(self, keycode: Int) -> Bool:
        """Whether this key came up this frame — true once per release."""
        return self._released_keys.test(keycode)

    def key_released(self, key: String) -> Bool:
        """Whether this key came up this frame. See `_check` for the names."""
        return self._check(key, self._released_keys)

    def key_typed(self, keycode: Int) -> Bool:
        """Whether this key went down or auto-repeated this frame — true once
        per press, then at the system's repeat rate while held."""
        return self._typed_keys.test(keycode)

    def key_typed(self, key: String) -> Bool:
        """Whether this key went down or auto-repeated this frame. See
        `_check` for the names."""
        return self._check(key, self._typed_keys)

    def mouse_down(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button is held right now.

        Defaults to `MouseButton.LEFT`, so the common case needs no argument.
        Name the rest through `MouseButton` rather than passing a raw int — the
        numbering is not what anyone guesses (`RIGHT` is 3, not 2).
        """
        return (self._held_buttons & (1 << button)) != 0

    def mouse_pressed(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button went down this frame — true once per
        click. `mouse_press_position` is where it happened."""
        return (self._pressed_buttons & (1 << button)) != 0

    def mouse_released(self, button: Int = MouseButton.LEFT) -> Bool:
        """Whether this mouse button came up this frame — true once."""
        return (self._released_buttons & (1 << button)) != 0

    def gamepad(self, player: Int = 0) -> Gamepad:
        """The gamepad in slot `player` — player one is 0, the default, so a
        one-player program needs no argument.

        A slot no gamepad holds reads as a disconnected `Gamepad()`, all
        zero and nothing down, so this never fails and needs no check first.
        """
        if 0 <= player < len(self._gamepads):
            return self._gamepads[player]
        return Gamepad()

    def _gamepad_slot(self, id: Int) -> Int:
        """The slot of the connected pad SDL calls `id`, or -1."""
        for i in range(len(self._gamepads)):
            if self._gamepads[i].connected and self._gamepads[i]._id == id:
                return i
        return -1

    def _connect_gamepad(mut self, id: Int, name: String):
        if self._gamepad_slot(id) != -1:
            return
        var pad = Gamepad()
        pad.connected = True
        pad.connected_this_frame = True
        pad.name = name
        pad._id = id
        for i in range(len(self._gamepads)):
            if not self._gamepads[i].connected:
                # A pad that left this same frame still gets its edge.
                pad.disconnected_this_frame = self._gamepads[
                    i
                ].disconnected_this_frame
                self._gamepads[i] = pad^
                return
        self._gamepads.append(pad^)

    def _disconnect_gamepad(mut self, id: Int):
        var slot = self._gamepad_slot(id)
        if slot != -1:
            var pad = Gamepad()
            pad.disconnected_this_frame = True
            pad.name = self._gamepads[slot].name
            self._gamepads[slot] = pad^
