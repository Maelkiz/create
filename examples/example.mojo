from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut ctx: Context) raises -> MyApp:
        return MyApp()  # Set initial application state here

    def update(mut self, mut ctx: Context, input: Input) raises:
        pass  # Executes once per frame, handle input, update state, etc.

    def render(self, mut frame: Frame) raises:
        # Also executes once per frame, frame.rectangle(), frame.circle(), etc.
        frame.background(Color.BLACK)
        frame.text_color(Color.WHITE)
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", mode=WindowMode.FULLSCREEN)
