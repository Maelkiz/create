"""Which renderer replays a frame's `RenderCommand`s.

A selector with a type of its own: `Backend.kind` and the `backend`
parameter of `run`/`run_headless` are all `RenderBackend`, compared with `==`,
the same shape as `WindowMode`. The type keeps a backend constant from binding
to a neighbouring `Int` parameter by position — `run_headless(w, h,
RenderBackend.GPU)` used to mean `frames=1` on the CPU backend and compile.
The constructor is deliberately not `@implicit` for the same reason.
"""

from std.sys import argv


struct RenderBackend(
    Copyable, Equatable, ImplicitlyCopyable, Movable, Writable
):
    var value: Int

    comptime CPU = RenderBackend(0)
    # replays onto a Surface through _raster.mojo
    comptime GPU = RenderBackend(1)
    # replays through GLRenderer — see _gl_backend.mojo

    def __init__(out self, value: Int):
        self.value = value

    @staticmethod
    def from_arguments() -> RenderBackend:
        """The backend named on the command line: `GPU` when the program was
        run with a `gpu` argument, `CPU` otherwise or with `cpu`, the last
        named winning. So one build runs on either, `./sketch gpu` or
        `pixi run example shadows gpu`, passed as
        `run(..., backend=RenderBackend.from_arguments())`; other arguments
        are left for the program."""
        var arguments = List[String]()
        var raw = argv()
        for i in range(1, len(raw)):
            arguments.append(String(raw[i]))
        return RenderBackend._from_argument_list(arguments)

    @staticmethod
    def _from_argument_list(arguments: List[String]) -> RenderBackend:
        """`from_arguments` over a given list, so it can be tested without a
        command line."""
        var backend = RenderBackend.CPU
        for argument in arguments:
            if argument == "gpu":
                backend = RenderBackend.GPU
            elif argument == "cpu":
                backend = RenderBackend.CPU
        return backend

    def __eq__(self, other: RenderBackend) -> Bool:
        return self.value == other.value

    def __ne__(self, other: RenderBackend) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        if self == RenderBackend.CPU:
            writer.write("RenderBackend.CPU")
        elif self == RenderBackend.GPU:
            writer.write("RenderBackend.GPU")
        else:
            writer.write("RenderBackend(", self.value, ")")
