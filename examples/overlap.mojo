from create import *


@fieldwise_init
struct App(Program):
    var center: Circle
    var mouse: Circle

    @staticmethod
    def create(mut options: Options) raises -> App:
        return App(
            center=Circle(0, 0, 100),
            mouse=Circle(0, 0, 100),
        )

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        self.mouse.move_to(frame.input.mouse)

        if overlaps(self.center, self.mouse):
            frame.background(Color(40, 40, 60))
        else:
            frame.background(Color(20, 20, 30))

        frame.outline(enabled=False)
        frame.fill(Color(220, 60, 60))
        frame.circle(self.center)
        frame.fill(Color(60, 120, 220))
        frame.circle(self.mouse)


def main() raises:
    run[App]("Circle Overlap", WindowMode.MAXIMIZED, width=1000, height=1000)
