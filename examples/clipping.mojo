from create import *

comptime LINES = 24
comptime LINE_HEIGHT = 28.0


@fieldwise_init
struct Clipping(Program):
    """Three uses of `canvas.clip`: a panel whose list scrolls under its
    edges, a star-shaped window onto turning stripes, and fog everywhere
    except around the mouse."""

    var panel: Rectangle
    var window: Polygon

    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Clipping:
        return Clipping(
            Rectangle((-200, 0), 260, 360),
            Polygon.star((200, 0), 170, 75, 5),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(40, 44, 60))
        var t = context.time.elapsed

        # A list scrolling through a panel: rows enter and leave at its edges.
        canvas.fill(Color(24, 26, 36))
        canvas.rectangle(self.panel)
        with canvas.clip(self.panel):
            var scroll = (t * 40.0) % (LINES * LINE_HEIGHT)
            canvas.text_color(Color.WHITE)
            for i in range(LINES * 2):
                var y = 200.0 - Float64(i) * LINE_HEIGHT + scroll
                canvas.text(
                    "Row " + String(i % LINES + 1), (self.panel.position.x, y)
                )

        # Stripes seen through a star: the clip stays put while they turn.
        with canvas.clip(self.window):
            canvas.outline_enabled(False)
            with canvas.transform(translate(200.0, 0.0) @ rotate(t * 0.5)):
                for i in range(-10, 11):
                    canvas.fill(Color.ORANGE if i % 2 == 0 else Color.PURPLE)
                    canvas.rectangle((Float64(i) * 24, 0), 24, 500)

        # Fog with a hole in it, wherever the mouse is.
        with canvas.clip(Circle(context.input.mouse, 120), invert=True):
            canvas.background(Color(0, 0, 0, 140))


def main() raises:
    run[Clipping]("Clipping", width=800, height=600, mode=WindowMode.FULLSCREEN)
