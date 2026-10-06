from std.collections import Optional
from std.utils.numerics import isnan, nan

from .align import Align
from create.color.blend_mode import BlendMode
from create.color.color import Color
from create.color.gradient import Gradient
from create.text.font import Font, FontWeight
from create.math.vector2d import Vector2D


comptime _KEEP = nan[DType.float64]()
"""Default of a `Float64` shadow part meaning "not given". Not
`Optional[Float64]`, which a bare `blur=12` cannot reach — an integer
literal converts to `Float64` or to an `Optional`, not through both — and not
a negative number, since a negative spread is meaningful."""


struct Style(Copyable, ImplicitlyCopyable, Movable, Writable):
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
    )
    ```

    The constructor's keywords are named after the canvas setters and act
    like them: naming any part of the fill, outline or shadow switches it
    on, unless `fill_enabled`, `outline_enabled` or `shadow_enabled` says
    otherwise, so `Style(shadow=Color.RED, shadow_enabled=False)` keeps a
    shadow ready but off. `fill_gradient` is the keyword for `fill`'s
    `Gradient` overload, since one keyword can't take both: given beside
    `fill`, the gradient paints and the colour is kept for when it is
    cleared. Every part left unset is what a fresh frame starts with.
    """

    var fill_color: Color
    var fill_gradient: Optional[Gradient]
    """Paints the fill instead of `fill_color` while set; `fill_color` is
    kept for when it is cleared."""
    var fill_enabled: Bool
    var outline_color: Color
    var outline_thickness: Int
    var outline_enabled: Bool
    var corner_radius: Int
    var text_color: Color
    var font: Optional[Font]
    """The face text is drawn in; none for the packaged Noto Sans."""
    var font_size: Int
    var font_weight: Int
    var font_italic: Bool
    var text_align: Align
    var tint: Color
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
        fill: Optional[Color] = None,
        fill_gradient: Optional[Gradient] = None,
        fill_enabled: Optional[Bool] = None,
        outline: Optional[Color] = None,
        outline_thickness: Optional[Int] = None,
        outline_enabled: Optional[Bool] = None,
        corner_radius: Int = 0,
        text_color: Color = Color.BLACK,
        font: Optional[Font] = None,
        font_size: Int = 16,
        font_weight: Int = FontWeight.REGULAR,
        font_italic: Bool = False,
        text_align: Align = Align.CENTER,
        tint: Color = Color.WHITE,
        opacity: Float64 = 1.0,
        blend_mode: BlendMode = BlendMode.NORMAL,
        shadow: Optional[Color] = None,
        shadow_offset: Optional[Vector2D] = None,
        shadow_blur: Float64 = _KEEP,
        shadow_spread: Float64 = _KEEP,
        shadow_inset: Optional[Bool] = None,
        shadow_follows_transform: Bool = False,
        shadow_enabled: Optional[Bool] = None,
    ):
        self.fill_color = fill.or_else(Color.WHITE)
        self.fill_gradient = fill_gradient
        self.fill_enabled = fill_enabled.or_else(
            Bool(fill) or Bool(fill_gradient)
        )
        self.outline_color = outline.or_else(Color.BLACK)
        self.outline_thickness = outline_thickness.or_else(1)
        self.outline_enabled = outline_enabled.or_else(True)
        self.corner_radius = corner_radius
        self.text_color = text_color
        self.font = font
        self.font_size = font_size
        self.font_weight = font_weight
        self.font_italic = font_italic
        self.text_align = text_align
        self.tint = tint
        self.opacity = opacity
        self.blend_mode = blend_mode
        self.shadow_color = shadow.or_else(Color(0, 0, 0, 96))
        self.shadow_offset = shadow_offset.or_else(Vector2D(4, -4))
        self.shadow_blur = 8.0 if isnan(shadow_blur) else shadow_blur
        self.shadow_spread = 0.0 if isnan(shadow_spread) else shadow_spread
        self.shadow_inset = shadow_inset.or_else(False)
        self.shadow_follows_transform = shadow_follows_transform
        self.shadow_enabled = shadow_enabled.or_else(
            Bool(shadow)
            or Bool(shadow_offset)
            or not isnan(shadow_blur)
            or not isnan(shadow_spread)
            or Bool(shadow_inset)
        )

    def write_to[W: Writer](self, mut writer: W):
        # Named by the constructor's keywords, not the fields, so the output
        # reads back as a `Style(...)` call.
        writer.write(
            "Style(fill=",
            self.fill_color,
            ", fill_gradient=",
        )
        if self.fill_gradient:
            writer.write(self.fill_gradient.value())
        else:
            writer.write("None")
        writer.write(
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
            ", font=",
        )
        if self.font:
            writer.write(self.font.value())
        else:
            writer.write("None")
        writer.write(
            ", font_size=",
            self.font_size,
            ", font_weight=",
            self.font_weight,
            ", font_italic=",
            self.font_italic,
            ", text_align=",
            self.text_align,
            ", tint=",
            self.tint,
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

        `fill_enabled` alone isn't enough — a fully transparent color, or a
        gradient whose every stop is, paints nothing either, and every rasteriser gate should skip that work
        rather than render an invisible fill.
        """
        if not self.fill_enabled:
            return False
        if self.fill_gradient:
            return self.fill_gradient.value()._visible()
        return self.fill_color.a > 0

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
