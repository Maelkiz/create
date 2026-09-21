from .align import Align
from .color import Color
from .font import FontWeight


struct Style(Copyable, Movable):
    """How the next shape or glyph is painted, independent of where it goes.

    Set once and read by every render call until changed. Rebuilt fresh each
    frame — carrying one forward would preserve only a forgotten setting,
    never a useful one.
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

    def __init__(out self):
        self.fill_color = Color.TRANSPARENT
        self.fill_enabled = True
        self.outline_color = Color.BLACK
        self.outline_thickness = 1
        self.outline_enabled = True
        self.corner_radius = 0
        self.text_color = Color.BLACK
        self.font_size = 16
        self.font_weight = FontWeight.REGULAR
        self.text_align = Align.TOP_LEFT
        self.opacity = 1.0

    def fill_visible(self) -> Bool:
        """Whether the fill actually paints anything.

        `fill_enabled` alone isn't enough — a fully transparent color paints
        nothing either, and every rasteriser gate should skip that work
        rather than render an invisible fill.
        """
        return self.fill_enabled and self.fill_color.a > 0

    def outline_visible(self) -> Bool:
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
