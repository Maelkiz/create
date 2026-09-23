"""The example code used in README."""

from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut options: Options) -> MyApp:
        # Set initial application state here
        return MyApp()

    def update(mut self, mut options: Options, mut frame: Frame):
        # Called once per frame: handle frame.input, advance state, and render to the screen
        frame.text("Hello World!", (0, 0))


def main() raises:
    run[MyApp]("Hello", WindowMode.WINDOWED)
