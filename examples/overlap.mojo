from create import *


@fieldwise_init
struct App(Program):
    var center: Circle
    var mouse: Circle

    @staticmethod
    def create(mut frame: Frame) raises -> App:
        return App(
            center=Circle(0, 0, 100),
            mouse=Circle(0, 0, 100),
        )

    def update(mut self, mut frame: Frame, input: Input) raises:
        self.mouse.move_to(input.mouse)

    def render(self, mut frame: Frame) raises:
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
    run[App]("Circle Overlap", 1000, 1000, WindowMode.MAXIMIZED)
