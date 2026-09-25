from create import *


@fieldwise_init
struct App(Program):
    var center: Circle
    var mouse: Circle

    @staticmethod
    def create(mut context: Context) raises -> App:
        return App(
            center=Circle(0, 0, 100),
            mouse=Circle(0, 0, 100),
        )

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        self.mouse.move_to(canvas.input.mouse)

        if overlaps(self.center, self.mouse):
            canvas.background(Color(40, 40, 60))
        else:
            canvas.background(Color(20, 20, 30))

        canvas.outline(enabled=False)
        canvas.fill(Color(220, 60, 60))
        canvas.circle(self.center)
        canvas.fill(Color(60, 120, 220))
        canvas.circle(self.mouse)


def main() raises:
    run[App]("Circle Overlap", WindowMode.MAXIMIZED, width=1000, height=1000)
