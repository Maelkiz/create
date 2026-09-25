from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from create.math.vector2d import Vector2D
from create.math.vector3d import Vector3D
from std.math import isnan, isinf


def test_init_float() raises -> None:
    var v = Vector2D(3.0, 4.0)
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 4.0)


def test_init_int() raises -> None:
    var v = Vector2D(3, 4)
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 4.0)


def test_init_tuple() raises -> None:
    var v = Vector2D((1.5, 2.5))
    assert_equal(v.x, 1.5)
    assert_equal(v.y, 2.5)


def test_zero() raises -> None:
    var v = Vector2D.zero()
    assert_equal(v.x, 0.0)
    assert_equal(v.y, 0.0)


def test_one() raises -> None:
    var v = Vector2D.one()
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 1.0)


def test_add() raises -> None:
    var c = Vector2D(1.0, 2.0) + Vector2D(3.0, 4.0)
    assert_equal(c.x, 4.0)
    assert_equal(c.y, 6.0)


def test_sub() raises -> None:
    var c = Vector2D(5.0, 3.0) - Vector2D(2.0, 1.0)
    assert_equal(c.x, 3.0)
    assert_equal(c.y, 2.0)


def test_mul_scalar() raises -> None:
    var v = Vector2D(2.0, 3.0) * 4.0
    assert_equal(v.x, 8.0)
    assert_equal(v.y, 12.0)


def test_div_scalar() raises -> None:
    var v = Vector2D(6.0, 4.0) / 2.0
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 2.0)


def test_neg() raises -> None:
    var v = -Vector2D(1.0, -2.0)
    assert_equal(v.x, -1.0)
    assert_equal(v.y, 2.0)


def test_iadd() raises -> None:
    var v = Vector2D(1.0, 2.0)
    v += Vector2D(3.0, 4.0)
    assert_equal(v.x, 4.0)
    assert_equal(v.y, 6.0)


def test_isub() raises -> None:
    var v = Vector2D(5.0, 3.0)
    v -= Vector2D(2.0, 1.0)
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 2.0)


def test_imul() raises -> None:
    var v = Vector2D(2.0, 3.0)
    v *= 4.0
    assert_equal(v.x, 8.0)
    assert_equal(v.y, 12.0)


def test_idiv() raises -> None:
    var v = Vector2D(6.0, 4.0)
    v /= 2.0
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 2.0)


def test_eq() raises -> None:
    assert_equal(Vector2D(1.0, 2.0) == Vector2D(1.0, 2.0), True)
    assert_equal(Vector2D(1.0, 2.0) == Vector2D(1.0, 3.0), False)


def test_ne() raises -> None:
    assert_equal(Vector2D(1.0, 2.0) != Vector2D(1.0, 3.0), True)
    assert_equal(Vector2D(1.0, 2.0) != Vector2D(1.0, 2.0), False)


def test_mag() raises -> None:
    assert_equal(Vector2D(3.0, 4.0).mag(), 5.0)
    assert_equal(Vector2D(0.0, 0.0).mag(), 0.0)


def test_mag_sq() raises -> None:
    assert_equal(Vector2D(3.0, 4.0).mag_sq(), 25.0)


def test_normalize() raises -> None:
    var n = Vector2D(3.0, 4.0).normalize()
    assert_almost_equal(n.x, 0.6, atol=1e-9)
    assert_almost_equal(n.y, 0.8, atol=1e-9)


def test_dot_perpendicular() raises -> None:
    assert_equal(Vector2D(1.0, 0.0).dot(Vector2D(0.0, 1.0)), 0.0)


def test_dot_parallel() raises -> None:
    assert_equal(Vector2D(2.0, 3.0).dot(Vector2D(4.0, 5.0)), 23.0)


def test_dist() raises -> None:
    assert_equal(Vector2D(0.0, 0.0).dist(Vector2D(3.0, 4.0)), 5.0)
    assert_equal(Vector2D(1.0, 1.0).dist(Vector2D(1.0, 1.0)), 0.0)


def test_dist_sq() raises -> None:
    assert_equal(Vector2D(0.0, 0.0).dist_sq(Vector2D(3.0, 4.0)), 25.0)


def test_lerp_endpoints() raises -> None:
    var a = Vector2D(0.0, 0.0)
    var b = Vector2D(10.0, 20.0)
    var r0 = a.lerp(b, 0.0)
    assert_equal(r0.x, 0.0)
    assert_equal(r0.y, 0.0)
    var r1 = a.lerp(b, 1.0)
    assert_equal(r1.x, 10.0)
    assert_equal(r1.y, 20.0)


def test_lerp_midpoint() raises -> None:
    var r = Vector2D(0.0, 0.0).lerp(Vector2D(10.0, 20.0), 0.5)
    assert_equal(r.x, 5.0)
    assert_equal(r.y, 10.0)


def test_write_to_contains_type_name() raises -> None:
    var v = Vector2D(3.0, 4.0)
    var s = String(v)
    assert_true(s.startswith("Vector2D("))
    assert_true(s.endswith(")"))


def test_normalize_zero_vector_is_nan() raises -> None:
    var n = Vector2D.zero().normalize()
    assert_true(isnan(n.x))
    assert_true(isnan(n.y))


def test_div_by_zero() raises -> None:
    var v = Vector2D(3.0, 0.0) / 0.0
    assert_true(isinf(v.x))
    assert_true(isnan(v.y))


def test_idiv_by_zero() raises -> None:
    var v = Vector2D(3.0, 0.0)
    v /= 0.0
    assert_true(isinf(v.x))
    assert_true(isnan(v.y))


def test_xy_returns_the_components() raises -> None:
    var t = Vector2D(1.5, 2.5).xy()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)


def test_xyz_defaults_z_to_zero() raises -> None:
    var t = Vector2D(1.5, 2.5).xyz()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)
    assert_equal(t[2], 0.0)


def test_xyz_takes_z() raises -> None:
    var t = Vector2D(1.5, 2.5).xyz(3.5)
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)
    assert_equal(t[2], 3.5)


def test_xy_converts_back_to_a_vector2d() raises -> None:
    var v = Vector2D(1.5, 2.5)
    var back = Vector2D(v.xy())
    assert_equal(back, v)


def test_xyz_converts_to_a_vector3d() raises -> None:
    var w = Vector3D(Vector2D(1.5, 2.5).xyz(3.5))
    assert_equal(w, Vector3D(1.5, 2.5, 3.5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
