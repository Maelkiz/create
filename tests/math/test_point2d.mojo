from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from create.math.point2d import Point2D
from create.math.vector2d import Vector2D
from create.math.vector3d import Vector3D


def test_init_float() raises -> None:
    var p = Point2D(3.0, 4.0)
    assert_equal(p.x, 3.0)
    assert_equal(p.y, 4.0)


def test_init_int() raises -> None:
    var p = Point2D(3, 4)
    assert_equal(p.x, 3.0)
    assert_equal(p.y, 4.0)


def test_init_tuple_float() raises -> None:
    var p: Point2D = (1.5, 2.5)
    assert_equal(p.x, 1.5)
    assert_equal(p.y, 2.5)


def test_init_tuple_int() raises -> None:
    var p: Point2D = (3, 7)
    assert_equal(p.x, 3.0)
    assert_equal(p.y, 7.0)


def test_init_tuple_int_float() raises -> None:
    var p: Point2D = (3, 4.5)
    assert_equal(p.x, 3.0)
    assert_equal(p.y, 4.5)


def test_init_tuple_float_int() raises -> None:
    var p: Point2D = (3.5, 4)
    assert_equal(p.x, 3.5)
    assert_equal(p.y, 4.0)


def test_point_minus_point_is_a_displacement() raises -> None:
    """Position minus position is the vector between them, which is the one
    operation that motivates the type split."""
    var d: Vector2D = Point2D(4.0, 6.0) - Point2D(1.0, 2.0)
    assert_equal(d, Vector2D(3.0, 4.0))


def test_point_plus_vector_moves_the_point() raises -> None:
    var p = Point2D(1.0, 2.0) + Vector2D(3.0, 4.0)
    assert_equal(p, Point2D(4.0, 6.0))


def test_point_minus_vector_moves_the_point() raises -> None:
    var p = Point2D(4.0, 6.0) - Vector2D(3.0, 4.0)
    assert_equal(p, Point2D(1.0, 2.0))


def test_displacement_round_trip() raises -> None:
    """`a + (b - a) == b` — the two operators are inverses, which is what
    makes the algebra affine rather than arbitrary."""
    var a = Point2D(-3.0, 7.5)
    var b = Point2D(11.0, -2.25)
    assert_equal(a + (b - a), b)


def test_iadd_vector() raises -> None:
    var p = Point2D(1.0, 2.0)
    p += Vector2D(3.0, 4.0)
    assert_equal(p, Point2D(4.0, 6.0))


def test_isub_vector() raises -> None:
    var p = Point2D(4.0, 6.0)
    p -= Vector2D(3.0, 4.0)
    assert_equal(p, Point2D(1.0, 2.0))


def test_eq() raises -> None:
    assert_equal(Point2D(1.0, 2.0) == Point2D(1.0, 2.0), True)
    assert_equal(Point2D(1.0, 2.0) == Point2D(1.0, 3.0), False)


def test_ne() raises -> None:
    assert_equal(Point2D(1.0, 2.0) != Point2D(1.0, 3.0), True)
    assert_equal(Point2D(1.0, 2.0) != Point2D(1.0, 2.0), False)


def test_dist() raises -> None:
    assert_equal(Point2D(0.0, 0.0).dist(Point2D(3.0, 4.0)), 5.0)
    assert_equal(Point2D(1.0, 1.0).dist(Point2D(1.0, 1.0)), 0.0)


def test_dist_is_symmetric() raises -> None:
    var a = Point2D(-2.0, 5.0)
    var b = Point2D(4.0, -3.0)
    assert_almost_equal(a.dist(b), b.dist(a), atol=1e-9)


def test_dist_sq() raises -> None:
    assert_equal(Point2D(0.0, 0.0).dist_sq(Point2D(3.0, 4.0)), 25.0)


def test_lerp_endpoints() raises -> None:
    var a = Point2D(0.0, 0.0)
    var b = Point2D(10.0, 20.0)
    assert_equal(a.lerp(b, 0.0), a)
    assert_equal(a.lerp(b, 1.0), b)


def test_lerp_midpoint() raises -> None:
    var r = Point2D(0.0, 0.0).lerp(Point2D(10.0, 20.0), 0.5)
    assert_equal(r, Point2D(5.0, 10.0))


def test_write_to_contains_type_name() raises -> None:
    var s = String(Point2D(3.0, 4.0))
    assert_true(s.startswith("Point2D("))
    assert_true(s.endswith(")"))


def test_xy_returns_the_components() raises -> None:
    var t = Point2D(1.5, 2.5).xy()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)


def test_xyz_defaults_z_to_zero() raises -> None:
    var t = Point2D(1.5, 2.5).xyz()
    assert_equal(t[0], 1.5)
    assert_equal(t[1], 2.5)
    assert_equal(t[2], 0.0)


def test_xyz_takes_z() raises -> None:
    var t = Point2D(1.5, 2.5).xyz(3.5)
    assert_equal(t[2], 3.5)


def test_xy_binds_back_to_a_point2d() raises -> None:
    var p = Point2D(1.5, 2.5)
    var back: Point2D = p.xy()
    assert_equal(back, p)


def test_xy_is_the_escape_hatch_to_a_vector2d() raises -> None:
    """`Vector2D(p.xy())` is how a program reaches the operations Point2D
    deliberately refuses."""
    var v = Vector2D(Point2D(3.0, 4.0).xy())
    assert_equal(v.mag(), 5.0)


def test_xyz_converts_to_a_vector3d() raises -> None:
    var w = Vector3D(Point2D(1.5, 2.5).xyz(3.5))
    assert_equal(w, Vector3D(1.5, 2.5, 3.5))


def test_subtracting_a_bare_tuple_is_a_displacement() raises -> None:
    """A bare tuple only converts to a `Point2D`, so `p - (1, 2)` is the
    displacement between two positions, not a move -- see the docstring."""
    var d: Vector2D = Point2D(4.0, 6.0) - (1.0, 2.0)
    assert_equal(d, Vector2D(3.0, 4.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
