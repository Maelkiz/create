from create import *


def without_last_character(text: String) -> String:
    """Drop the last character, not the last byte: `text` is UTF-8, so an
    accented letter can be two bytes and must go as one."""
    var bytes = text.as_bytes()
    var end = len(bytes)
    if end == 0:
        return text
    end -= 1
    # Continuation bytes are 0b10xxxxxx; the character starts before them.
    while end > 0 and (bytes[end] & 0xC0) == 0x80:
        end -= 1
    return String(text[byte=0:end])


@fieldwise_init
struct TypingTest(Program):
    var phrases: List[String]
    var phrase: Int
    var typed: String
    var started_at: Float64
    var keystrokes: Int
    var mistakes: Int
    var result: String

    @staticmethod
    def create(mut context: Context) raises -> TypingTest:
        return TypingTest(
            phrases=[
                "the quick brown fox jumps over the lazy dog",
                "a café naïve enough to serve crème brûlée",
                "sphinx of black quartz, judge my vow",
            ],
            phrase=0,
            typed="",
            started_at=0,
            keystrokes=0,
            mistakes=0,
            result="",
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(30, 30, 40))
        ref target = self.phrases[self.phrase]
        var finished = self.typed == target

        if finished:
            if context.input.key_pressed(Key.ENTER):
                self.phrase = (self.phrase + 1) % len(self.phrases)
                self.typed = ""
                self.result = ""
        else:
            # `text` is this frame's typed characters; editing keys come
            # through `key_typed`, so holding Backspace keeps deleting.
            for character in context.input.text.codepoint_slices():
                if not self.typed:
                    self.started_at = context.time.elapsed
                    self.keystrokes = 0
                    self.mistakes = 0
                self.typed += character
                self.keystrokes += 1
                if not target.startswith(self.typed):
                    self.mistakes += 1
            if context.input.key_typed(Key.BACKSPACE):
                self.typed = without_last_character(self.typed)
            if self.typed == target:
                self.result = self.score(target, context.time.elapsed)

        var on_track = target.startswith(self.typed)
        var caret = "_" if Int(context.time.elapsed * 2) % 2 == 0 else " "

        canvas.text_align(Align.CENTER)
        canvas.font_size(28)
        canvas.text_color(Color(200, 200, 220))
        canvas.text(target, (0, 60))
        canvas.text_color(
            Color(120, 200, 140) if on_track else Color(230, 90, 90)
        )
        canvas.text(self.typed + ("" if finished else caret), (0, 0))

        canvas.font_size(20)
        canvas.text_color(Color(150, 150, 170))
        if finished:
            canvas.text(self.result, (0, -80))
            canvas.text("Enter for the next phrase", (0, -120))
        else:
            canvas.text("Type the phrase above", (0, -80))

    def score(self, target: String, now: Float64) -> String:
        """Words per minute counts five characters as a word, the standard
        typing-test measure; accuracy is the share of keystrokes that were
        right when typed, so a corrected mistake still counts against it."""
        var minutes = max(now - self.started_at, 0.001) / 60
        var characters = len(target.codepoint_slices())
        var wpm = Int(Float64(characters) / 5 / minutes)
        var accuracy = (
            100 * (self.keystrokes - self.mistakes) // max(self.keystrokes, 1)
        )
        return String(wpm, " wpm, ", accuracy, "% accuracy")


def main() raises:
    run[TypingTest]("Typing", width=900, height=600)
