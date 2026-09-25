from .vector2d import Vector2D


struct Point2D(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A location in world space: `dist`, `lerp`, the affine operators, and
    `xy`/`xyz` to hand the components to another type.

    Every position in the library is one of these — `canvas.circle(pos, r)`,
    `Rectangle.center()`, `input.mouse` — and no signature takes a location
    as a loose x/y pair instead. The tuple constructors are `@implicit`, so
    `canvas.circle((0, 0), 20)` works without naming the type and a program
    only spells `Point2D` when it is storing one. It is the only type here
    that converts from a bare tuple, which is what keeps that unambiguous.

    The surface is strictly affine, which is the whole point of the type
    existing beside `Vector2D`: subtracting two positions gives the
    displacement between them (`Vector2D`), and adding a displacement to a
    position gives another position. `mag`, `normalize`, `dot`, scalar `*`,
    unary `-` and `Point2D + Point2D` are absent on purpose — none of them
    means anything for a location, and `pos.normalize()` compiling was the
    mistake this split exists to catch. A program that genuinely wants a
    position's components as a direction says so: `Vector2D(p.xy())`.

    A displacement is always named: `p + Vector2D(1, 2)` moves a position.
    Mind `p - (1, 2)`: the tuple can only become a `Point2D`, so it is the
    displacement from `(1, 2)` to `p` -- a `Vector2D`, not a moved position.
    Moving backwards is `p - Vector2D(1, 2)`.

    There are no `zero()`/`one()` factories either. `(0, 0)` through the
    implicit constructor is shorter than any name for the origin, and `one()`
    has no meaning for a position at all.

    `xy` and `xyz` return plain tuples rather than a vector type: they
    destructure, and go through a vector's explicit tuple constructor,
    `Vector2D(p.xy())`. Having to name the accessor is what keeps the
    conversion visible.
    """

    var x: Float64
    var y: Float64

    def __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y

    def __init__(out self, x: Int, y: Int):
        self = Point2D(Float64(x), Float64(y))

    @implicit
    def __init__(out self, t: Tuple[Float64, Float64]):
        self = Point2D(t[0], t[1])

    @implicit
    def __init__(out self, t: Tuple[Int, Int]):
        self = Point2D(Float64(t[0]), Float64(t[1]))

    @implicit
    def __init__(out self, t: Tuple[Int, Float64]):
        self = Point2D(Float64(t[0]), t[1])

    @implicit
    def __init__(out self, t: Tuple[Float64, Int]):
        self = Point2D(t[0], Float64(t[1]))

    def __sub__(self, other: Point2D) -> Vector2D:
        """The displacement from `other` to `self`."""
        return Vector2D(self.x - other.x, self.y - other.y)

    def __add__(self, v: Vector2D) -> Point2D:
        return Point2D(self.x + v.x, self.y + v.y)

    def __sub__(self, v: Vector2D) -> Point2D:
        return Point2D(self.x - v.x, self.y - v.y)

    def __iadd__(mut self, v: Vector2D):
        self.x += v.x
        self.y += v.y

    def __isub__(mut self, v: Vector2D):
        self.x -= v.x
        self.y -= v.y

    def __eq__(self, other: Point2D) -> Bool:
        return self.x == other.x and self.y == other.y

    def __ne__(self, other: Point2D) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Point2D(", self.x, ", ", self.y, ")")

    def dist(self, other: Point2D) -> Float64:
        return (self - other).mag()

    def dist_sq(self, other: Point2D) -> Float64:
        return (self - other).mag_sq()

    def lerp(self, other: Point2D, t: Float64) -> Point2D:
        return Point2D(
            self.x + (other.x - self.x) * t, self.y + (other.y - self.y) * t
        )

    def xy(self) -> Tuple[Float64, Float64]:
        return (self.x, self.y)

    def xyz(self, z: Float64 = 0.0) -> Tuple[Float64, Float64, Float64]:
        return (self.x, self.y, z)
