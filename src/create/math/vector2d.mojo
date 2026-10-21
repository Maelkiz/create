from std.math import sqrt

from .point2d import Point2D
from .vector3d import Vector3D


struct Vector2D(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A 2D displacement or direction: arithmetic operators, `magnitude`, `normalize`,
    `dot`, `distance`, `lerp`, and explicit constructors from a `Point2D` or a
    `Vector3D`.

    Unlike `Point2D`, a bare tuple does not convert to one implicitly: a
    displacement literal names its type, `rect.translate(Vector2D(3, 4))`.
    Only one type taking a bare tuple is what keeps `canvas.circle((0, 0), 20)`
    unambiguous, and locations are the literals a program writes most;
    displacements mostly arrive from arithmetic (`b - a`, `vel * dt`), which
    already yields a `Vector2D`.

    Crossing to another type is an explicit constructor: `Vector2D(p)` is
    the displacement from the origin to the position `p`, `Vector2D(v3)`
    drops `z`, and `Vector3D(v, z)` widens. Naming the target type is what
    keeps the conversion visible. `xy` returns the components as a plain
    tuple, to destructure: `var (x, y) = v.xy()`.

    The direction constants follow the screen's axes, y up: `UP` is
    `Vector2D(0, 1)` and `DOWN` is `Vector2D(0, -1)`, so gravity is
    `Vector2D.DOWN * 9.81`.
    """

    var x: Float64
    var y: Float64

    def __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y

    def __init__(out self, x: Int, y: Int):
        self = Vector2D(Float64(x), Float64(y))

    def __init__(out self, t: Tuple[Float64, Float64]):
        self = Vector2D(t[0], t[1])

    def __init__(out self, p: Point2D):
        """The displacement from the origin to `p`."""
        self = Vector2D(p.x, p.y)

    def __init__(out self, v: Vector3D):
        """`v` without its `z`."""
        self = Vector2D(v.x, v.y)

    def __add__(self, other: Vector2D) -> Vector2D:
        return Vector2D(self.x + other.x, self.y + other.y)

    def __sub__(self, other: Vector2D) -> Vector2D:
        return Vector2D(self.x - other.x, self.y - other.y)

    def __mul__(self, s: Float64) -> Vector2D:
        return Vector2D(self.x * s, self.y * s)

    def __rmul__(self, s: Float64) -> Vector2D:
        """`s * v`, the same as `v * s`, so a formula reads as written."""
        return self * s

    def __truediv__(self, s: Float64) -> Vector2D:
        return Vector2D(self.x / s, self.y / s)

    def __neg__(self) -> Vector2D:
        return Vector2D(-self.x, -self.y)

    def __iadd__(mut self, other: Vector2D):
        self.x += other.x
        self.y += other.y

    def __isub__(mut self, other: Vector2D):
        self.x -= other.x
        self.y -= other.y

    def __imul__(mut self, s: Float64):
        self.x *= s
        self.y *= s

    def __itruediv__(mut self, s: Float64):
        self.x /= s
        self.y /= s

    def __eq__(self, other: Vector2D) -> Bool:
        return self.x == other.x and self.y == other.y

    def __ne__(self, other: Vector2D) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Vector2D(", self.x, ", ", self.y, ")")

    def magnitude(self) -> Float64:
        return sqrt(self.x * self.x + self.y * self.y)

    def magnitude_squared(self) -> Float64:
        return self.x * self.x + self.y * self.y

    def normalize(self) -> Vector2D:
        var m = self.magnitude()
        return Vector2D(self.x / m, self.y / m)

    def dot(self, other: Vector2D) -> Float64:
        return self.x * other.x + self.y * other.y

    def distance(self, other: Vector2D) -> Float64:
        return (self - other).magnitude()

    def distance_squared(self, other: Vector2D) -> Float64:
        return (self - other).magnitude_squared()

    def lerp(self, other: Vector2D, t: Float64) -> Vector2D:
        return Vector2D(
            self.x + (other.x - self.x) * t, self.y + (other.y - self.y) * t
        )

    def xy(self) -> Tuple[Float64, Float64]:
        return (self.x, self.y)

    comptime ZERO = Vector2D(0.0, 0.0)
    comptime ONE = Vector2D(1.0, 1.0)

    comptime UP = Vector2D(0.0, 1.0)
    comptime DOWN = Vector2D(0.0, -1.0)
    comptime LEFT = Vector2D(-1.0, 0.0)
    comptime RIGHT = Vector2D(1.0, 0.0)
