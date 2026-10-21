from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from create.math.vector3d import Vector3D
from std.math import isnan, isinf, pi


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
    var v = Vector2D.ZERO
    assert_equal(v.x, 0.0)
    assert_equal(v.y, 0.0)


def test_one() raises -> None:
    var v = Vector2D.ONE
    assert_equal(v.x, 1.0)
    assert_equal(v.y, 1.0)


def test_directions() raises -> None:
    assert_equal(Vector2D.UP, Vector2D(0.0, 1.0))
    assert_equal(Vector2D.DOWN, Vector2D(0.0, -1.0))
    assert_equal(Vector2D.LEFT, Vector2D(-1.0, 0.0))
    assert_equal(Vector2D.RIGHT, Vector2D(1.0, 0.0))
    assert_equal(Vector2D.UP, -Vector2D.DOWN)
    assert_equal(Vector2D.LEFT, -Vector2D.RIGHT)


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


def test_scalar_times_vector() raises -> None:
    """`s * v` compiles and agrees with `v * s`."""
    var v = Vector2D(3.0, -4.0)
    var dt = 2.0
    assert_equal(dt * v, Vector2D(6.0, -8.0))
    assert_equal(dt * v, v * dt)


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


def test_magnitude() raises -> None:
    assert_equal(Vector2D(3.0, 4.0).magnitude(), 5.0)
    assert_equal(Vector2D(0.0, 0.0).magnitude(), 0.0)


def test_magnitude_squared() raises -> None:
    assert_equal(Vector2D(3.0, 4.0).magnitude_squared(), 25.0)


def test_normalize() raises -> None:
    var n = Vector2D(3.0, 4.0).normalize()
    assert_almost_equal(n.x, 0.6, atol=1e-9)
    assert_almost_equal(n.y, 0.8, atol=1e-9)


def test_dot_perpendicular() raises -> None:
    assert_equal(Vector2D(1.0, 0.0).dot(Vector2D(0.0, 1.0)), 0.0)


def test_dot_parallel() raises -> None:
    assert_equal(Vector2D(2.0, 3.0).dot(Vector2D(4.0, 5.0)), 23.0)


def test_distance() raises -> None:
    assert_equal(Vector2D(0.0, 0.0).distance(Vector2D(3.0, 4.0)), 5.0)
    assert_equal(Vector2D(1.0, 1.0).distance(Vector2D(1.0, 1.0)), 0.0)


def test_distance_squared() raises -> None:
    assert_equal(Vector2D(0.0, 0.0).distance_squared(Vector2D(3.0, 4.0)), 25.0)


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
    var n = Vector2D.ZERO.normalize()
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


def test_xy_converts_back_to_a_vector2d() raises -> None:
    var v = Vector2D(1.5, 2.5)
    var back = Vector2D(v.xy())
    assert_equal(back, v)


def test_xy_destructures() raises -> None:
    var (x, y) = Vector2D(1.5, 2.5).xy()
    assert_equal(x, 1.5)
    assert_equal(y, 2.5)


def test_constructs_from_a_point2d() raises -> None:
    """The displacement from the origin to the position."""
    var p = Point2D(1.5, -2.5)
    assert_equal(Vector2D(p), p - Point2D(0.0, 0.0))


def test_widens_to_a_vector3d() raises -> None:
    assert_equal(Vector3D(Vector2D(1.5, 2.5), 3.5), Vector3D(1.5, 2.5, 3.5))
    assert_equal(Vector3D(Vector2D(1.5, 2.5)), Vector3D(1.5, 2.5, 0.0))


def test_narrows_from_a_vector3d() raises -> None:
    assert_equal(Vector2D(Vector3D(1.5, 2.5, 3.5)), Vector2D(1.5, 2.5))


def test_float_tuple_still_takes_the_tuple_constructor() raises -> None:
    """A `Point2D` constructor beside the tuple one must not make a float
    tuple ambiguous."""
    assert_equal(Vector2D((1.5, 2.5)), Vector2D(1.5, 2.5))


def _assert_close(a: Vector2D, b: Vector2D) raises:
    assert_almost_equal(a.x, b.x, atol=1e-12)
    assert_almost_equal(a.y, b.y, atol=1e-12)


def test_from_angle_follows_the_y_up_convention() raises -> None:
    _assert_close(Vector2D.from_angle(0.0), Vector2D.RIGHT)
    _assert_close(Vector2D.from_angle(pi / 2.0), Vector2D.UP)
    _assert_close(Vector2D.from_angle(-pi / 2.0), Vector2D.DOWN)


def test_from_angle_takes_a_length() raises -> None:
    _assert_close(Vector2D.from_angle(pi, 3.0), Vector2D(-3.0, 0.0))


def test_angle_reads_the_heading_back() raises -> None:
    assert_almost_equal(Vector2D.UP.angle(), pi / 2.0)
    assert_almost_equal(Vector2D.from_angle(2.5, 4.0).angle(), 2.5)
    assert_equal(Vector2D.ZERO.angle(), 0.0)


def test_rotate_turns_counter_clockwise() raises -> None:
    _assert_close(Vector2D(2.0, 0.0).rotate(pi / 2.0), Vector2D(0.0, 2.0))
    _assert_close(Vector2D.UP.rotate(-pi / 2.0), Vector2D.RIGHT)


def test_rotate_keeps_the_length() raises -> None:
    var v = Vector2D(3.0, 4.0).rotate(1.234)
    assert_almost_equal(v.magnitude(), 5.0)


def test_rotate_leaves_self_alone() raises -> None:
    var v = Vector2D(3.0, 4.0)
    _ = v.rotate(1.0)
    assert_equal(v, Vector2D(3.0, 4.0))


def test_with_length_keeps_the_direction() raises -> None:
    _assert_close(Vector2D(3.0, 4.0).with_length(10.0), Vector2D(6.0, 8.0))


def test_with_length_of_zero_is_nan() raises -> None:
    var v = Vector2D.ZERO.with_length(2.0)
    assert_true(isnan(v.x))
    assert_true(isnan(v.y))


def test_limit_shortens_only_a_longer_vector() raises -> None:
    _assert_close(Vector2D(3.0, 4.0).limit(2.5), Vector2D(1.5, 2.0))
    assert_equal(Vector2D(3.0, 4.0).limit(5.0), Vector2D(3.0, 4.0))
    assert_equal(Vector2D(3.0, 4.0).limit(10.0), Vector2D(3.0, 4.0))
    assert_equal(Vector2D.ZERO.limit(1.0), Vector2D.ZERO)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
