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
    def create(mut frame: Frame) raises -> MyApp:
        # Build the program's initial state, and load anything it owns,
        # e.g., sprites, fonts, sounds. This frame is never presented.
        return MyApp()  # Set initial application state here

    def update(mut self, mut frame: Frame, input: Input) raises:
        # Called once per frame: handle input, advance state, and render to the screen
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", WindowMode.FULLSCREEN)
```

`mode` comes right after the title because `WindowMode.FULLSCREEN` names itself; `width`/`height`
are keyword arguments because two bare integers do not.

`run`'s `width`/`height` (default 1280x720) are the resolution the program is *authored* in, not a
window size: a windowed launch opens at that size because the two coincide, while a fullscreen one
covers the display and scales the design onto it. `frame.design_resolution(w, h)` pins the same space from
inside `create`, and `frame.autoscale = AutoScale.OFF` opts out of the design space entirely, making
coordinates the window's own pixels.

Rendering runs on the CPU by default. `backend=RenderBackend.GPU` runs the same program through an
OpenGL 3.3 backend instead — no other change to the program:

```mojo
run[MyApp]("Example Sketch", backend=RenderBackend.GPU)
```

Run the example programs using the `create` pixi task:

```bash
pixi run create examples/sketch.mojo
```
