from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from create.math.util import (
    lerp,
    map,
    inverse_lerp,
    smoothstep,
    sign,
    fractional_part,
    wrap,
    degrees,
    radians,
)
from std.math import isnan, isinf
from create.math import PI


def test_lerp_start() raises -> None:
    assert_equal(lerp(0.0, 10.0, 0.0), 0.0)


def test_lerp_end() raises -> None:
    assert_equal(lerp(0.0, 10.0, 1.0), 10.0)


def test_lerp_midpoint() raises -> None:
    assert_equal(lerp(0.0, 10.0, 0.5), 5.0)


def test_lerp_negative_range() raises -> None:
    assert_equal(lerp(-10.0, 10.0, 0.5), 0.0)


def test_lerp_extrapolates() raises -> None:
    assert_equal(lerp(0.0, 10.0, 2.0), 20.0)


def test_map_low() raises -> None:
    assert_equal(map(0.0, 0.0, 10.0, 0.0, 100.0), 0.0)


def test_map_high() raises -> None:
    assert_equal(map(10.0, 0.0, 10.0, 0.0, 100.0), 100.0)


def test_map_midpoint() raises -> None:
    assert_equal(map(5.0, 0.0, 10.0, 0.0, 100.0), 50.0)


def test_map_different_ranges() raises -> None:
    assert_equal(map(1.0, 0.0, 4.0, 0.0, 1.0), 0.25)


def test_map_inverted_output() raises -> None:
    assert_equal(map(0.0, 0.0, 1.0, 1.0, 0.0), 1.0)
    assert_equal(map(1.0, 0.0, 1.0, 1.0, 0.0), 0.0)


def test_inverse_lerp_low() raises -> None:
    assert_equal(inverse_lerp(0.0, 0.0, 10.0), 0.0)


def test_inverse_lerp_high() raises -> None:
    assert_equal(inverse_lerp(10.0, 0.0, 10.0), 1.0)


def test_inverse_lerp_mid() raises -> None:
    assert_equal(inverse_lerp(5.0, 0.0, 10.0), 0.5)


def test_smoothstep_below_edge0() raises -> None:
    assert_equal(smoothstep(0.0, 1.0, -1.0), 0.0)


def test_smoothstep_above_edge1() raises -> None:
    assert_equal(smoothstep(0.0, 1.0, 2.0), 1.0)


def test_smoothstep_at_edges() raises -> None:
    assert_equal(smoothstep(0.0, 1.0, 0.0), 0.0)
    assert_equal(smoothstep(0.0, 1.0, 1.0), 1.0)


def test_smoothstep_midpoint() raises -> None:
    assert_equal(smoothstep(0.0, 1.0, 0.5), 0.5)


def test_smoothstep_is_smooth() raises -> None:
    # smoothstep should be monotonically increasing
    var prev = smoothstep(0.0, 1.0, 0.0)
    for i in range(1, 11):
        var cur = smoothstep(0.0, 1.0, Float64(i) / 10.0)
        assert_true(cur >= prev)
        prev = cur


def test_sign_positive() raises -> None:
    assert_equal(sign(5.0), 1.0)
    assert_equal(sign(0.001), 1.0)


def test_sign_negative() raises -> None:
    assert_equal(sign(-3.0), -1.0)


def test_sign_zero() raises -> None:
    assert_equal(sign(0.0), 0.0)


def test_fractional_part_positive() raises -> None:
    assert_almost_equal(fractional_part(3.75), 0.75, atol=1e-12)
    assert_almost_equal(fractional_part(1.0), 0.0, atol=1e-12)


def test_fractional_part_negative() raises -> None:
    # fractional_part(-0.25) = -0.25 - floor(-0.25) = -0.25 - (-1) = 0.75
    assert_almost_equal(fractional_part(-0.25), 0.75, atol=1e-12)


def test_wrap_basic() raises -> None:
    assert_almost_equal(wrap(7.0, 3.0), 1.0, atol=1e-12)
    assert_almost_equal(wrap(6.0, 3.0), 0.0, atol=1e-12)


