from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from create.math.vector3d import Vector3D
from create.math.vector2d import Vector2D
from std.math import isnan, isinf


def test_init_float() raises -> None:
    var v = Vector3D(1.0, 2.0, 3.0)
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 2.0)
    assert_equal(v.z, 3.0)


def test_init_int() raises -> None:
    var v = Vector3D(1, 2, 3)
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 2.0)
    assert_equal(v.z, 3.0)


def test_init_tuple() raises -> None:
    var v = Vector3D((1.5, 2.5, 3.5))
    assert_equal(v.x, 1.5)
    assert_equal(v.y, 2.5)
    assert_equal(v.z, 3.5)


def test_zero() raises -> None:
    var v = Vector3D.zero()
    assert_equal(v.x, 0.0)
    assert_equal(v.y, 0.0)
    assert_equal(v.z, 0.0)


def test_one() raises -> None:
    var v = Vector3D.one()
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 1.0)
    assert_equal(v.z, 1.0)


def test_add() raises -> None:
    var c = Vector3D(1.0, 2.0, 3.0) + Vector3D(4.0, 5.0, 6.0)
    assert_equal(c.x, 5.0)
    assert_equal(c.y, 7.0)
    assert_equal(c.z, 9.0)


def test_sub() raises -> None:
    var c = Vector3D(4.0, 5.0, 6.0) - Vector3D(1.0, 2.0, 3.0)
    assert_equal(c.x, 3.0)
    assert_equal(c.y, 3.0)
    assert_equal(c.z, 3.0)


def test_mul_scalar() raises -> None:
    var v = Vector3D(1.0, 2.0, 3.0) * 2.0
    assert_equal(v.x, 2.0)
    assert_equal(v.y, 4.0)
    assert_equal(v.z, 6.0)


def test_div_scalar() raises -> None:
    var v = Vector3D(2.0, 4.0, 6.0) / 2.0
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 2.0)
    assert_equal(v.z, 3.0)


def test_neg() raises -> None:
    var v = -Vector3D(1.0, -2.0, 3.0)
    assert_equal(v.x, -1.0)
    assert_equal(v.y, 2.0)
    assert_equal(v.z, -3.0)


def test_iadd() raises -> None:
    var v = Vector3D(1.0, 2.0, 3.0)
    v += Vector3D(1.0, 1.0, 1.0)
    assert_equal(v.x, 2.0)
    assert_equal(v.y, 3.0)
    assert_equal(v.z, 4.0)


def test_isub() raises -> None:
    var v = Vector3D(3.0, 3.0, 3.0)
    v -= Vector3D(1.0, 2.0, 3.0)
    assert_equal(v.x, 2.0)
    assert_equal(v.y, 1.0)
    assert_equal(v.z, 0.0)


def test_imul() raises -> None:
    var v = Vector3D(1.0, 2.0, 3.0)
    v *= 3.0
    assert_equal(v.x, 3.0)
    assert_equal(v.y, 6.0)
    assert_equal(v.z, 9.0)


def test_idiv() raises -> None:
    var v = Vector3D(3.0, 6.0, 9.0)
    v /= 3.0
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 2.0)
    assert_equal(v.z, 3.0)


def test_eq() raises -> None:
    assert_equal(Vector3D(1.0, 2.0, 3.0) == Vector3D(1.0, 2.0, 3.0), True)
    assert_equal(Vector3D(1.0, 2.0, 3.0) == Vector3D(1.0, 2.0, 4.0), False)


def test_ne() raises -> None:
    assert_equal(Vector3D(1.0, 2.0, 3.0) != Vector3D(1.0, 2.0, 4.0), True)
    assert_equal(Vector3D(1.0, 2.0, 3.0) != Vector3D(1.0, 2.0, 3.0), False)


def test_mag() raises -> None:
    assert_almost_equal(Vector3D(1.0, 2.0, 2.0).mag(), 3.0, atol=1e-9)
    assert_equal(Vector3D(0.0, 0.0, 0.0).mag(), 0.0)


def test_mag_sq() raises -> None:
    assert_equal(Vector3D(1.0, 2.0, 2.0).mag_sq(), 9.0)


def test_normalize() raises -> None:
    var n = Vector3D(1.0, 2.0, 2.0).normalize()
    assert_almost_equal(n.x, 1.0 / 3.0, atol=1e-9)
    assert_almost_equal(n.y, 2.0 / 3.0, atol=1e-9)
    assert_almost_equal(n.z, 2.0 / 3.0, atol=1e-9)


