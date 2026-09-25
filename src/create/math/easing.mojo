"""Easing curves for animation — the shape of a 0-to-1 fraction over time.

An easing curve reshapes a normalised fraction without changing its endpoints:
`ease(curve, 0.0)` is always 0 and `ease(curve, 1.0)` is always 1, but
everything between is bent. That is what separates a motion that starts and
stops like a physical object from one that moves at a constant rate.

The curves come in three flavours, and the prefix says which end is eased:
`IN_` starts slow and accelerates, `OUT_` starts fast and settles, `IN_OUT_`
does both. `OUT_` is the usual choice for anything responding to input, since
it moves immediately and decelerates into place.

Usable without a `Tween` — it is a plain function, so anything already holding
a fraction can bend it:

```mojo
var t = norm(self.x, 0.0, 300.0)
canvas.circle((0.0, lerp(-200.0, 200.0, ease(Easing.OUT_CUBIC, t))), 20.0)
```

`smoothstep` in [util.mojo](util.mojo) is a near relative but a different
tool: it maps a *range* onto an eased 0..1, where `ease` reshapes a fraction
that is already normalised.
"""

from std.math import sin, cos, pow, pi, tau, clamp


struct Easing(Copyable, Equatable, ImplicitlyCopyable, Movable, Writable):
    """Which curve `ease` applies. A `Tween` stores one as a field.

    A wrapped `Int` rather than a bare one so a stray number cannot be passed
    where a curve is expected.
    """

    var value: Int

    comptime LINEAR = Easing(0)
    """No easing — the fraction passes through unchanged."""

    comptime IN_QUAD = Easing(1)
    comptime OUT_QUAD = Easing(2)
    comptime IN_OUT_QUAD = Easing(3)

    comptime IN_CUBIC = Easing(4)
    comptime OUT_CUBIC = Easing(5)
    comptime IN_OUT_CUBIC = Easing(6)

    comptime IN_SINE = Easing(7)
    comptime OUT_SINE = Easing(8)
    comptime IN_OUT_SINE = Easing(9)

    comptime IN_EXPO = Easing(10)
    comptime OUT_EXPO = Easing(11)
    comptime IN_OUT_EXPO = Easing(12)

    comptime IN_BACK = Easing(13)
    comptime OUT_BACK = Easing(14)
    comptime IN_OUT_BACK = Easing(15)

    comptime IN_ELASTIC = Easing(16)
    comptime OUT_ELASTIC = Easing(17)
    comptime IN_OUT_ELASTIC = Easing(18)

    comptime IN_BOUNCE = Easing(19)
    comptime OUT_BOUNCE = Easing(20)
    comptime IN_OUT_BOUNCE = Easing(21)

    def __init__(out self, value: Int):
        self.value = value

    def __eq__(self, other: Easing) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Easing) -> Bool:
        return self.value != other.value

    def write_to[W: Writer](self, mut writer: W):
        if self == Easing.LINEAR:
            writer.write("Easing.LINEAR")
        elif self == Easing.IN_QUAD:
            writer.write("Easing.IN_QUAD")
        elif self == Easing.OUT_QUAD:
            writer.write("Easing.OUT_QUAD")
        elif self == Easing.IN_OUT_QUAD:
            writer.write("Easing.IN_OUT_QUAD")
        elif self == Easing.IN_CUBIC:
            writer.write("Easing.IN_CUBIC")
        elif self == Easing.OUT_CUBIC:
            writer.write("Easing.OUT_CUBIC")
        elif self == Easing.IN_OUT_CUBIC:
            writer.write("Easing.IN_OUT_CUBIC")
        elif self == Easing.IN_SINE:
            writer.write("Easing.IN_SINE")
        elif self == Easing.OUT_SINE:
            writer.write("Easing.OUT_SINE")
        elif self == Easing.IN_OUT_SINE:
            writer.write("Easing.IN_OUT_SINE")
        elif self == Easing.IN_EXPO:
            writer.write("Easing.IN_EXPO")
        elif self == Easing.OUT_EXPO:
            writer.write("Easing.OUT_EXPO")
        elif self == Easing.IN_OUT_EXPO:
            writer.write("Easing.IN_OUT_EXPO")
        elif self == Easing.IN_BACK:
            writer.write("Easing.IN_BACK")
        elif self == Easing.OUT_BACK:
            writer.write("Easing.OUT_BACK")
        elif self == Easing.IN_OUT_BACK:
            writer.write("Easing.IN_OUT_BACK")
        elif self == Easing.IN_ELASTIC:
            writer.write("Easing.IN_ELASTIC")
        elif self == Easing.OUT_ELASTIC:
            writer.write("Easing.OUT_ELASTIC")
        elif self == Easing.IN_OUT_ELASTIC:
            writer.write("Easing.IN_OUT_ELASTIC")
        elif self == Easing.IN_BOUNCE:
            writer.write("Easing.IN_BOUNCE")
        elif self == Easing.OUT_BOUNCE:
            writer.write("Easing.OUT_BOUNCE")
        elif self == Easing.IN_OUT_BOUNCE:
            writer.write("Easing.IN_OUT_BOUNCE")
        else:
            writer.write("Easing(", self.value, ")")


# Overshoot constant for the BACK curves, and its IN_OUT variant — the amount
# the curve pulls past its endpoint before returning. Penner's originals.
comptime _BACK_1 = 1.70158
comptime _BACK_2 = _BACK_1 * 1.525
comptime _BACK_3 = _BACK_1 + 1.0

