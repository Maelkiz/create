"""The example code used in README."""

from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut context: Context) -> MyApp:
        # Set initial application state here
        return MyApp()

    def update(mut self, mut context: Context, mut canvas: Canvas):
        # Called once per frame: handle canvas.input, advance state, and render to the screen
        canvas.text("Hello World!", (0, 0))


def main() raises:
    run[MyApp]("Hello", WindowMode.WINDOWED)
