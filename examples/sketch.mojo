from create import *


@fieldwise_init
struct Sketch(Program):
    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> Sketch:
        return Sketch()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        canvas.background(Color.WHITE)
        canvas.outline(Color.GREEN, thickness=3)

        var circle = Circle((-100, 0), 50)
        var triangle = Triangle(
            (0, -100), (50, -250), (150, -150), corner_radius=10
        )
        var rectangle = Rectangle((-250, 150), 100, 100, corner_radius=10)
        var line = Line((-250, 150), triangle.center())

        canvas.fill(Color.BLUE)
        canvas.draw(circle)

        canvas.draw(line)

        canvas.fill(Color.RED)
        canvas.draw(rectangle)

        canvas.fill(Color.BLACK)
        canvas.draw(triangle)

        canvas.text_color(Color.BLACK)
        canvas.font_size(54)
        canvas.text("Create!", (50, 100))


def main() raises:
    run[Sketch]("Example Sketch", width=800, height=600)
