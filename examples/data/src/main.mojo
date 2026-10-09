"""A bar chart drawn from a CSV file, styled from a JSON one.

Both are loaded once in `create`: the table is kept and read every frame,
the style is read into plain fields. Edit either file and run it again.
"""

from create import *


@fieldwise_init
struct Chart(Program):
    var scores: Table
    var title: String
    var background: Color
    var bar: Color
    var best: Color
    var text: Color
    var show_level: Bool

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Chart:
        var scores = Table.load(source_path("../assets/scores.csv"))
        scores.sort("score", descending=True)

        var style = JSON.load(source_path("../assets/style.json"))
        var colors = style["colors"]
        return Chart(
            scores^,
            style["title"].string(),
            Color.hex(colors["background"].string()),
            Color.hex(colors["bar"].string()),
            Color.hex(colors["best"].string()),
            Color.hex(colors["text"].string()),
            style.get("show_level", False).bool(),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(self.background)
        canvas.text_color(self.text)

        canvas.font_size(32)
        canvas.text(self.title, (0, canvas.top() - 50))

        canvas.font_size(18)
        var labels = List[String]()
        var widest = 0.0
        for ref row in self.scores.rows():
            var label = row.string("score")
            if self.show_level:
                label += "  (level " + row.string("level") + ")"
            widest = max(widest, canvas.text_width(label))
            labels.append(label^)

        var top_score = self.scores.row(0).float("score")
        var row_height = (canvas.top() - canvas.bottom() - 160) / Float64(
            self.scores.row_count()
        )
        var bar_start = canvas.left() + 180
        var bar_room = canvas.right() - 40 - widest - 12 - bar_start

        canvas.outline_enabled(False)
        for i in range(self.scores.row_count()):
            ref row = self.scores.row(i)
            var y = canvas.top() - 120 - (Float64(i) + 0.5) * row_height
            var w = bar_room * row.float("score") / top_score

            canvas.fill(self.best if i == 0 else self.bar)
            canvas.rectangle((bar_start + w / 2, y), w, row_height * 0.7)

            with canvas.style(text_align=Align.RIGHT):
                canvas.text(row.string("name"), (bar_start - 16, y))
            with canvas.style(text_align=Align.LEFT):
                canvas.text(labels[i], (bar_start + w + 12, y))


def main() raises:
    run[Chart]("Data Example", width=960, height=540)
