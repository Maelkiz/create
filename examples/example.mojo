from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut frame: Frame) raises -> MyApp:
        # Build the program's initial state, and load anything it owns,
        # e.g., sprites, fonts, sounds. This frame is never presented.
        return MyApp()

    def update(mut self, mut frame: Frame, input: Input) raises:
        # Called once per frame: handle input, advance state, and render to the screen
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", mode=WindowMode.FULLSCREEN)
