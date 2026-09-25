from .color import Color
from .style import Style
from create.math.matrix import Matrix, identity

comptime CMD_CLEAR = 0
"""Paint the whole framebuffer. `style.fill_color` is the colour."""
comptime CMD_RECT = 1
comptime CMD_CIRCLE = 2
comptime CMD_LINE = 3
comptime CMD_TRIANGLE = 4
comptime CMD_SPRITE = 5
comptime CMD_TEXT = 6
comptime CMD_LETTERBOX = 7
"""Paint the four bars outside the design area. `style.fill_color` is the colour and
`geom` is the *device* content rect — the one command whose geometry is
already in pixels, because it is the frame's clip rather than something a
program drew."""

comptime _GEOM_SLOTS = 6
"""Widest geometry any kind needs: a triangle's three vertices."""


def _scaled_alpha(color: Color, opacity: Float64) -> Color:
    """`color` with its alpha multiplied by `opacity`, clamped to `UInt8`."""
    var a = Float64(color.a) * opacity
    return Color(color.r, color.g, color.b, UInt8(max(0.0, min(255.0, a))))


struct RenderCommand(Copyable, Movable):
    """One recorded render, everything a backend needs to replay it.

    `Canvas` appends one of these per render call instead of rasterising, and a
    backend consumes the whole buffer at the end of the frame. That seam is
    what lets a GPU backend exist at all: a `Surface` is a pixel pointer, which
    a GPU does not have, whereas this is just data.

    **Geometry is local, never device.** It is the shape as the program asked
    for it, paired with the `transform` that maps it — *not* a pre-mapped
    device rect. A rotated rectangle is not an axis-aligned device rectangle,
    so pre-mapping would be lossy; the CPU replay needs the matrix anyway to
    inverse-map per pixel, and the GL backend wants exactly this shape because
    the transform becomes a vertex-shader uniform. The one exception is
    `CMD_LETTERBOX`, noted above.

    Everything else the replay needs is derivable from `transform`: whether it
    is an axis-aligned uniform scale, the world-units-per-pixel factor, and the
    device scan bounds of a local box.

    `geom` slots by kind:

    | kind | 0 | 1 | 2 | 3 | 4 | 5 |
    |---|---|---|---|---|---|---|
    | `CMD_CLEAR` | — | — | — | — | — | — |
    | `CMD_RECT` | `x` | `y` | `w` | `h` | — | — |
    | `CMD_CIRCLE` | `cx` | `cy` | `r` | — | — | — |
    | `CMD_LINE` | `x0` | `y0` | `x1` | `y1` | — | — |
    | `CMD_TRIANGLE` | `x1` | `y1` | `x2` | `y2` | `x3` | `y3` |
    | `CMD_SPRITE` | `cx` | `cy` | `w` | `h` | — | — |
    | `CMD_TEXT` | `x` | `y` | — | — | — | — |
    | `CMD_LETTERBOX` | `cx0` | `cy0` | `cx1` | `cy1` | — | — |

    Build one with the free functions below rather than by hand, so no rendering
    call site has to remember that table.
    """

    var kind: Int
    var geom: Array[Float64, _GEOM_SLOTS]
    var transform: Matrix[3, 3]
    var style: Style
    """Resolved at record time. A later `canvas.fill()` cannot reach back and
    change what an already-recorded command paints."""
    var text: String
    """`CMD_TEXT` only, and owned — layout happens at replay, in the backend
    that holds the fonts, so the string has to outlive the rendering call."""
    var image: Int
    """`CMD_SPRITE` only: a backend image id, interned at record time. The
    pixels are copied or uploaded when the sprite is first seen, so no borrow
    of caller-owned memory ever enters the buffer."""
    var image_w: Int
    var image_h: Int

    def __init__(
        out self,
        kind: Int,
        transform: Matrix[3, 3],
        style: Style,
        g0: Float64 = 0.0,
        g1: Float64 = 0.0,
        g2: Float64 = 0.0,
        g3: Float64 = 0.0,
        g4: Float64 = 0.0,
        g5: Float64 = 0.0,
    ):
        self.kind = kind
        self.geom = Array[Float64, _GEOM_SLOTS](fill=0.0)
        self.geom[0] = g0
        self.geom[1] = g1
        self.geom[2] = g2
        self.geom[3] = g3
        self.geom[4] = g4
        self.geom[5] = g5
        self.transform = transform
        self.style = style.copy()
        if self.style.opacity != 1.0:
            self.style.fill_color = _scaled_alpha(
                self.style.fill_color, self.style.opacity
            )
            self.style.outline_color = _scaled_alpha(
                self.style.outline_color, self.style.opacity
            )
            self.style.text_color = _scaled_alpha(
                self.style.text_color, self.style.opacity
            )
            self.style.opacity = 1.0
        self.text = String("")
        self.image = 0
        self.image_w = 0
        self.image_h = 0