# Period constants for the ELASTIC curves: one oscillation per third of the
# travel, halved again for the IN_OUT variant which fits two ends into one run.
comptime _ELASTIC_1 = tau / 3.0
comptime _ELASTIC_2 = tau / 4.5

# The four segments of the BOUNCE curve: each successive bounce is 1/2.75 of
# the remaining travel, at 7.5625 the steepness.
comptime _BOUNCE_N = 7.5625
comptime _BOUNCE_D = 2.75


def _out_bounce(t: Float64) -> Float64:
    """The `OUT_BOUNCE` curve. The other three bounce variants are reflections
    of it, so it is written once here."""
    if t < 1.0 / _BOUNCE_D:
        return _BOUNCE_N * t * t
    if t < 2.0 / _BOUNCE_D:
        var u = t - 1.5 / _BOUNCE_D
        return _BOUNCE_N * u * u + 0.75
    if t < 2.5 / _BOUNCE_D:
        var u = t - 2.25 / _BOUNCE_D
        return _BOUNCE_N * u * u + 0.9375
    var u = t - 2.625 / _BOUNCE_D
    return _BOUNCE_N * u * u + 0.984375


def ease(curve: Easing, t: Float64) -> Float64:
    """Reshape the fraction `t` by `curve`.

    `t` is clamped to 0..1 first — unlike `lerp`, easing does not extrapolate.
    The curves are not linear, so an out-of-range input does not continue the
    motion sensibly: `IN_EXPO` at `t = 2.0` would return 1024.

    The `BACK` and `ELASTIC` curves deliberately leave 0..1 in the *middle* of
    their run, overshooting the target before settling. Anything consuming the
    result as a colour channel or an index has to clamp it.
    """
    var x = clamp(t, 0.0, 1.0)

    if curve == Easing.LINEAR:
        return x

    if curve == Easing.IN_QUAD:
        return x * x
    if curve == Easing.OUT_QUAD:
        return 1.0 - (1.0 - x) * (1.0 - x)
    if curve == Easing.IN_OUT_QUAD:
        if x < 0.5:
            return 2.0 * x * x
        var u = -2.0 * x + 2.0
        return 1.0 - u * u / 2.0

    if curve == Easing.IN_CUBIC:
        return x * x * x
    if curve == Easing.OUT_CUBIC:
        var u = 1.0 - x
        return 1.0 - u * u * u
    if curve == Easing.IN_OUT_CUBIC:
        if x < 0.5:
            return 4.0 * x * x * x
        var u = -2.0 * x + 2.0
        return 1.0 - u * u * u / 2.0

    if curve == Easing.IN_SINE:
        return 1.0 - cos(x * pi / 2.0)
    if curve == Easing.OUT_SINE:
        return sin(x * pi / 2.0)
    if curve == Easing.IN_OUT_SINE:
        return -(cos(pi * x) - 1.0) / 2.0

    if curve == Easing.IN_EXPO:
        if x == 0.0:
            return 0.0
        return pow(2.0, 10.0 * x - 10.0)
    if curve == Easing.OUT_EXPO:
        if x == 1.0:
            return 1.0
        return 1.0 - pow(2.0, -10.0 * x)
    if curve == Easing.IN_OUT_EXPO:
        if x == 0.0:
            return 0.0
        if x == 1.0:
            return 1.0
        if x < 0.5:
            return pow(2.0, 20.0 * x - 10.0) / 2.0
        return (2.0 - pow(2.0, -20.0 * x + 10.0)) / 2.0

    if curve == Easing.IN_BACK:
        return _BACK_3 * x * x * x - _BACK_1 * x * x
    if curve == Easing.OUT_BACK:
        var u = x - 1.0
        return 1.0 + _BACK_3 * u * u * u + _BACK_1 * u * u
    if curve == Easing.IN_OUT_BACK:
        if x < 0.5:
            var u = 2.0 * x
            return u * u * ((_BACK_2 + 1.0) * u - _BACK_2) / 2.0
        var u = 2.0 * x - 2.0
        return (u * u * ((_BACK_2 + 1.0) * u + _BACK_2) + 2.0) / 2.0

    if curve == Easing.IN_ELASTIC:
        if x == 0.0:
            return 0.0
        if x == 1.0:
            return 1.0
        return -pow(2.0, 10.0 * x - 10.0) * sin((10.0 * x - 10.75) * _ELASTIC_1)
    if curve == Easing.OUT_ELASTIC:
        if x == 0.0:
            return 0.0
        if x == 1.0:
            return 1.0
        return pow(2.0, -10.0 * x) * sin((10.0 * x - 0.75) * _ELASTIC_1) + 1.0
    if curve == Easing.IN_OUT_ELASTIC:
        if x == 0.0:
            return 0.0
        if x == 1.0:
            return 1.0
        var s = sin((20.0 * x - 11.125) * _ELASTIC_2)
        if x < 0.5:
            return -(pow(2.0, 20.0 * x - 10.0) * s) / 2.0
        return pow(2.0, -20.0 * x + 10.0) * s / 2.0 + 1.0

    if curve == Easing.IN_BOUNCE:
        return 1.0 - _out_bounce(1.0 - x)
    if curve == Easing.OUT_BOUNCE:
        return _out_bounce(x)
    if curve == Easing.IN_OUT_BOUNCE:
        if x < 0.5:
            return (1.0 - _out_bounce(1.0 - 2.0 * x)) / 2.0
        return (1.0 + _out_bounce(2.0 * x - 1.0)) / 2.0

    # Unknown curve — an `Easing` built from a raw number outside the named
    # set. Pass the fraction through rather than raising: a wrong curve should
    # look wrong, not stop the frame.
    return x
