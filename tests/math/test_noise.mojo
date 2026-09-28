from std.testing import TestSuite, assert_true, assert_equal
from create.math.noise import Noise
from create.math.point2d import Point2D


def test_same_seed_same_field() raises -> None:
    var a = Noise(42)
    var b = Noise(42)
    for i in range(100):
        var x = Float64(i) * 0.37
        assert_equal(a.at(x), b.at(x))
        assert_equal(a.at(Point2D(x, -x)), b.at(Point2D(x, -x)))
        assert_equal(a.at(Point2D(x, 1.3), x), b.at(Point2D(x, 1.3), x))


def test_different_seed_different_field() raises -> None:
    var a = Noise(1)
    var b = Noise(2)
    var differing = 0
    for i in range(100):
        var p = Point2D(Float64(i) * 0.37, 0.61)
        if a.at(p) != b.at(p):
            differing += 1
    assert_true(differing > 90, "differing=" + String(differing))


def _check_range(name: String, low: Float64, high: Float64) raises -> None:
    assert_true(
        low >= 0.0 and high <= 1.0,
        name + " left [0, 1]: " + String(low) + ".." + String(high),
    )
    # A dense sample should reach well into both halves of the range
    assert_true(
        low < 0.25 and high > 0.75,
        name + " spread too narrow: " + String(low) + ".." + String(high),
    )


def test_range_and_spread() raises -> None:
    var noise = Noise(7)
    var low1 = 1.0
    var high1 = 0.0
    var low2 = 1.0
    var high2 = 0.0
    var low3 = 1.0
    var high3 = 0.0
    for i in range(200):
        for j in range(200):
            var x = Float64(i) * 0.113 - 11.0
            var y = Float64(j) * 0.127 - 13.0
            var v2 = noise.at(Point2D(x, y))
            var v3 = noise.at(Point2D(x, y), Float64(i + j) * 0.071)
            low2 = min(low2, v2)
            high2 = max(high2, v2)
            low3 = min(low3, v3)
            high3 = max(high3, v3)
        for j in range(50):
            var v1 = noise.at(Float64(i * 50 + j) * 0.0173 - 50.0)
            low1 = min(low1, v1)
            high1 = max(high1, v1)
    _check_range("1D", low1, high1)
    _check_range("2D", low2, high2)
    _check_range("2D+time", low3, high3)


def test_continuity() raises -> None:
    # A tiny step moves the value by a tiny amount: no seams at cell edges
    var noise = Noise(3)
    comptime step = 1e-4
    var worst = 0.0
    for i in range(1000):
        var x = Float64(i) * 0.0317 - 15.0
        worst = max(worst, abs(noise.at(x + step) - noise.at(x)))
        var p = Point2D(x, x * 0.7 + 0.2)
        worst = max(
            worst, abs(noise.at(Point2D(p.x + step, p.y)) - noise.at(p))
        )
        worst = max(
            worst, abs(noise.at(Point2D(p.x, p.y + step)) - noise.at(p))
        )
        worst = max(worst, abs(noise.at(p, x + step) - noise.at(p, x)))
    assert_true(worst < 0.01, "worst step=" + String(worst))


def test_lattice_points_are_one_half() raises -> None:
    var noise = Noise(11)
    for i in range(-5, 6):
        var x = Float64(i)
        assert_equal(noise.at(x), 0.5)
        for j in range(-5, 6):
            var p = Point2D(x, Float64(j))
            assert_equal(noise.at(p), 0.5)
            assert_equal(noise.at(p, Float64(j - i)), 0.5)


def test_feature_size_scales_space() raises -> None:
    # A power of two keeps the division exact
    comptime k = 4.0
    var unit = Noise(5)
    var scaled = Noise(5, feature_size=k)
    for i in range(100):
        var x = Float64(i) * 0.29 - 14.0
        var y = Float64(i) * -0.41 + 3.0
        assert_equal(scaled.at(x * k), unit.at(x))
        assert_equal(scaled.at(Point2D(x * k, y * k)), unit.at(Point2D(x, y)))


def test_feature_size_leaves_time_unscaled() raises -> None:
    comptime k = 4.0
    var unit = Noise(5)
    var scaled = Noise(5, feature_size=k)
    for i in range(100):
        var x = Float64(i) * 0.29 - 14.0
        var t = Float64(i) * 0.13
        assert_equal(
            scaled.at(Point2D(x * k, 2.5 * k), t), unit.at(Point2D(x, 2.5), t)
        )


def test_bare_tuple_is_a_position() raises -> None:
    var noise = Noise(9)
    assert_equal(noise.at((1.5, 2.5)), noise.at(Point2D(1.5, 2.5)))
    assert_equal(noise.at((1.5, 2.5), 0.3), noise.at(Point2D(1.5, 2.5), 0.3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
