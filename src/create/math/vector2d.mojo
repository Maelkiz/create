from std.math import sqrt


struct Vector2D(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """A 2D displacement or direction: arithmetic operators, `mag`, `normalize`,
    `dot`, `dist`, `lerp`, and `xy`/`xyz` to hand the components to another
    type.

    Unlike `Point2D`, a bare tuple does not convert to one implicitly: a
    displacement literal names its type, `rect.translate(Vector2D(3, 4))`.
    Only one type taking a bare tuple is what keeps `canvas.circle((0, 0), 20)`
    unambiguous, and locations are the literals a program writes most;
    displacements mostly arrive from arithmetic (`b - a`, `vel * dt`), which
    already yields a `Vector2D`.

    `xy` and `xyz` return plain tuples, which destructure and bind to a
    `Point2D` parameter; the explicit tuple constructors take them the rest of
    the way: `Vector3D(v.xyz())`. Having to name the accessor is what keeps
    the conversion visible.
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

    @staticmethod
    def zero() -> Vector2D:
        return Vector2D(0.0, 0.0)

    @staticmethod
    def one() -> Vector2D:
        return Vector2D(1.0, 1.0)

    def __add__(self, other: Vector2D) -> Vector2D:
        return Vector2D(self.x + other.x, self.y + other.y)

    def __sub__(self, other: Vector2D) -> Vector2D:
        return Vector2D(self.x - other.x, self.y - other.y)

    def __mul__(self, s: Float64) -> Vector2D:
        return Vector2D(self.x * s, self.y * s)

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

    def mag(self) -> Float64:
        return sqrt(self.x * self.x + self.y * self.y)

    def mag_sq(self) -> Float64:
        return self.x * self.x + self.y * self.y

    def normalize(self) -> Vector2D:
        var m = self.mag()
        return Vector2D(self.x / m, self.y / m)

    def dot(self, other: Vector2D) -> Float64:
        return self.x * other.x + self.y * other.y

    def dist(self, other: Vector2D) -> Float64:
        return (self - other).mag()

    def dist_sq(self, other: Vector2D) -> Float64:
        return (self - other).mag_sq()

    def lerp(self, other: Vector2D, t: Float64) -> Vector2D:
        return Vector2D(
            self.x + (other.x - self.x) * t, self.y + (other.y - self.y) * t
        )

    def xy(self) -> Tuple[Float64, Float64]:
        return (self.x, self.y)

    def xyz(self, z: Float64 = 0.0) -> Tuple[Float64, Float64, Float64]:
        return (self.x, self.y, z)
