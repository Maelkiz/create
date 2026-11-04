"""The example code used in README."""

from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut context: Context, mut canvas: Canvas) raises -> MyApp:
        # Called once: set initial application state and draw the first frame
        return MyApp()

    def update(mut self, mut context: Context, mut canvas: Canvas) raises:
        # Called once per frame: handle input, modify state, and draw to the screen
        canvas.font_size(48)
        canvas.text("Hello, world!", (0, 0))


def main() raises:
    run[MyApp]("Hello")
