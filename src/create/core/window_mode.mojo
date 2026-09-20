"""How the window presents itself at launch.

A mode selector, not a typed value passed around structurally — `run`'s
`mode` parameter stays a plain `Int`, compared with `==`, the same shape as
`AutoScale`/`RenderBackend`. A struct instead of free constants because this
file is public surface and the library doesn't scatter top-level constants.

`FULLSCREEN` and `BORDERLESS` are mutually exclusive by construction — one
`Int` can only equal one constant — which a pair of independent bools could
not guarantee. `WINDOWED` is the default: an ordinary decorated, sized
window.
"""


struct WindowMode:
    comptime WINDOWED = 0
    comptime FULLSCREEN = 1
    comptime BORDERLESS = 2
