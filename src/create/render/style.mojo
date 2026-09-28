from .align import Align
from .blend_mode import BlendMode
from .color import Color
from .font import FontWeight
from create.math.vector2d import Vector2D


struct Style(Copyable, Movable, Writable):
    """How the next shape or glyph is painted, independent of where it goes.

    The canvas holds one, set piece by piece through `canvas.fill`,
    `canvas.outline` and the other style setters, read by every render call
    until changed and rebuilt fresh each frame. A program can also build its
    own and apply it whole with `canvas.style(s)`, to reuse one look across
    render calls, frames or entities:

    ```mojo
    var label = Style(outline_enabled=False, text_color=Color.WHITE, font_size=24)
    with canvas.style(label):
        canvas.text("Score", (0, canvas.top() - 20))
    ```

    A shadow is part of the style too, so a card's look can carry its own:

    ```mojo
    var card = Style(
        fill=Color.WHITE,
        outline_enabled=False,
        corner_radius=12,
        shadow=Color(0, 0, 0, 80),
        shadow_blur=16,
        shadow_enabled=True,
    )
    ```

    The constructor's keywords are named after the canvas setters, and each
    defaults to what a fresh frame starts with. The font is not part of a
    style: it is a loaded resource, set with `canvas.font` and kept across
    frames.
    """

    var fill_color: Color
    var fill_enabled: Bool
    var outline_color: Color
    var outline_thickness: Int
    var outline_enabled: Bool
    var corner_radius: Int
    var text_color: Color
    var font_size: Int
    var font_weight: Int
    var text_align: Align
    var opacity: Float64
    var blend_mode: BlendMode
    var shadow_color: Color
    var shadow_offset: Vector2D
    var shadow_blur: Float64
    var shadow_spread: Float64
    var shadow_inset: Bool
    var shadow_follows_transform: Bool
    var shadow_enabled: Bool

    def __init__(
        out self,
        *,
        fill: Color = Color.TRANSPARENT,
        fill_enabled: Bool = True,
        outline: Color = Color.BLACK,
        outline_thickness: Int = 1,
        outline_enabled: Bool = True,
        corner_radius: Int = 0,
        text_color: Color = Color.BLACK,
        font_size: Int = 16,
        font_weight: Int = FontWeight.REGULAR,
        text_align: Align = Align.CENTER,
        opacity: Float64 = 1.0,
        blend_mode: BlendMode = BlendMode.NORMAL,
        shadow: Color = Color(0, 0, 0, 96),
        shadow_offset: Vector2D = Vector2D(4, -4),
        shadow_blur: Float64 = 8.0,
        shadow_spread: Float64 = 0.0,
        shadow_inset: Bool = False,
        shadow_follows_transform: Bool = False,
        shadow_enabled: Bool = False,
    ):
        self.fill_color = fill
        self.fill_enabled = fill_enabled
        self.outline_color = outline
        self.outline_thickness = outline_thickness
        self.outline_enabled = outline_enabled
        self.corner_radius = corner_radius
        self.text_color = text_color
        self.font_size = font_size
        self.font_weight = font_weight
        self.text_align = text_align
        self.opacity = opacity
        self.blend_mode = blend_mode
        self.shadow_color = shadow
        self.shadow_offset = shadow_offset
        self.shadow_blur = shadow_blur
        self.shadow_spread = shadow_spread
        self.shadow_inset = shadow_inset
        self.shadow_follows_transform = shadow_follows_transform
        self.shadow_enabled = shadow_enabled

    def write_to[W: Writer](self, mut writer: W):
        # Named by the constructor's keywords, not the fields, so the output
        # reads back as a `Style(...)` call.
        writer.write(
            "Style(fill=",
            self.fill_color,
            ", fill_enabled=",
            self.fill_enabled,
            ", outline=",
            self.outline_color,
            ", outline_thickness=",
            self.outline_thickness,
            ", outline_enabled=",
            self.outline_enabled,
            ", corner_radius=",
            self.corner_radius,
            ", text_color=",
            self.text_color,
            ", font_size=",
            self.font_size,
            ", font_weight=",
            self.font_weight,
            ", text_align=",
            self.text_align,
            ", opacity=",
            self.opacity,
            ", blend_mode=",
            self.blend_mode,
            ", shadow=",
            self.shadow_color,
            ", shadow_offset=",
            self.shadow_offset,
            ", shadow_blur=",
            self.shadow_blur,
            ", shadow_spread=",
            self.shadow_spread,
            ", shadow_inset=",
            self.shadow_inset,
            ", shadow_follows_transform=",
            self.shadow_follows_transform,
            ", shadow_enabled=",
            self.shadow_enabled,
            ")",
        )

    def _fill_visible(self) -> Bool:
        """Whether the fill actually paints anything.

        `fill_enabled` alone isn't enough — a fully transparent color paints
        nothing either, and every rasteriser gate should skip that work
        rather than render an invisible fill.
        """
        return self.fill_enabled and self.fill_color.a > 0

    def _outline_visible(self) -> Bool:
        """Whether the outline actually paints anything.

        `outline_enabled` alone isn't enough — a fully transparent color or a
        zero thickness paints nothing either, and every rasteriser gate
        should skip that work rather than render an invisible outline.
        """
        return (
            self.outline_enabled
            and self.outline_color.a > 0
            and self.outline_thickness > 0
        )

    def _shadow_visible(self) -> Bool:
        """Whether the shadow actually paints anything.

        Like `_fill_visible`: switched on and not fully transparent. Which
        kinds cast one (and which ignore `shadow_inset`) is the backends'
        call, not the style's.
        """
        return self.shadow_enabled and self.shadow_color.a > 0
