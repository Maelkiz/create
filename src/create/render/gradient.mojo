from std.math import abs, max, min, sqrt
from std.memory import ArcPointer

from .color import Color, _scaled_alpha
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D


comptime _LINEAR = 0
comptime _RADIAL = 1

comptime _DEGENERATE = 1e-9
"""Below this, a direction has no line to run along and a box no extent to
span: the gradient paints its first stop. Small rather than zero, because
normalising a vector like `Vector2D(1e-300, 0)` loses precision."""


def _premultiplied(c: Color) -> SIMD[DType.float64, 4]:
    var a = Float64(Int(c.a)) / 255.0
    return SIMD[DType.float64, 4](
        Float64(Int(c.r)) * a, Float64(Int(c.g)) * a, Float64(Int(c.b)) * a, a
    )


def _byte(v: Float64) -> UInt8:
    return UInt8(Int(min(max(v, 0.0), 255.0) + 0.5))


def _straight(p: SIMD[DType.float64, 4]) -> Color:
    """Undo `_premultiplied`: back to a straight-alpha `Color`."""
    var a = p[3]
    if a <= 0.0:
        return Color.TRANSPARENT
    return Color(
        _byte(p[0] / a), _byte(p[1] / a), _byte(p[2] / a), _byte(a * 255.0)
    )


