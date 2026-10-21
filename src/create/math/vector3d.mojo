from std.math import sqrt

from .point2d import Point2D
from .vector2d import Vector2D


struct Vector3D(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A 3D point or direction: arithmetic operators, `magnitude`, `normalize`,
    `dot`, `cross`, `distance`, `lerp`, and explicit constructors from the 2D
    types.

    Rendering is 2D, so nothing in the library takes one — it is here for a
    program doing its own 3D work.

    A bare tuple does not convert to one implicitly -- a literal names its
    type, `Vector3D(1, 2, 3)`. Crossing from 2D is an explicit constructor,
    `Vector3D(v, z)` or `Vector3D(p, z)`, and back is `Vector2D(v3)`, which
    drops `z`. `xy` and `xyz` return the components as plain tuples, to
    destructure.
    """

    var x: Float64
    var y: Float64
    var z: Float64

    def __init__(out self, x: Float64, y: Float64, z: Float64):
        self.x = x
        self.y = y
        self.z = z

    def __init__(out self, x: Int, y: Int, z: Int):
        self = Vector3D(Float64(x), Float64(y), Float64(z))

    def __init__(out self, v: Vector2D, z: Float64 = 0.0):
        """`v` raised to a height of `z`."""
        self = Vector3D(v.x, v.y, z)

    def __init__(out self, p: Point2D, z: Float64 = 0.0):
        """The position `p` raised to a height of `z`, as a 3D vector."""
        self = Vector3D(p.x, p.y, z)

    def __init__(out self, t: Tuple[Float64, Float64, Float64]):
        self = Vector3D(t[0], t[1], t[2])

    def __add__(self, other: Vector3D) -> Vector3D:
        return Vector3D(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other: Vector3D) -> Vector3D:
        return Vector3D(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, s: Float64) -> Vector3D:
        return Vector3D(self.x * s, self.y * s, self.z * s)

    def __truediv__(self, s: Float64) -> Vector3D:
        return Vector3D(self.x / s, self.y / s, self.z / s)

    def __neg__(self) -> Vector3D:
        return Vector3D(-self.x, -self.y, -self.z)

    def __iadd__(mut self, other: Vector3D):
        self.x += other.x
        self.y += other.y
        self.z += other.z

    def __isub__(mut self, other: Vector3D):
        self.x -= other.x
        self.y -= other.y
        self.z -= other.z

    def __imul__(mut self, s: Float64):
        self.x *= s
        self.y *= s
        self.z *= s

    def __itruediv__(mut self, s: Float64):
        self.x /= s
        self.y /= s
        self.z /= s

    def __eq__(self, other: Vector3D) -> Bool:
        return self.x == other.x and self.y == other.y and self.z == other.z

    def __ne__(self, other: Vector3D) -> Bool:
        return not (self == other)

    def write_to[W: Writer](self, mut writer: W):
        writer.write("Vector3D(", self.x, ", ", self.y, ", ", self.z, ")")

    def magnitude(self) -> Float64:
        return sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    def magnitude_squared(self) -> Float64:
        return self.x * self.x + self.y * self.y + self.z * self.z

    def normalize(self) -> Vector3D:
        var m = self.magnitude()
        return Vector3D(self.x / m, self.y / m, self.z / m)

    def dot(self, other: Vector3D) -> Float64:
        return self.x * other.x + self.y * other.y + self.z * other.z

    def cross(self, other: Vector3D) -> Vector3D:
        return Vector3D(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def distance(self, other: Vector3D) -> Float64:
        return (self - other).magnitude()

    def distance_squared(self, other: Vector3D) -> Float64:
        return (self - other).magnitude_squared()

    def lerp(self, other: Vector3D, t: Float64) -> Vector3D:
        return Vector3D(
            self.x + (other.x - self.x) * t,
            self.y + (other.y - self.y) * t,
            self.z + (other.z - self.z) * t,
        )

    def xy(self) -> Tuple[Float64, Float64]:
        return (self.x, self.y)

    def xyz(self) -> Tuple[Float64, Float64, Float64]:
        return (self.x, self.y, self.z)

    comptime ZERO = Vector3D(0.0, 0.0, 0.0)
    comptime ONE = Vector3D(1.0, 1.0, 1.0)
