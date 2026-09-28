from std.math import floor, clamp
from std.time import perf_counter_ns

from .point2d import Point2D
from .random import Random
from .util import lerp


struct Noise(Copyable, Movable):
    """Smooth pseudo-random values: `.at(x)`, `.at(position)` and
    `.at(position, time)`, each in `[0.0, 1.0]`.

    Where `Random` gives independent samples that jump from one call to the
    next, `Noise` is a field: nearby inputs give nearby values, so a terrain
    height, a wandering position or a flow-field angle drifts instead of
    jittering. The range is `Random.float()`'s, so it swaps in wherever the
    jitter should be smooth; `lerp(-a, a, n)` makes it signed.

    `Noise()` seeds itself from the clock and `Noise(seed)` takes one; the same
    seed always gives the same field. Nothing changes after construction, so
    `.at` reads rather than advances, and a copy is the same field.

    `feature_size` is the distance, in the units passed to `.at`, over which
    the field goes from one value to an unrelated one: hills about 120 units
    across are `Noise(feature_size=120)`. It divides `x` and `position` but
    not `time`, so an animation's rate is set at the call,
    `noise.at(position, time=t * 0.3)`, independently of the spatial scale.

    `octaves` layers the field over itself at doubling frequencies, each
    layer's weight `falloff` times the last: one octave is plain, blobby
    Perlin; the default four at 0.5 add the finer detail of a coastline or a
    cloud edge. The layers are averaged by weight, so the range stays
    `[0, 1]`.

    Improved Perlin noise (2002). Its value at a whole-number lattice point,
    after dividing by `feature_size`, is exactly 0.5.
    """

    var _seed: UInt64
    var _octaves: Int
    var _falloff: Float64
    var _feature_size: Float64
    var _permutation: List[UInt8]

    def __init__(
        out self,
        *,
        octaves: Int = 4,
        falloff: Float64 = 0.5,
        feature_size: Float64 = 1.0,
    ):
        # The clock value is kept as the seed, so the field can be rebuilt.
        self = Self(
            UInt64(perf_counter_ns()),
            octaves=octaves,
            falloff=falloff,
            feature_size=feature_size,
        )

    def __init__(
        out self,
        seed: UInt64,
        *,
        octaves: Int = 4,
        falloff: Float64 = 0.5,
        feature_size: Float64 = 1.0,
    ):
        debug_assert(octaves >= 1, "Noise: octaves must be at least 1")
        debug_assert(falloff > 0, "Noise: falloff must be greater than 0")
        debug_assert(
            feature_size > 0, "Noise: feature_size must be greater than 0"
        )
        self._seed = seed
        self._octaves = octaves
        self._falloff = falloff
        self._feature_size = feature_size
        self._permutation = List[UInt8](capacity=256)
        for i in range(256):
            self._permutation.append(UInt8(i))
        # Fisher-Yates: the seed picks one of the 256! orderings.
        var rng = Random(seed)
        for i in range(255, 0, -1):
            var j = rng.int(0, i + 1)
            var swap = self._permutation[i]
            self._permutation[i] = self._permutation[j]
            self._permutation[j] = swap

    def at(self, x: Float64) -> Float64:
        """The field along a line: a value that wanders smoothly as `x` (a
        time, say) moves."""
        return self._layered[1](x / self._feature_size, 0.0, 0.0)

    def at(self, position: Point2D) -> Float64:
        """The field over the plane: terrain, texture, a flow-field angle."""
        return self._layered[2](
            position.x / self._feature_size,
            position.y / self._feature_size,
            0.0,
        )

    def at(self, position: Point2D, time: Float64) -> Float64:
        """The plane field, animated: it evolves smoothly as `time` moves.
        `time` is not divided by `feature_size`; scale it at the call."""
        return self._layered[3](
            position.x / self._feature_size,
            position.y / self._feature_size,
            time,
        )

    def _layered[
        dimensions: Int
    ](self, x: Float64, y: Float64, z: Float64) -> Float64:
        # Sum the octaves, then divide by the total weight: every kernel
        # reaches at most ±1, so the average does too, and the clamp only
        # guards rounding. Time doubles with space, so finer layers also
        # change faster.
        var total = 0.0
        var weight = 1.0
        var weight_sum = 0.0
        var frequency = 1.0
        for _ in range(self._octaves):
            comptime if dimensions == 1:
                total += weight * self._raw1(x * frequency)
            elif dimensions == 2:
                total += weight * self._raw2(x * frequency, y * frequency)
            else:
                total += weight * self._raw3(
                    x * frequency, y * frequency, z * frequency
                )
            weight_sum += weight
            weight *= self._falloff
            frequency *= 2.0
        return clamp(0.5 + 0.5 * total / weight_sum, 0.0, 1.0)

    @staticmethod
    def _fade(t: Float64) -> Float64:
        # 6t⁵ − 15t⁴ + 10t³: flat first and second derivatives at 0 and 1, so
        # cells join without visible creases.
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

    def _hash(self, i: Int) -> Int:
        return Int(self._permutation[i & 255])

    @staticmethod
    def _gradient1(hash: Int, x: Float64) -> Float64:
        return x if hash & 1 == 0 else -x

    @staticmethod
    def _gradient2(hash: Int, x: Float64, y: Float64) -> Float64:
        # Eight directions: the four diagonals, then the four axes.
        var h = hash & 7
        if h < 4:
            var u = x if h & 1 == 0 else -x
            var v = y if h & 2 == 0 else -y
            return u + v
        if h == 4:
            return x
        if h == 5:
            return -x
        if h == 6:
            return y
        return -y

    @staticmethod
    def _gradient3(hash: Int, x: Float64, y: Float64, z: Float64) -> Float64:
        # Perlin's twelve cube-edge directions, four of them repeated to
        # fill sixteen slots.
        var h = hash & 15
        var u = x if h < 8 else y
        var v = y if h < 4 else (x if h == 12 or h == 14 else z)
        return (u if h & 1 == 0 else -u) + (v if h & 2 == 0 else -v)

    def _raw1(self, x: Float64) -> Float64:
        var cell = floor(x)
        var i = Int(cell)
        var f = x - cell
        # Peaks at ±0.5 mid-cell; doubled to reach ±1.
        return 2.0 * lerp(
            Self._gradient1(self._hash(i), f),
            Self._gradient1(self._hash(i + 1), f - 1.0),
            Self._fade(f),
        )

    def _raw2(self, x: Float64, y: Float64) -> Float64:
        var cell_x = floor(x)
        var cell_y = floor(y)
        var i = Int(cell_x)
        var j = Int(cell_y)
        var fx = x - cell_x
        var fy = y - cell_y
        var a = self._hash(i) + j
        var b = self._hash(i + 1) + j
        var u = Self._fade(fx)
        # Diagonal gradients of length √2 reach ±1 at a cell's centre.
        return lerp(
            lerp(
                Self._gradient2(self._hash(a), fx, fy),
                Self._gradient2(self._hash(b), fx - 1.0, fy),
                u,
            ),
            lerp(
                Self._gradient2(self._hash(a + 1), fx, fy - 1.0),
                Self._gradient2(self._hash(b + 1), fx - 1.0, fy - 1.0),
                u,
            ),
            Self._fade(fy),
        )

    def _raw3(self, x: Float64, y: Float64, z: Float64) -> Float64:
        var cell_x = floor(x)
        var cell_y = floor(y)
        var cell_z = floor(z)
        var i = Int(cell_x)
        var j = Int(cell_y)
        var k = Int(cell_z)
        var fx = x - cell_x
        var fy = y - cell_y
        var fz = z - cell_z
        var a = self._hash(i) + j
        var aa = self._hash(a) + k
        var ab = self._hash(a + 1) + k
        var b = self._hash(i + 1) + j
        var ba = self._hash(b) + k
        var bb = self._hash(b + 1) + k
        var u = Self._fade(fx)
        var v = Self._fade(fy)
        return lerp(
            lerp(
                lerp(
                    Self._gradient3(self._hash(aa), fx, fy, fz),
                    Self._gradient3(self._hash(ba), fx - 1.0, fy, fz),
                    u,
                ),
                lerp(
                    Self._gradient3(self._hash(ab), fx, fy - 1.0, fz),
                    Self._gradient3(self._hash(bb), fx - 1.0, fy - 1.0, fz),
                    u,
                ),
                v,
            ),
            lerp(
                lerp(
                    Self._gradient3(self._hash(aa + 1), fx, fy, fz - 1.0),
                    Self._gradient3(self._hash(ba + 1), fx - 1.0, fy, fz - 1.0),
                    u,
                ),
                lerp(
                    Self._gradient3(self._hash(ab + 1), fx, fy - 1.0, fz - 1.0),
                    Self._gradient3(
                        self._hash(bb + 1), fx - 1.0, fy - 1.0, fz - 1.0
                    ),
                    u,
                ),
                v,
            ),
            Self._fade(fz),
        )