struct Gradient(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A smooth run of colours across a shape's fill, or across the
    background.

    ```mojo
    var sky = Gradient.linear(Color.hex(0x0B1D3A), Color.hex(0xF4A261))
    canvas.background(sky)
    canvas.fill(Gradient.radial(Color.WHITE, Color.WHITE.with_alpha(0)))
    canvas.circle((0, 0), 80)
    ```

    **Placed by the shape, not the world.** A gradient spans the bounding box
    of the shape it fills, in the shape's own coordinates, so it moves and
    turns with the shape and one `Style` looks the same on every entity.

    - `linear` runs along `direction`, top to bottom by default. The line is
      just long enough for the box's two farthest corners to land exactly on
      the first and last stop, as in CSS.
    - `radial` runs out from `center`, given in the box's own unit space
      (`(0, 0)` its middle, `(1, 1)` its top-right corner), to the box's
      edges: a circle on a square box, an ellipse on a long one. Its size
      stays put when `center` moves.

    **Stops** are positions from 0 to 1, each with a colour. Given only
    colours, they are spaced evenly; given `(position, colour)` pairs, each
    position is clamped to 0..1 and to no less than the stop before it.
    Before the first stop and after the last, the end colours carry on.
    Colours blend premultiplied, so a fade to `Color.TRANSPARENT` doesn't
    pass through grey.

    A zero `direction` has no line to run along, and a box with no width (or
    height) has nothing to span, so the gradient paints its first stop.
    `direction` is kept as given, so `==` and printing round-trip.

    Copying one is cheap: the stops are shared, never changed after
    construction.
    """

    var _kind: Int
    var _stops: ArcPointer[List[Tuple[Float64, Color]]]
    var direction: Vector2D
    """`linear` only: which way the colours run, first stop to last."""
    var center: Point2D
    """`radial` only: where the first stop sits, in the box's unit space."""

    def __init__(
        out self,
        *,
        kind: Int,
        var stops: List[Tuple[Float64, Color]],
        direction: Vector2D,
        center: Point2D,
    ):
        var floor = 0.0
        for i in range(len(stops)):
            var position = max(min(stops[i][0], 1.0), floor)
            stops[i] = (position, stops[i][1])
            floor = position
        self._kind = kind
        self._stops = ArcPointer(stops^)
        self.direction = direction
        self.center = center

    @staticmethod
    def _even(
        first: Color, rest: VariadicList[Color, _]
    ) -> List[Tuple[Float64, Color]]:
        var stops: List[Tuple[Float64, Color]] = [(0.0, first)]
        var n = len(rest)
        for i in range(n):
            stops.append((Float64(i + 1) / Float64(n), rest[i]))
        return stops^

    @staticmethod
    def linear(
        first: Color, *rest: Color, direction: Vector2D = Vector2D.DOWN
    ) -> Gradient:
        """Evenly spaced colours along `direction`; one colour is a solid."""
        return Gradient(
            kind=_LINEAR,
            stops=Gradient._even(first, rest),
            direction=direction,
            center=Point2D(0.0, 0.0),
        )

    @staticmethod
    def linear(
        stops: List[Tuple[Float64, Color]],
        direction: Vector2D = Vector2D.DOWN,
    ) -> Gradient:
        """Colours at the given positions along `direction`:
        `Gradient.linear([(0.0, Color.NAVY), (0.7, Color.PURPLE), (1.0, Color.ORANGE)])`.
        """
        return Gradient(
            kind=_LINEAR,
            stops=stops.copy(),
            direction=direction,
            center=Point2D(0.0, 0.0),
        )

    @staticmethod
    def radial(
        first: Color, *rest: Color, center: Point2D = Point2D(0.0, 0.0)
    ) -> Gradient:
        """Evenly spaced colours out from `center` to the box's edges."""
        return Gradient(
            kind=_RADIAL,
            stops=Gradient._even(first, rest),
            direction=Vector2D.DOWN,
            center=center,
        )

    @staticmethod
    def radial(
        stops: List[Tuple[Float64, Color]],
        center: Point2D = Point2D(0.0, 0.0),
    ) -> Gradient:
        """Colours at the given positions out from `center` to the box's
        edges."""
        return Gradient(
            kind=_RADIAL,
            stops=stops.copy(),
            direction=Vector2D.DOWN,
            center=center,
        )

    def __eq__(self, other: Gradient) -> Bool:
        if self._kind != other._kind or len(self._stops[]) != len(
            other._stops[]
        ):
            return False
        if self._kind == _LINEAR and self.direction != other.direction:
            return False
        if self._kind == _RADIAL and self.center != other.center:
            return False
        for i in range(len(self._stops[])):
            if (
                self._stops[][i][0] != other._stops[][i][0]
                or self._stops[][i][1] != other._stops[][i][1]
            ):
                return False
        return True

    def __ne__(self, other: Gradient) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        # The stops form always, so the output reads back exactly.
        writer.write(
            "Gradient.linear([" if self._kind
            == _LINEAR else "Gradient.radial(["
        )
        for i in range(len(self._stops[])):
            if i > 0:
                writer.write(", ")
            writer.write(
                "(", self._stops[][i][0], ", ", self._stops[][i][1], ")"
            )
        if self._kind == _LINEAR:
            writer.write("], direction=", self.direction, ")")
        else:
            writer.write("], center=", self.center, ")")

    def _at(self, t: Float64) -> Color:
        """The colour at parameter `t`, blended premultiplied between the
        stops either side; the end colours carry on past them. Where two
        stops share a position (a hard edge), `t` at it takes the later."""
        ref stops = self._stops[]
        var n = len(stops)
        if n == 0:
            return Color.TRANSPARENT
        if t < stops[0][0]:
            return stops[0][1]
        for i in range(1, n):
            var p1 = stops[i][0]
            if t < p1:
                var p0 = stops[i - 1][0]
                var f = (t - p0) / (p1 - p0)
                var a = _premultiplied(stops[i - 1][1])
                var b = _premultiplied(stops[i][1])
                return _straight(a + (b - a) * f)
        return stops[n - 1][1]

    def _t_at(self, local: Point2D, center: Point2D, half: Vector2D) -> Float64:
        """The gradient parameter at `local`, for a box centred on `center`
        with half-extents `half`, all in the shape's own coordinates. 0 for
        a degenerate direction or box, which `_at` maps to the first stop."""
        var p = local - center
        if self._kind == _LINEAR:
            var length = self.direction.mag()
            if length < _DEGENERATE:
                return 0.0
            var dx = self.direction.x / length
            var dy = self.direction.y / length
            var reach = half.x * abs(dx) + half.y * abs(dy)
            if reach < _DEGENERATE:
                return 0.0
            return 0.5 + (p.x * dx + p.y * dy) / (2.0 * reach)
        if half.x < _DEGENERATE or half.y < _DEGENERATE:
            return 0.0
        var u = p.x / half.x - self.center.x
        var v = p.y / half.y - self.center.y
        return sqrt(u * u + v * v)

    def _opaque(self) -> Bool:
        """Whether every pixel it paints is opaque: every stop is."""
        ref stops = self._stops[]
        if len(stops) == 0:
            return False
        for i in range(len(stops)):
            if stops[i][1].a != 255:
                return False
        return True

    def _visible(self) -> Bool:
        """Whether it paints anything at all: some stop isn't transparent."""
        ref stops = self._stops[]
        for i in range(len(stops)):
            if stops[i][1].a > 0:
                return True
        return False

    def _with_opacity(self, opacity: Float64) -> Gradient:
        """The same gradient with every stop's alpha scaled by `opacity`, as a
        command resolves a colour's."""
        var stops = self._stops[].copy()
        for i in range(len(stops)):
            stops[i] = (stops[i][0], _scaled_alpha(stops[i][1], opacity))
        return Gradient(
            kind=self._kind,
            stops=stops^,
            direction=self.direction,
            center=self.center,
        )
