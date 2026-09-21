from std.time import perf_counter_ns


struct Random(Movable):
    """A seeded pseudo-random generator: `.float()`, `.int()`, `.bool()`.

    `Random()` seeds itself from the clock and `Random(seed)` takes one, which
    is the difference that matters: a seeded generator replays the same
    sequence every run, so a procedurally generated level or a particle burst
    can be reproduced exactly while it is being tuned.

    xoroshiro128++ — fast and well-distributed, not cryptographic. Don't render
    keys or tokens from it.
    """

    var _s0: UInt64
    var _s1: UInt64

    def __init__(out self):
        # Seeded from nanosecond timer — not cryptographically random,
        # but collision probability is negligible for normal use.
        self = Self(UInt64(perf_counter_ns()))

    def __init__(out self, seed: UInt64):
        # SplitMix64 to initialize state from seed — avoids bad zero states
        var z = seed + 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) * 0x94D049BB133111EB
        self._s0 = z ^ (z >> 31)
        z = self._s0 + 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) * 0x94D049BB133111EB
        self._s1 = z ^ (z >> 31)

    @staticmethod
    def _rotl(x: UInt64, k: Int) -> UInt64:
        return (x << UInt64(k)) | (x >> UInt64(64 - k))

    def _next(mut self) -> UInt64:
        var s0 = self._s0
        var s1 = self._s1
        var result = Self._rotl(s0 + s1, 17) + s0
        s1 ^= s0
        self._s0 = Self._rotl(s0, 49) ^ s1 ^ (s1 << 21)
        self._s1 = Self._rotl(s1, 28)
        return result

    def float(mut self) -> Float64:
        """A number in `[0.0, 1.0)` — 1.0 itself is never returned."""
        return Float64(self._next()) / (Float64(UInt64.MAX) + 1.0)

    def float(mut self, low: Float64, high: Float64) -> Float64:
        """A number in `[low, high)`."""
        return low + self.float() * (high - low)

    def int(mut self, low: Int, high: Int) -> Int:
        """A whole number in `[low, high)` — `high` is excluded, so
        `r.int(0, len(items))` indexes a list without going off the end."""
        debug_assert(high > low, "Random.int: high must be greater than low")
        return low + Int(self._next() % UInt64(high - low))

    def bool(mut self) -> Bool:
        """A coin flip — `True` half the time."""
        return self._next() & 1 == 1
