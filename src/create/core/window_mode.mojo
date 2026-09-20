"""How the window presents itself at launch.

A mode selector, not a typed value passed around structurally — `run`'s
`mode` parameter stays a plain `Int`, compared with `==`, the same shape as
`AutoScale`/`RenderBackend`. A struct instead of free constants because this
file is public surface and the library doesn't scatter top-level constants.

`FULLSCREEN`, `BORDERLESS` and `MAXIMIZED` are mutually exclusive by
construction — one `Int` can only equal one constant — which independent
bools could not guarantee. `WINDOWED` is the default: an ordinary decorated,
sized window.
"""


struct WindowMode:
    comptime WINDOWED = 0
    comptime FULLSCREEN = 1
    comptime BORDERLESS = 2
    comptime MAXIMIZED = 3