def test_dot_perpendicular() raises -> None:
    assert_equal(Vector3D(1.0, 0.0, 0.0).dot(Vector3D(0.0, 1.0, 0.0)), 0.0)


def test_dot_values() raises -> None:
    assert_equal(Vector3D(1.0, 2.0, 3.0).dot(Vector3D(4.0, 5.0, 6.0)), 32.0)


def test_cross_basis_vectors() raises -> None:
    # x × y = z
    var c = Vector3D(1.0, 0.0, 0.0).cross(Vector3D(0.0, 1.0, 0.0))
    assert_equal(c.x, 0.0)
    assert_equal(c.y, 0.0)
    assert_equal(c.z, 1.0)


def test_cross_anticommutative() raises -> None:
    var a = Vector3D(1.0, 2.0, 3.0)
    var b = Vector3D(4.0, 5.0, 6.0)
    var ab = a.cross(b)
    var neg_ba = -(b.cross(a))
    assert_almost_equal(ab.x, neg_ba.x, atol=1e-9)
    assert_almost_equal(ab.y, neg_ba.y, atol=1e-9)
    assert_almost_equal(ab.z, neg_ba.z, atol=1e-9)


def test_dist() raises -> None:
    assert_almost_equal(
        Vector3D(0.0, 0.0, 0.0).dist(Vector3D(1.0, 2.0, 2.0)), 3.0, atol=1e-9
    )


def test_dist_sq() raises -> None:
    assert_equal(Vector3D(0.0, 0.0, 0.0).dist_sq(Vector3D(1.0, 2.0, 2.0)), 9.0)


def test_lerp_endpoints() raises -> None:
    var a = Vector3D(0.0, 0.0, 0.0)
    var b = Vector3D(2.0, 4.0, 6.0)
    var r0 = a.lerp(b, 0.0)
    assert_equal(r0.x, 0.0)
    assert_equal(r0.y, 0.0)
    assert_equal(r0.z, 0.0)
    var r1 = a.lerp(b, 1.0)
    assert_equal(r1.x, 2.0)
    assert_equal(r1.y, 4.0)
    assert_equal(r1.z, 6.0)


def test_lerp_midpoint() raises -> None:
    var r = Vector3D(0.0, 0.0, 0.0).lerp(Vector3D(2.0, 4.0, 6.0), 0.5)
    assert_equal(r.x, 1.0)
    assert_equal(r.y, 2.0)
    assert_equal(r.z, 3.0)


def test_write_to_contains_type_name() raises -> None:
    var v = Vector3D(1.0, 2.0, 3.0)
    var s = String(v)
    assert_true(s.startswith("Vector3D("))
    assert_true(s.endswith(")"))


def test_normalize_zero_vector_is_nan() raises -> None:
    var n = Vector3D.zero().normalize()
    assert_true(isnan(n.x))
    assert_true(isnan(n.y))
    assert_true(isnan(n.z))


def test_div_by_zero() raises -> None:
    var v = Vector3D(3.0, 0.0, -2.0) / 0.0
    assert_true(isinf(v.x))
    assert_true(isnan(v.y))
    assert_true(isinf(v.z))


def test_idiv_by_zero() raises -> None:
    var v = Vector3D(3.0, 0.0, -2.0)
    v /= 0.0
    assert_true(isinf(v.x))
    assert_true(isnan(v.y))
    assert_true(isinf(v.z))


def test_xy_drops_z() raises -> None:
    var t = Vector3D(1.5, 2.5, 3.5).xy()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)


def test_xyz_returns_every_component() raises -> None:
    var t = Vector3D(1.5, 2.5, 3.5).xyz()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)
    assert_equal(t[2], 3.5)


def test_xy_xyz_round_trip() raises -> None:
    """The tuple return does not chain, so the round trip reconstructs
    through the explicit tuple constructor instead."""
    var v = Vector3D(1.5, 2.5, 3.5)
    var narrowed = Vector2D(v.xy())
    assert_equal(Vector3D(narrowed.x, narrowed.y, v.z), v)


def test_xyz_converts_back_to_a_vector3d() raises -> None:
    var v = Vector3D(1.5, 2.5, 3.5)
    var back = Vector3D(v.xyz())
    assert_equal(back, v)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
