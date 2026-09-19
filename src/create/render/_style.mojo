from .align import Align
from .color import Color
from .font import FontWeight


struct Style(Copyable, Movable):
    """How the next shape or glyph is painted, independent of where it goes.

    Set once and read by every draw call until changed. Rebuilt fresh each
    frame — carrying one forward would preserve only a forgotten setting,
    never a useful one.
    """

    var fill: Color
    var fill_enabled: Bool
    var outline: Color
    var outline_thickness: Int
    var outline_enabled: Bool
    var font_size: Int
    var font_weight: Int
    var text_align: Align

    def __init__(out self):
        self.fill = Color.WHITE
        self.fill_enabled = True
        self.outline = Color.BLACK
        self.outline_thickness = 1
        self.outline_enabled = True
        self.font_size = 16
        self.font_weight = FontWeight.REGULAR
        self.text_align = Align.TOP_LEFT
