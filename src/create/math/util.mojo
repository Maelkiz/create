"""Scalar helpers for animation and ranges.

Reached through `from create import *`, or by name from `create.math`.
"""

from std.math import floor, pi, clamp


def lerp(a: Float64, b: Float64, t: Float64) -> Float64:
    """Blend from `a` to `b`, `t` running 0 to 1. Not clamped: `t` outside that
    range extrapolates past either end."""
    return a + (b - a) * t


def map(
    value: Float64,
    in_low: Float64,
    in_high: Float64,
    out_low: Float64,
    out_high: Float64,
) -> Float64:
    """Re-scale `value` from one range onto another — a slider position to a
    world coordinate, say. Linear and unclamped."""
    return out_low + (value - in_low) / (in_high - in_low) * (
        out_high - out_low
    )


def inverse_lerp(value: Float64, low: Float64, high: Float64) -> Float64:
    """Where `value` sits in `[low, high]` as a 0-to-1 fraction. The inverse of
    `lerp`, and `map` with a 0..1 output range."""
    return (value - low) / (high - low)


def smoothstep(edge0: Float64, edge1: Float64, x: Float64) -> Float64:
    """Like `inverse_lerp`, but clamped to 0..1 and eased at both ends — the usual
    choice for a transition that should not start or stop abruptly."""
    var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def sign(x: Float64) -> Float64:
    """-1.0, 0.0 or 1.0 by the sign of `x`. Zero is its own case, not positive.
    """
    if x > 0.0:
        return 1.0
    if x < 0.0:
        return -1.0
    return 0.0


def fractional_part(x: Float64) -> Float64:
    """The part after the decimal point, always positive: `fractional_part(-0.25)` is
    0.75, since it floors rather than truncating."""
    return x - floor(x)


def wrap(x: Float64, y: Float64) -> Float64:
    """`x` wrapped into `[0, y)`. Floored, so a negative `x` wraps forward
    instead of staying negative — what an angle or a scrolling offset wants."""
    return x - floor(x / y) * y


def degrees(r: Float64) -> Float64:
    """Radians to degrees. Rotations take radians, so this is for display."""
    return r * (180.0 / pi)


def radians(d: Float64) -> Float64:
    """Degrees to radians, for feeding `rotate` an angle written in degrees."""
    return d * (pi / 180.0)
