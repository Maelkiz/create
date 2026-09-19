from create import *


@fieldwise_init
struct Sketch(Program):
    @staticmethod
    def create(mut ctx: Context) raises -> Sketch:
        return Sketch()

    def render(self, mut canvas: Canvas) raises:
        canvas.background(Color.WHITE)
        canvas.outline(Color.GREEN)

        canvas.fill(Color.RED)
        canvas.rectangle((-250, 150), 100, 100)

        canvas.fill(Color.BLUE)
        canvas.circle((-100, 0), 50)

        canvas.fill(Color.BLACK)
        canvas.triangle((0, -100), (50, -250), (150, -150))

        canvas.outline(thickness=3)
        canvas.line((-200, 100), (0, -100))

        canvas.text_color(Color.BLACK)
        canvas.font_size(54)
        canvas.text("Create!", 50, 100)


def main() raises:
    run[Sketch]("Example Sketch", 800, 600)
