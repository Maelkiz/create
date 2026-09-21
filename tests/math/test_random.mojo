from std.testing import TestSuite, assert_true, assert_equal
from create.math.random import Random


def test_float_in_unit_interval() raises -> None:
    # float() is half-open [0, 1), matching int(low, high)'s convention
    var rng = Random(42)
    var out_of_range = 0
    for _ in range(1000):
        var v = rng.float()
        if not (v >= 0.0 and v < 1.0):
            out_of_range += 1
    assert_equal(out_of_range, 0, "renders outside [0, 1) out of 1000")


def test_float_range() raises -> None:
    # float(low, high) inherits float()'s half-open convention
    var rng = Random(1)
    var out_of_range = 0
    for _ in range(1000):
        var v = rng.float(5.0, 10.0)
        if not (v >= 5.0 and v < 10.0):
            out_of_range += 1
    assert_equal(out_of_range, 0, "renders outside [5, 10) out of 1000")


def test_int_range() raises -> None:
    # int(low, high) is half-open — the convention float() now matches
    var rng = Random(7)
    var out_of_range = 0
    for _ in range(1000):
        var v = rng.int(3, 8)
        if not (v >= 3 and v < 8):
            out_of_range += 1
    assert_equal(out_of_range, 0, "renders outside [3, 8) out of 1000")


def test_bool_roughly_half() raises -> None:
    var rng = Random(99)
    var true_count = 0
    for _ in range(1000):
        if rng.bool():
            true_count += 1
    # Expect ~500 of 1000; tolerate a 100-render (10 percentage point) band
    var deviation = abs(true_count - 500)
    assert_true(
        deviation <= 100,
        "true_count=" + String(true_count) + ", deviation=" + String(deviation),
    )


def test_deterministic_seed() raises -> None:
    var a = Random(12345)
    var b = Random(12345)
    assert_equal(a.float(), b.float())


def test_different_seeds_differ() raises -> None:
    var a = Random(1)
    var b = Random(2)
    # Astronomically unlikely to match
    assert_equal(a.float() == b.float(), False)


def test_float_golden_vectors() raises -> None:
    # First eight float() outputs for seed 42 — pins SplitMix64 seeding and
    # the xoroshiro128+ step so a change to either fails loudly instead of
    # staying "deterministic".
    var rng = Random(42)
    assert_equal(rng.float(), 0.09216857653620139)
    assert_equal(rng.float(), 0.37809197770204533)
    assert_equal(rng.float(), 6.418922274806796e-05)
    assert_equal(rng.float(), 0.6636138713760317)
    assert_equal(rng.float(), 0.8932261481311833)
    assert_equal(rng.float(), 0.46157633621021904)
    assert_equal(rng.float(), 0.9560477333629563)
    assert_equal(rng.float(), 0.2836676123496478)


def test_entropy_seeded_default_ctor_differs() raises -> None:
    var a = Random()
    var b = Random()
    # Astronomically unlikely to collide on the nanosecond timer seed
    assert_equal(a.float() == b.float(), False)


def test_int_golden_vectors() raises -> None:
    # First eight int(0, 1_000_000) outputs for seed 42
    var rng = Random(42)
    assert_equal(rng.int(0, 1000000), 418247)
    assert_equal(rng.int(0, 1000000), 329168)
    assert_equal(rng.int(0, 1000000), 323945)
    assert_equal(rng.int(0, 1000000), 265373)
    assert_equal(rng.int(0, 1000000), 314372)
    assert_equal(rng.int(0, 1000000), 425446)
    assert_equal(rng.int(0, 1000000), 565016)
    assert_equal(rng.int(0, 1000000), 204856)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
