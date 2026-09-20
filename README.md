# Mojo Create

**Mojo Create** is a creative coding library for rapid prototyping and 
interactive graphics, inspired by Processing but built to scale — from sketch to 
game, prototype to full application. It provides a clean, modular API while 
taking full advantage of Mojo's performance and language features.

> Early development, no stable API until the first public release.

## The shape of a program

```mojo
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
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", fullscreen=True)
```

Rendering runs on the CPU by default. `backend=RenderBackend.GPU` runs the same program through an
OpenGL 3.3 backend instead — no other change to the program:

```mojo
run[MyApp]("Example Sketch", backend=RenderBackend.GPU)
```

Run the example programs using the `create` pixi task:

```bash
pixi run create examples/sketch.mojo
```
