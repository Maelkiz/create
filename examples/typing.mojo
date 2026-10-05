from create import *


def characters(text: String) -> List[String]:
    """`text` split into characters, not bytes: an accented letter is two
    bytes of UTF-8 but one character to type."""
    var result = List[String]()
    for character in text.codepoint_slices():
        result.append(String(character))
    return result^


@fieldwise_init
struct TypingTest(Program):
    var phrases: List[String]
    var phrase: Int
    var typed: EditableText
    var started_at: Float64
    var keystrokes: Int
    var mistakes: Int
    var result: String

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> TypingTest:
        return TypingTest(
            phrases=[
                "the quick brown fox jumps over the lazy dog",
                "a café naïve enough to serve crème brûlée",
                "sphinx of black quartz, judge my vow",
            ],
            phrase=0,
            typed=EditableText(),
            started_at=0,
            keystrokes=0,
            mistakes=0,
            result="",
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # Set every frame; the window is only told when it changes.
        context.title(
            "Typing — phrase "
            + String(self.phrase + 1)
            + " of "
            + String(len(self.phrases))
        )
        canvas.background(Color(30, 30, 40))
        var target = characters(self.phrases[self.phrase])
        var finished = self.typed.text == self.phrases[self.phrase]

        if finished:
            if context.input.key_pressed(Key.ENTER):
                self.phrase = (self.phrase + 1) % len(self.phrases)
                self.typed.text = ""
                self.result = ""
        else:
            self.count_keystrokes(context, target)
            # Typed text, Backspace, Delete and the arrow keys, all in one.
            self.typed.update(context.input)
            if self.typed.text == self.phrases[self.phrase]:
                self.result = self.score(len(target), context.time.elapsed)

        # Both lines start at the same left edge, so each typed letter sits
        # under the one it should match.
        canvas.font_size(28)
        canvas.text_align(Align.LEFT)
        var left = -canvas.text_width(self.phrases[self.phrase]) / 2
        canvas.text_color(Color(200, 200, 220))
        canvas.text(self.phrases[self.phrase], (left, 60))

        var x = left
        var typed = characters(self.typed.text)
        for i in range(len(typed)):
            var right = i < len(target) and typed[i] == target[i]
            canvas.text_color(
                Color(120, 200, 140) if right else Color(230, 90, 90)
            )
            canvas.text(typed[i], (x, 0))
            x += canvas.text_width(typed[i])

        if not finished and Int(context.time.elapsed * 2) % 2 == 0:
            var caret_x = left + canvas.text_width(self.typed.before_caret())
            canvas.outline(Color.WHITE, thickness=2)
            canvas.line((caret_x, -16), (caret_x, 16))

        canvas.font_size(20)
        canvas.text_align(Align.CENTER)
        canvas.text_color(Color(150, 150, 170))
        if finished:
            canvas.text(self.result, (0, -80))
            canvas.text("Enter for the next phrase", (0, -120))
        else:
            canvas.text("Type the phrase above", (0, -80))

    def count_keystrokes(mut self, context: Context, target: List[String]):
        """Count this frame's typed characters, and those that went in wrong
        for where the caret put them. The clock starts on the first."""
        var typed = characters(context.input.text)
        if not typed:
            return
        if not self.typed.text:
            self.started_at = context.time.elapsed
            self.keystrokes = 0
            self.mistakes = 0
        var position = len(characters(self.typed.before_caret()))
        for i in range(len(typed)):
            self.keystrokes += 1
            var at = position + i
            if at >= len(target) or typed[i] != target[at]:
                self.mistakes += 1

    def score(self, characters: Int, now: Float64) -> String:
        """Words per minute counts five characters as a word, the standard
        typing-test measure; accuracy is the share of keystrokes that were
        right when typed, so a corrected mistake still counts against it."""
        var minutes = max(now - self.started_at, 0.001) / 60
        var wpm = Int(Float64(characters) / 5 / minutes)
        var accuracy = (
            100 * (self.keystrokes - self.mistakes) // max(self.keystrokes, 1)
        )
        return String(wpm, " wpm, ", accuracy, "% accuracy")


def main() raises:
    run[TypingTest]("Typing", width=900, height=600)
