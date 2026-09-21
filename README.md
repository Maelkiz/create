<p align="center">
    <img src="assets/logo/png/logo-trim.png" width="150" alt="Create Logo">
</p>

<h1 align="center">Mojo Create</h1>

> **Note:** API will be unstable until the first public release.

---

**Mojo Create** is a creative coding library for rapid prototyping and interactive graphics, inspired by Processing but built to scale — 
from sketch to game, prototype to full application. It provides a clean, modular API while taking full advantage of Mojo's performance and language features.

## The shape of a program

```mojo
from create import *


@fieldwise_init
struct MyApp(Program):
    @staticmethod
    def create(mut options: Options) raises -> MyApp:
        # Set initial application state here
        return MyApp()  

    def update(mut self, mut options: Options, mut frame: Frame) raises:
        # Called once per frame: handle input, advance state, and render to the screen
        frame.text_align(Align.CENTER)
        frame.text("Hello World!", 0, 0)


def main() raises:
    run[MyApp]("Example Sketch", WindowMode.FULLSCREEN)
```

Rendering runs on the CPU by default. `backend=RenderBackend.GPU` runs the same program through an OpenGL 3.3 backend instead:

```mojo
run[MyApp]("Example Sketch", backend=RenderBackend.GPU)
```

The example programs in this repository can be run with the `example` pixi task, which takes a name rather than a path. 
The name must correspond to a file or folder under `examples/`. For folders it will find an run their `src/main.mojo`.

```bash
pixi run example sketch          # examples/sketch.mojo
pixi run example sidescroller    # examples/sidescroller/src/main.mojo
pixi run example                 # lists every example
```
