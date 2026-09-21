"""Which renderer replays a frame's `RenderCommand`s.

A selector with a type of its own: `Backend.kind` and the `backend`
parameter of `run`/`run_headless` are all `RenderBackend`, compared with `==`,
the same shape as `WindowMode`. The type keeps a backend constant from binding
to a neighbouring `Int` parameter by position — `run_headless(w, h,
RenderBackend.GPU)` used to mean `frames=1` on the CPU backend and compile.
The constructor is deliberately not `@implicit` for the same reason.
"""


struct RenderBackend(Copyable, Equatable, ImplicitlyCopyable, Movable):
    var value: Int

    comptime CPU = RenderBackend(0)
    # replays onto a Surface through _raster.mojo
    comptime GPU = RenderBackend(1)
    # replays through GLRenderer — see _gl_backend.mojo

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: RenderBackend) -> Bool:
        return self.value == other.value

    def __ne__(self, other: RenderBackend) -> Bool:
        return self.value != other.value