def clear_command(color: Color) -> RenderCommand:
    """Paint the whole framebuffer. Carries no transform — it covers the
    framebuffer, not the design area, so no mapping applies."""
    var s = Style()
    s.fill_color = color
    s.fill_enabled = True
    return RenderCommand(CMD_CLEAR, identity[3](), s)


def rect_command(
    transform: Matrix[3, 3],
    style: Style,
    x: Float64,
    y: Float64,
    w: Float64,
    h: Float64,
) -> RenderCommand:
    """A rectangle centred at `(x, y)`, `w` by `h`, in local units."""
    return RenderCommand(CMD_RECT, transform, style, x, y, w, h)


def circle_command(
    transform: Matrix[3, 3],
    style: Style,
    cx: Float64,
    cy: Float64,
    r: Float64,
) -> RenderCommand:
    return RenderCommand(CMD_CIRCLE, transform, style, cx, cy, r)


def line_command(
    transform: Matrix[3, 3],
    style: Style,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
) -> RenderCommand:
    return RenderCommand(CMD_LINE, transform, style, x0, y0, x1, y1)


def triangle_command(
    transform: Matrix[3, 3],
    style: Style,
    x1: Float64,
    y1: Float64,
    x2: Float64,
    y2: Float64,
    x3: Float64,
    y3: Float64,
) -> RenderCommand:
    return RenderCommand(CMD_TRIANGLE, transform, style, x1, y1, x2, y2, x3, y3)


def sprite_command(
    transform: Matrix[3, 3],
    style: Style,
    cx: Float64,
    cy: Float64,
    w: Float64,
    h: Float64,
    image: Int,
    image_w: Int,
    image_h: Int,
) -> RenderCommand:
    """A sprite centred at `(cx, cy)`, rendered `w` by `h` local units.

    `image` is a backend id, not a pointer — see the field docstring. `image_w`
    and `image_h` are the source pixel dimensions, which the replay needs to
    resample and the record site already knows.
    """
    var c = RenderCommand(CMD_SPRITE, transform, style, cx, cy, w, h)
    c.image = image
    c.image_w = image_w
    c.image_h = image_h
    return c^


def text_command(
    transform: Matrix[3, 3], style: Style, x: Float64, y: Float64, var s: String
) -> RenderCommand:
    """Text anchored at `(x, y)` in local units.

    Deferred whole: the alignment, advances and baseline all come out of
    `style` and the backend's font at replay time, so nothing about the layout
    is decided here.
    """
    var c = RenderCommand(CMD_TEXT, transform, style, x, y)
    c.text = s^
    return c^


def letterbox_command(
    color: Color, cx0: Float64, cy0: Float64, cx1: Float64, cy1: Float64
) -> RenderCommand:
    """The bars outside the device content rect `[cx0, cx1) x [cy0, cy1)`.

    Recorded last, so it doubles as the clip for anything a program drew past
    the edges of the design area.
    """
    var s = Style()
    s.fill_color = color
    s.fill_enabled = True
    return RenderCommand(CMD_LETTERBOX, identity[3](), s, cx0, cy0, cx1, cy1)
