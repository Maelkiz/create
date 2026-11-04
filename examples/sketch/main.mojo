"""A first sketch: shapes built as values and drawn with `canvas.draw`, each in
the fill set before it, all with one outline.
"""

from create import *


@fieldwise_init
struct Sketch(Program):
    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Sketch:
        return Sketch()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color(240, 236, 222))
        canvas.outline(Color(40, 40, 44), thickness=3)

        var circle = Circle((-100, 0), 50)
        var triangle = Triangle(
            (0, -100), (50, -250), (150, -150), corner_radius=10
        )
        var rectangle = Rectangle((-250, 150), 100, 100, corner_radius=10)
        var line = Line((-250, 150), triangle.center())

        canvas.fill(Color(98, 104, 168))
        canvas.draw(circle)

        canvas.draw(line)

        canvas.fill(Color(226, 46, 56))
        canvas.draw(rectangle)

        canvas.fill(Color(201, 140, 150))
        canvas.draw(triangle)

        canvas.text_color(Color(40, 40, 44))
        canvas.font_size(54)
        canvas.text("Create!", (50, 100))


def main() raises:
    run[Sketch]("Sketch", width=800, height=600)
