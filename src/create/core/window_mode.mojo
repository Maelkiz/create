"""How the window presents itself at launch.

A mode selector with a type of its own: `run`'s `mode` parameter is a
`WindowMode`, compared with `==`, the same shape as `RenderBackend`. The type
is what lets `mode` sit ahead of `width`/`height` in `run`'s signature — an
`Int` there would have made `run("T", 800)` a silently valid mode. The
constructor is deliberately not `@implicit` for the same reason.

`FULLSCREEN`, `BORDERLESS` and `MAXIMIZED` are mutually exclusive by
construction — one `Int` can only equal one constant — which independent
bools could not guarantee. `WINDOWED` is the default: an ordinary decorated,
sized window.
"""


struct WindowMode(Copyable, Equatable, ImplicitlyCopyable, Movable):
    var value: Int

    comptime WINDOWED = WindowMode(0)
    comptime FULLSCREEN = WindowMode(1)
    comptime BORDERLESS = WindowMode(2)
    comptime MAXIMIZED = WindowMode(3)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: WindowMode) -> Bool:
        return self.value == other.value

    def __ne__(self, other: WindowMode) -> Bool:
        return self.value != other.value
