"""How smooth the edges of shapes are drawn.

A selector with a type of its own, the same shape as `RenderBackend` and
`WindowMode`: an `Int` in `run`'s signature would make a bare number silently
valid, and the constructor is not `@implicit` for the same reason.

The levels name a quality, not a technique, because each backend reaches it
its own way:

| Level | GPU (MSAA samples) | CPU (samples per pixel) |
|---|---|---|
| `OFF` | none | 1, the pixel centre |
| `LOW` | 2 | 2 x 2 |
| `MEDIUM` | 4 | 4 x 4 |
| `HIGH` | 8 | 8 x 8 |

The GPU draws the frame into an offscreen multisampled framebuffer and
resolves it into the window (or a headless target), capped at the driver's
maximum sample count. The CPU replays each shape through its own rasteriser
on a grid that much finer and composites the coverage once, fill and outline
together, so a shape's edge has no seam between the two. Shapes only: text
and images are smooth already. A clip's edge is antialiased like a shape's
on both. Pixel reads and `save_image` replay
on the CPU at the same level, under either backend.

`run`'s `antialiasing` argument is the starting level; `canvas.antialiasing`
changes it for the whole frame it is called in and every later one.
"""

from std.math import max, min


struct Antialiasing(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    var value: Int

    comptime OFF = Antialiasing(0)
    comptime LOW = Antialiasing(1)
    comptime MEDIUM = Antialiasing(2)
    comptime HIGH = Antialiasing(3)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: Antialiasing) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Antialiasing) -> Bool:
        return self.value != other.value

    def _gpu_samples(self) -> Int:
        """The MSAA sample count the GL window asks for: 0, 2, 4 or 8."""
        if self.value <= 0:
            return 0
        return 1 << min(self.value, 3)

    def _cpu_grid(self) -> Int:
        """Samples along each axis of a pixel on the CPU: 1, 2, 4 or 8."""
        return 1 << max(min(self.value, 3), 0)

    def _lower(self) -> Antialiasing:
        """The next level down, `OFF` staying `OFF`."""
        return Antialiasing(max(self.value - 1, 0))

    def write_to[W: Writer](self, mut writer: W):
        if self == Antialiasing.OFF:
            writer.write("Antialiasing.OFF")
        elif self == Antialiasing.LOW:
            writer.write("Antialiasing.LOW")
        elif self == Antialiasing.MEDIUM:
            writer.write("Antialiasing.MEDIUM")
        elif self == Antialiasing.HIGH:
            writer.write("Antialiasing.HIGH")
        else:
            writer.write("Antialiasing(", self.value, ")")
