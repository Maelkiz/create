struct Align(Copyable, Equatable, ImplicitlyCopyable, Movable):
    """Which point of a box a position names — one value for both axes.

    The nine constants are the nine points of the box, so a single argument
    says everything `canvas.text_align` needs:

    ```
    # # # # # # # # # # # # # # # # # # # # # #
    # TOP_LEFT ———————— TOP ——————— TOP_RIGHT #
    # |                  |                  | #
    # |                  |                  | #
    # LEFT —————————— CENTER —————————— RIGHT #
    # |                  |                  | #
    # |                  |                  | #
    # BOTTOM_LEFT ——— BOTTOM ——— BOTTOM_RIGHT #
    # # # # # # # # # # # # # # # # # # # # # #
    ```

    The one-word constants name an edge's midpoint: `TOP` is top-centre,
    `LEFT` is middle-left, `CENTER` is the middle of the box.

    Edges of the box, not typographic baselines — there is no separate
    `text_baseline`. `TOP` and `BOTTOM` mean the visual top and bottom even
    though y grows upward, because glyphs are not flipped by the coordinate
    system; only their anchor point is mapped.
    """

    var value: Int

    comptime TOP = Align(0)
    comptime CENTER = Align(1)
    comptime BOTTOM = Align(2)
    comptime LEFT = Align(3)
    comptime RIGHT = Align(4)
    comptime TOP_LEFT = Align(5)
    comptime BOTTOM_LEFT = Align(6)
    comptime TOP_RIGHT = Align(7)
    comptime BOTTOM_RIGHT = Align(8)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: Align) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Align) -> Bool:
        return self.value != other.value

    # The two axes, decoded for layout. Internal: a consumer picks a point,
    # not an axis, so only the text layout ever asks which half of one it is.

    def _left(self) -> Bool:
        return (
            self == Align.LEFT
            or self == Align.TOP_LEFT
            or self == Align.BOTTOM_LEFT
        )

    def _right(self) -> Bool:
        return (
            self == Align.RIGHT
            or self == Align.TOP_RIGHT
            or self == Align.BOTTOM_RIGHT
        )

    def _top(self) -> Bool:
        return (
            self == Align.TOP
            or self == Align.TOP_LEFT
            or self == Align.TOP_RIGHT
        )

    def _bottom(self) -> Bool:
        return (
            self == Align.BOTTOM
            or self == Align.BOTTOM_LEFT
            or self == Align.BOTTOM_RIGHT
        )
