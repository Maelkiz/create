from create import *


@fieldwise_init
struct Sketch(Program):
    @staticmethod
    def create(mut ctx: Context) raises -> Sketch:
        return Sketch()

    def render(self, mut frame: Frame) raises:
        frame.background(Color.WHITE)
        frame.outline(Color.GREEN, thickness=3)
        frame.corner_radius(10)

        var circle = Circle((-100, 0), 50)
        var triangle = Triangle((0, -100), (50, -250), (150, -150))
        var rectangle = Rectangle((-250, 150), 100, 100)
        var line = Line((-250, 150), triangle.center())

        frame.fill(Color.BLUE)
        frame.circle(circle)

        frame.line(line)

        frame.fill(Color.RED)
        frame.rectangle(rectangle)

        frame.fill(Color.BLACK)
        frame.triangle(triangle)

        frame.text_color(Color.BLACK)
        frame.font_size(54)
        frame.text("Create!", 50, 100)


def main() raises:
    run[Sketch]("Example Sketch", 800, 600)
