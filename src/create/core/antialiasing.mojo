"""How the GPU backend smooths the edges it draws.

A selector with a type of its own, the same shape as `WindowMode`: an `Int`
in `run`'s signature would make a bare sample count silently valid, and the
constructor is not `@implicit` for the same reason. The value is the sample
count, so `OFF` is 0 and `MSAA_4X` is 4.

Multisampling is the framebuffer's job, fixed when the GL context is
created, which is why this is a `run` argument rather than a `Context` dial.
The CPU backend antialiases nothing and ignores it. Pixel reads
(`canvas.pixel`, `canvas.snapshot`) replay the frame on the CPU, so they never
see it either.

A driver that refuses the requested count gets the next one down, then the
next, and finally none: a missing antialias is a better outcome than a
program that will not start.
"""


struct Antialiasing(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    var samples: Int

    comptime OFF = Antialiasing(0)
    comptime MSAA_2X = Antialiasing(2)
    comptime MSAA_4X = Antialiasing(4)
    comptime MSAA_8X = Antialiasing(8)

    def __init__(out self, samples: Int):
        self.samples = samples

    def __eq__(self, other: Antialiasing) -> Bool:
        return self.samples == other.samples

    def __ne__(self, other: Antialiasing) -> Bool:
        return self.samples != other.samples

    def write_to[W: Writer](self, mut writer: W):
        if self == Antialiasing.OFF:
            writer.write("Antialiasing.OFF")
        elif self == Antialiasing.MSAA_2X:
            writer.write("Antialiasing.MSAA_2X")
        elif self == Antialiasing.MSAA_4X:
            writer.write("Antialiasing.MSAA_4X")
        elif self == Antialiasing.MSAA_8X:
            writer.write("Antialiasing.MSAA_8X")
        else:
            writer.write("Antialiasing(", self.samples, ")")
