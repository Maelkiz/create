from create import *


@fieldwise_init
struct Sketch(Program):
    @staticmethod
    def create(mut ctx: Context) raises -> Sketch:
        return Sketch()

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color.WHITE)
        canvas.outline(Color.GREEN, thickness=3)
        canvas.corner_radius(10)

        var circle = Circle((-100, 0), 50)
        var triangle = Triangle((0, -100), (50, -250), (150, -150))
        var rectangle = Rectangle((-250, 150), 100, 100)
        var line = Line((-250, 150), triangle.center())

        canvas.fill(Color.BLUE)
        canvas.circle(circle)

        canvas.line(line)

        canvas.fill(Color.RED)
        canvas.rectangle(rectangle)

        canvas.fill(Color.BLACK)
        canvas.triangle(triangle)

        canvas.text_color(Color.BLACK)
        canvas.font_size(54)
        canvas.text("Create!", 50, 100)


def main() raises:
    run[Sketch]("Example Sketch", 800, 600)
