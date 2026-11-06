<p align="center">
    <img src="assets/logo/png/logo-trim.png" width="150" alt="Create Logo">
</p>

<h1 align="center">Create</h1>

> Note: APIs are experimental and subject to change.

---

**Create** is a creative coding library for rapid prototyping and interactive graphics, inspired by Processing but built to scale — 
from sketch to game, prototype to full application. It provides a clean, modular API while taking full advantage of Mojo's performance and language features.

## Example program

<p align="center">
    <img src="assets/gifs/logo-animation.gif" alt="The Create logo assembling: a Sierpinski triangle drawn in points, then the logo's triangles flying in over it">
    <br>
    <sub>The logo drawn, animated, and recorded to a GIF using the Create library itself. See: <a href="examples/logo/main.mojo">examples/logo</a> for the source code.</sub>
</p>

## The boilerplate

```mojo
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
```

Rendering runs on the CPU by default. `backend=RenderBackend.GPU` runs the same program through an OpenGL 3.3 backend instead:

```mojo
run[MyApp]("Hello", backend=RenderBackend.GPU)
```

`RenderBackend.from_arguments()` lets the command line choose instead: given `gpu` as an argument, the program will run using the GPU backend. 
Conversely, providing `cpu` (or omitting the argument entirely) runs the program on the CPU rendering backend.

```mojo
run[MyApp]("Hello", backend=RenderBackend.from_arguments())
```

## Running examples and benchmarks

You can run the example programs in this repository with the `example` pixi task, which takes a name rather than a path. 
The name is a folder under `examples/`, and the task runs its `main.mojo`.

```bash
pixi run example sketch          # examples/sketch/main.mojo
pixi run example sidescroller    # examples/sidescroller/main.mojo
pixi run example                 # lists every example
```

Benchmarks live under `benchmarks/` and run the same way with the `benchmark` task:

```bash
pixi run benchmark frame         # a heavy frame through the window loop, GPU
pixi run benchmark frame cpu     # the same frame on the CPU backend
pixi run benchmark raster        # CPU rasterization per primitive, headless
```

## Supported Platforms

| Platform | Status |
|----------|--------|
| Linux (x86-64) | Supported, used day to day |
| Windows through WSL2 | Supported, used day to day |
| macOS on Apple silicon | Built and tested in CI on every change; little use on a real desktop yet |

Intel Macs and native Windows are not supported: Mojo doesn't run on either. Every dependency, Mojo included, 
is managed by [pixi](https://pixi.sh), so `pixi run` is all a supported machine needs. Programs built with 
`mojo build` can be run from any working directory and locate their shared libraries in the original Pixi 
environment, which must remain in place.
