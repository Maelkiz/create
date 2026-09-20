from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut frame: Frame) raises -> MyApp:
        # Build the program's initial state, and load anything it owns —
        # sprites, fonts, sounds. This frame is never presented.
        return MyApp()

    def update(mut self, mut frame: Frame, input: Input) raises:
        # One method per frame: read `input`, advance state, then draw. The
        # decision and the drawing it causes belong to the same frame, so
        # they belong to the same method.
        frame.background(Color.BLACK)
        frame.text_color(Color.WHITE)
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", mode=WindowMode.FULLSCREEN)
