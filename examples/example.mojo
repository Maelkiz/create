from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut ctx: Context) raises -> MyApp:
        return MyApp()  # Set initial application state here

    def update(mut self, mut ctx: Context, input: Input) raises:
        pass  # Executes once per frame, handle input, update state, etc.

    def render(self, mut canvas: Canvas) raises:
        # Also executes once per frame, canvas.rectangle(), canvas.circle(), etc.
        canvas.background(Color.BLACK)
        canvas.text_color(Color.WHITE)
        canvas.text_align(Align.CENTER)
        canvas.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", mode=WindowMode.FULLSCREEN)
