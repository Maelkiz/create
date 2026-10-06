from .input import Input
from .key import Key


struct EditableText(Copyable, Movable, Writable):
    """A line of text being typed into, with a caret: the state of a text
    field, without its look.

    The program owns one per field and feeds it the frame's input, then draws
    `text` itself — `before_caret` measured with `canvas.text_width` puts the
    caret after the right character:

    ```mojo
    self.name.update(context.input)                 # in update
    canvas.text_align(Align.LEFT)
    canvas.text(self.name.text, (left, 0))
    var caret_x = left + canvas.text_width(self.name.before_caret())
    canvas.line((caret_x, -20), (caret_x, 20))
    ```

    `update` inserts `input.text` at the caret, and handles Backspace and
    Delete either side of it, Left and Right to move it by one character, and
    Home and End. All of them repeat while held. Enter is left to the program,
    which decides what submitting means.

    Every edit and move is by whole characters, so a multi-byte UTF-8
    character is never split. `text` is a plain field: reading it is the
    point, and assigning it (`self.name.text = ""`) is safe, since the caret
    is kept inside it and on a character boundary.
    """

    var text: String
    """What has been typed so far, UTF-8."""
    var _caret: Int
    """Byte offset of the caret into `text`. Read through `_caret_offset`,
    which clamps it, because `text` can be reassigned under it."""

    def __init__(out self, text: String = ""):
        """Start with `text` already typed, the caret after it."""
        self.text = text
        self._caret = text.byte_length()

    def update(mut self, input: Input):
        """Apply one frame's typing: the typed text first, then the editing
        keys, as within a frame typing mostly comes before a correction."""
        if input.text:
            self.insert(input.text)
        if input.key_typed(Key.BACKSPACE):
            self.delete_backward()
        if input.key_typed(Key.DELETE):
            self.delete_forward()
        if input.key_typed(Key.LEFT):
            self.move_left()
        if input.key_typed(Key.RIGHT):
            self.move_right()
        if input.key_typed(Key.HOME):
            self._caret = 0
        if input.key_typed(Key.END):
            self._caret = self.text.byte_length()

    def before_caret(self) -> String:
        """The text left of the caret — what to measure to place it."""
        return String(self.text[byte = 0 : self._caret_offset()])

    def after_caret(self) -> String:
        """The text right of the caret."""
        return String(self.text[byte = self._caret_offset() :])

    def insert(mut self, typed: String):
        """Insert `typed` at the caret and move the caret past it."""
        var before = self.before_caret()
        self.text = before + typed + self.after_caret()
        self._caret = before.byte_length() + typed.byte_length()

    def delete_backward(mut self):
        """Delete the character left of the caret, as Backspace does."""
        var end = self._caret_offset()
        var start = self._previous_boundary(end)
        self._remove(start, end)

    def delete_forward(mut self):
        """Delete the character right of the caret, as Delete does."""
        var start = self._caret_offset()
        self._remove(start, self._next_boundary(start))

    def move_left(mut self):
        """Move the caret one character left, stopping at the start."""
        self._caret = self._previous_boundary(self._caret_offset())

    def move_right(mut self):
        """Move the caret one character right, stopping at the end."""
        self._caret = self._next_boundary(self._caret_offset())

    def _remove(mut self, start: Int, end: Int):
        self.text = String(self.text[byte=0:start]) + String(
            self.text[byte=end:]
        )
        self._caret = start

    def _caret_offset(self) -> Int:
        """The caret clamped into `text` and moved back onto the start of a
        character, whatever `text` was reassigned to."""
        var offset = min(max(self._caret, 0), self.text.byte_length())
        while offset > 0 and self._continues(offset):
            offset -= 1
        return offset

    def _continues(self, offset: Int) -> Bool:
        """Whether the byte at `offset` continues a character rather than
        starting one: UTF-8 continuation bytes are 0b10xxxxxx."""
        if offset >= self.text.byte_length():
            return False
        return (self.text.as_bytes()[offset] & 0xC0) == 0x80

    def _previous_boundary(self, offset: Int) -> Int:
        if offset == 0:
            return 0
        var previous = offset - 1
        while previous > 0 and self._continues(previous):
            previous -= 1
        return previous

    def _next_boundary(self, offset: Int) -> Int:
        var end = self.text.byte_length()
        if offset >= end:
            return end
        var following = offset + 1
        while following < end and self._continues(following):
            following += 1
        return following

    def write_to[W: Writer](self, mut writer: W):
        # The caret is left out: it is private, and a byte offset besides.
        writer.write('EditableText(text="', self.text, '")')