def test_degrees_from_radians() raises -> None:
    assert_almost_equal(degrees(PI), 180.0, atol=1e-9)
    assert_almost_equal(degrees(0.0), 0.0, atol=1e-12)


def test_radians_from_degrees() raises -> None:
    assert_almost_equal(radians(180.0), PI, atol=1e-12)
    assert_almost_equal(radians(0.0), 0.0, atol=1e-12)


def test_degrees_radians_roundtrip() raises -> None:
    assert_almost_equal(degrees(radians(90.0)), 90.0, atol=1e-9)
    assert_almost_equal(radians(degrees(1.0)), 1.0, atol=1e-9)


def test_wrap_negative_numerator() raises -> None:
    # floor(-1/3) = -1, so -1 - (-1)*3 = 2
    assert_almost_equal(wrap(-1.0, 3.0), 2.0, atol=1e-12)


def test_wrap_negative_large() raises -> None:
    # floor(-7/3) = -3, so -7 - (-3)*3 = 2
    assert_almost_equal(wrap(-7.0, 3.0), 2.0, atol=1e-12)


def test_lerp_out_of_range_extrapolates_below() raises -> None:
    assert_equal(lerp(0.0, 10.0, -1.0), -10.0)


def test_map_extrapolates_outside_input() raises -> None:
    # value outside [in_low, in_high] extrapolates linearly
    assert_almost_equal(map(15.0, 0.0, 10.0, 0.0, 100.0), 150.0, atol=1e-9)


def test_inverse_lerp_outside_range() raises -> None:
    assert_almost_equal(inverse_lerp(-5.0, 0.0, 10.0), -0.5, atol=1e-12)
    assert_almost_equal(inverse_lerp(15.0, 0.0, 10.0), 1.5, atol=1e-12)


def test_fractional_part_at_integer() raises -> None:
    assert_almost_equal(fractional_part(5.0), 0.0, atol=1e-12)
    assert_almost_equal(fractional_part(0.0), 0.0, atol=1e-12)


def test_degrees_quarter_turn() raises -> None:
    assert_almost_equal(degrees(PI / 2.0), 90.0, atol=1e-9)


def test_radians_quarter_turn() raises -> None:
    assert_almost_equal(radians(90.0), PI / 2.0, atol=1e-12)


# Degenerate-input contract: in_low == in_high divides by zero. At the pinned
# value that's 0/0 = nan; anywhere else it's a nonzero numerator over zero,
# which is +/-inf.
def test_map_degenerate_equal_input_range_at_value() raises -> None:
    assert_true(isnan(map(5.0, 5.0, 5.0, 0.0, 100.0)))


def test_map_degenerate_equal_input_range_away_from_value() raises -> None:
    assert_true(isinf(map(6.0, 5.0, 5.0, 0.0, 100.0)))


def test_inverse_lerp_degenerate_equal_range_at_value() raises -> None:
    assert_true(isnan(inverse_lerp(5.0, 5.0, 5.0)))


def test_inverse_lerp_degenerate_equal_range_away_from_value() raises -> None:
    assert_true(isinf(inverse_lerp(6.0, 5.0, 5.0)))


def test_smoothstep_degenerate_equal_edges() raises -> None:
    # clamp(nan, 0, 1) resolves to the upper bound in this implementation
    assert_equal(smoothstep(3.0, 3.0, 3.0), 1.0)
    assert_equal(smoothstep(3.0, 3.0, 5.0), 1.0)
    assert_equal(smoothstep(3.0, 3.0, 1.0), 0.0)


def test_wrap_by_zero() raises -> None:
    assert_true(isnan(wrap(5.0, 0.0)))
    assert_true(isnan(wrap(0.0, 0.0)))
    assert_true(isnan(wrap(-5.0, 0.0)))


def test_sign_negative_zero() raises -> None:
    assert_equal(sign(-0.0), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
