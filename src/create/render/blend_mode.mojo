struct BlendMode(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """How a shape, glyph or sprite combines with what is already rendered.

    Set with `canvas.blend_mode` or the `blend_mode` keyword of
    `canvas.style`/`Style`, and read by every render call after it, like any
    other style setting. Each mode is a per-channel formula over the source
    colour `s` and the colour already there, `d`, both as fractions of 255:

    | Mode | Result | Looks like |
    |---|---|---|
    | `NORMAL` | `s` | Paint over paint — the default |
    | `ADD` | `d + s` | Light: glows, sparks, fire. Only brightens |
    | `SUBTRACT` | `d - s` | Removing light. Only darkens |
    | `MULTIPLY` | `d * s` | Stacked tinted film: shadows. Only darkens |
    | `SCREEN` | `1 - (1 - d) * (1 - s)` | Projected light. Only brightens, softer than `ADD` |

    Results are clamped to `[0, 1]`. The source's alpha (after `opacity`)
    scales how much of the effect shows, so a half-transparent `ADD` adds
    half as much. The framebuffer's own alpha channel always composites
    source-over, whatever the mode.

    Modes apply to render calls, not to `canvas.background`, which always
    paints normally. A shape's fill and its outline overlap along the edge,
    so under a mode that accumulates (`ADD`, `MULTIPLY`, ...) the overlap
    shows twice; switch the outline off for a clean glow.

    ```mojo
    with canvas.style(blend_mode=BlendMode.ADD, outline_enabled=False):
        for p in self.sparks:
            canvas.circle(p.pos, 6)
    ```
    """

    var value: Int

    comptime NORMAL = BlendMode(0)
    comptime ADD = BlendMode(1)
    comptime MULTIPLY = BlendMode(2)
    comptime SUBTRACT = BlendMode(3)
    comptime SCREEN = BlendMode(4)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: BlendMode) -> Bool:
        return self.value == other.value

    def __ne__(self, other: BlendMode) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        if self == BlendMode.NORMAL:
            writer.write("BlendMode.NORMAL")
        elif self == BlendMode.ADD:
            writer.write("BlendMode.ADD")
        elif self == BlendMode.MULTIPLY:
            writer.write("BlendMode.MULTIPLY")
        elif self == BlendMode.SUBTRACT:
            writer.write("BlendMode.SUBTRACT")
        elif self == BlendMode.SCREEN:
            writer.write("BlendMode.SCREEN")
        else:
            writer.write("BlendMode(", self.value, ")")
