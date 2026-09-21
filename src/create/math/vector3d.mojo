from std.math import sqrt


struct Vector3D(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A 3D point or direction: arithmetic operators, `mag`, `normalize`,
    `dot`, `cross`, `dist`, `lerp`, and `xy`/`xyz` to hand the components to
    another type — `xy` dropping `z`.

    Rendering is 2D, so nothing in the library takes one — it is here for a
    program doing its own 3D work.

    Both accessors return plain tuples rather than a `Vector2D`, which is
    strictly more capable given the `@implicit` tuple constructors every
    vector type here has: `v.xy()` still binds to a `Vector2D` parameter, and
    it destructures as well. Having to name the accessor is what keeps the
    conversion visible.
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

    @implicit
    def __init__(out self, t: Tuple[Float64, Float64, Float64]):
        self = Vector3D(t[0], t[1], t[2])

    @implicit
    def __init__(out self, t: Tuple[Int, Int, Int]):
        self = Vector3D(Float64(t[0]), Float64(t[1]), Float64(t[2]))

    @implicit
    def __init__(out self, t: Tuple[Float64, Int, Int]):
        self = Vector3D(t[0], Float64(t[1]), Float64(t[2]))

    @implicit
    def __init__(out self, t: Tuple[Int, Float64, Int]):
        self = Vector3D(Float64(t[0]), t[1], Float64(t[2]))

    @implicit
    def __init__(out self, t: Tuple[Int, Int, Float64]):
        self = Vector3D(Float64(t[0]), Float64(t[1]), t[2])

    @implicit
    def __init__(out self, t: Tuple[Float64, Float64, Int]):
        self = Vector3D(t[0], t[1], Float64(t[2]))

    @implicit
    def __init__(out self, t: Tuple[Int, Float64, Float64]):
        self = Vector3D(Float64(t[0]), t[1], t[2])

    @implicit
    def __init__(out self, t: Tuple[Float64, Int, Float64]):
        self = Vector3D(t[0], Float64(t[1]), t[2])

    @staticmethod
    def zero() -> Vector3D:
        return Vector3D(0.0, 0.0, 0.0)

    @staticmethod
    def one() -> Vector3D:
        return Vector3D(1.0, 1.0, 1.0)

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

    def mag(self) -> Float64:
        return sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    def mag_sq(self) -> Float64:
        return self.x * self.x + self.y * self.y + self.z * self.z

    def normalize(self) -> Vector3D:
        var m = self.mag()
        return Vector3D(self.x / m, self.y / m, self.z / m)

    def dot(self, other: Vector3D) -> Float64:
        return self.x * other.x + self.y * other.y + self.z * other.z

    def cross(self, other: Vector3D) -> Vector3D:
        return Vector3D(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def dist(self, other: Vector3D) -> Float64:
        return (self - other).mag()

    def dist_sq(self, other: Vector3D) -> Float64:
        return (self - other).mag_sq()

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
