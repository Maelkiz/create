from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_true,
)
from std.math import pi, abs
from create.math.matrix import (
    Matrix,
    identity,
    translate,
    rotate,
    scale,
    perspective,
    apply,
    inverse,
)


def test_zero_init() raises -> None:
    var m = Matrix[2, 2]()
    assert_equal(m[0, 0], 0.0)
    assert_equal(m[0, 1], 0.0)
    assert_equal(m[1, 0], 0.0)
    assert_equal(m[1, 1], 0.0)


def test_compares_by_elements() raises -> None:
    assert_true(translate(1.0, 2.0) == translate(1.0, 2.0))
    assert_true(translate(1.0, 2.0) != translate(1.0, 3.0))
    assert_true(identity[3]() == scale(1.0, 1.0))


def test_get_set() raises -> None:
    var m = Matrix[3, 3]()
    m[1, 2] = 7.5
    assert_equal(m[1, 2], 7.5)
    assert_equal(m[0, 0], 0.0)


def test_identity_2x2() raises -> None:
    var m = identity[2]()
    assert_equal(m[0, 0], 1.0)
    assert_equal(m[1, 1], 1.0)
    assert_equal(m[0, 1], 0.0)
    assert_equal(m[1, 0], 0.0)


def test_identity_3x3() raises -> None:
    var m = identity[3]()
    for i in range(3):
        for j in range(3):
            var expected = 1.0 if i == j else 0.0
            assert_equal(m[i, j], expected)


def test_matmul_by_identity() raises -> None:
    var m = Matrix[2, 2]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[1, 0] = 3.0
    m[1, 1] = 4.0
    var id = identity[2]()
    var r = m @ id
    assert_equal(r[0, 0], 1.0)
    assert_equal(r[0, 1], 2.0)
    assert_equal(r[1, 0], 3.0)
    assert_equal(r[1, 1], 4.0)


def test_matmul_values() raises -> None:
    # [[1,2],[3,4]] @ [[5,6],[7,8]] = [[19,22],[43,50]]
    var a = Matrix[2, 2]()
    a[0, 0] = 1.0
    a[0, 1] = 2.0
    a[1, 0] = 3.0
    a[1, 1] = 4.0
    var b = Matrix[2, 2]()
    b[0, 0] = 5.0
    b[0, 1] = 6.0
    b[1, 0] = 7.0
    b[1, 1] = 8.0
    var r = a @ b
    assert_equal(r[0, 0], 19.0)
    assert_equal(r[0, 1], 22.0)
    assert_equal(r[1, 0], 43.0)
    assert_equal(r[1, 1], 50.0)


def test_transpose_square() raises -> None:
    var m = Matrix[2, 2]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[1, 0] = 3.0
    m[1, 1] = 4.0
    var t = m.transposed()
    assert_equal(t[0, 0], 1.0)
    assert_equal(t[0, 1], 3.0)
    assert_equal(t[1, 0], 2.0)
    assert_equal(t[1, 1], 4.0)


def test_transpose_non_square() raises -> None:
    # 2×3 → 3×2: element [r,c] maps to [c,r]
    var m = Matrix[2, 3]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[0, 2] = 3.0
    m[1, 0] = 4.0
    m[1, 1] = 5.0
    m[1, 2] = 6.0
    var t = m.transposed()
    assert_equal(t[0, 0], 1.0)
    assert_equal(t[1, 0], 2.0)
    assert_equal(t[2, 0], 3.0)
    assert_equal(t[0, 1], 4.0)
    assert_equal(t[2, 1], 6.0)


def test_translate_structure() raises -> None:
    var m = translate(3.0, 4.0)
    assert_equal(m[0, 2], 3.0)
    assert_equal(m[1, 2], 4.0)
    assert_equal(m[0, 0], 1.0)
    assert_equal(m[1, 1], 1.0)
    assert_equal(m[2, 2], 1.0)
    assert_equal(m[0, 1], 0.0)
    assert_equal(m[1, 0], 0.0)


def test_translate_apply() raises -> None:
    var m = translate(3.0, 4.0)
    var r = apply(m, 1.0, 2.0)
    assert_almost_equal(r[0], 4.0, atol=1e-9)
    assert_almost_equal(r[1], 6.0, atol=1e-9)


def test_scale_structure() raises -> None:
    var m = scale(2.0, 3.0)
    assert_equal(m[0, 0], 2.0)
    assert_equal(m[1, 1], 3.0)
    assert_equal(m[2, 2], 1.0)
    assert_equal(m[0, 1], 0.0)
    assert_equal(m[1, 0], 0.0)


def test_scale_uniform() raises -> None:
    var m = scale(5.0)
    assert_equal(m[0, 0], 5.0)
    assert_equal(m[1, 1], 5.0)
    assert_equal(m[2, 2], 1.0)


def test_scale_apply() raises -> None:
    var m = scale(2.0, 3.0)
    var r = apply(m, 4.0, 5.0)
    assert_almost_equal(r[0], 8.0, atol=1e-9)
    assert_almost_equal(r[1], 15.0, atol=1e-9)


def test_rotate_zero() raises -> None:
    var m = rotate(0.0)
    assert_almost_equal(m[0, 0], 1.0, atol=1e-9)
    assert_almost_equal(m[0, 1], 0.0, atol=1e-9)
    assert_almost_equal(m[1, 0], 0.0, atol=1e-9)
    assert_almost_equal(m[1, 1], 1.0, atol=1e-9)


def test_rotate_90_degrees() raises -> None:
    # x-axis (1,0) rotated 90° → (0,1)
    var m = rotate(pi / 2.0)
    var r = apply(m, 1.0, 0.0)
    assert_almost_equal(r[0], 0.0, atol=1e-9)
    assert_almost_equal(r[1], 1.0, atol=1e-9)


def test_rotate_180_degrees() raises -> None:
    # (1,0) rotated 180° → (-1,0)
    var m = rotate(pi)
    var r = apply(m, 1.0, 0.0)
    assert_almost_equal(r[0], -1.0, atol=1e-9)
    assert_almost_equal(r[1], 0.0, atol=1e-9)


def test_perspective_key_elements() raises -> None:
    # fov=pi/2, aspect=1, near=0.1, far=100 → f=1
    var m = perspective(pi / 2.0, 1.0, 0.1, 100.0)
    assert_almost_equal(m[0, 0], 1.0, atol=1e-9)
    assert_almost_equal(m[1, 1], 1.0, atol=1e-9)
    assert_almost_equal(m[3, 2], -1.0, atol=1e-9)
    assert_almost_equal(m[3, 3], 0.0, atol=1e-9)


def test_inverse_2x2() raises -> None:
    # [[2,1],[1,1]], det=1, inverse=[[1,-1],[-1,2]]
    var m = Matrix[2, 2]()
    m[0, 0] = 2.0
    m[0, 1] = 1.0
    m[1, 0] = 1.0
    m[1, 1] = 1.0
    var inv = inverse(m)
    assert_almost_equal(inv[0, 0], 1.0, atol=1e-9)
    assert_almost_equal(inv[0, 1], -1.0, atol=1e-9)
    assert_almost_equal(inv[1, 0], -1.0, atol=1e-9)
    assert_almost_equal(inv[1, 1], 2.0, atol=1e-9)


def test_inverse_roundtrip_3x3() raises -> None:
    # M @ inverse(M) ≈ identity
    var m = Matrix[3, 3]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[0, 2] = 0.0
    m[1, 0] = 0.0
    m[1, 1] = 1.0
    m[1, 2] = 3.0
    m[2, 0] = 0.0
    m[2, 1] = 0.0
    m[2, 2] = 1.0
    var inv = inverse(m)
    var prod = m @ inv
    for i in range(3):
        for j in range(3):
            var expected = 1.0 if i == j else 0.0
            assert_almost_equal(prod[i, j], expected, atol=1e-9)


def test_inverse_of_identity() raises -> None:
    var m = identity[3]()
    var inv = inverse(m)
    for i in range(3):
        for j in range(3):
            var expected = 1.0 if i == j else 0.0
            assert_almost_equal(inv[i, j], expected, atol=1e-9)


def test_apply_4x4_with_w_divide() raises -> None:
    # Row 3 isn't the trivial (0,0,0,1): ow=2 regardless of input, so the
    # divide actually does something rather than passing values through.
    var m = Matrix[4, 4]()
    m[0, 0] = 1.0
    m[0, 3] = 5.0
    m[1, 1] = 1.0
    m[2, 2] = 1.0
    m[3, 3] = 2.0
    var r = apply(m, 1.0, 2.0, 3.0)
    assert_almost_equal(r[0], 3.0, atol=1e-9)
    assert_almost_equal(r[1], 1.0, atol=1e-9)
    assert_almost_equal(r[2], 1.5, atol=1e-9)


def test_perspective_projects_point() raises -> None:
    var m = perspective(pi / 2.0, 1.0, 0.1, 100.0)
    var r = apply(m, 1.0, 2.0, -5.0)
    assert_almost_equal(r[0], 0.2, atol=1e-9)
    assert_almost_equal(r[1], 0.4, atol=1e-9)
    assert_almost_equal(r[2], 0.9619619619619619, atol=1e-9)


def test_inverse_with_pivot_swap() raises -> None:
    # m[0,0] is zero, forcing the partial-pivot row swap before elimination.
    var m = Matrix[3, 3]()
    m[0, 0] = 0.0
    m[0, 1] = 1.0
    m[0, 2] = 2.0
    m[1, 0] = 1.0
    m[1, 1] = 0.0
    m[1, 2] = 3.0
    m[2, 0] = 4.0
    m[2, 1] = 5.0
    m[2, 2] = 6.0
    var inv = inverse(m)
    var prod = m @ inv
    for i in range(3):
        for j in range(3):
            var expected = 1.0 if i == j else 0.0
            assert_almost_equal(prod[i, j], expected, atol=1e-9)


def test_inverse_of_singular_matrix_is_garbage() raises -> None:
    # Row 2 = row 0 + row 1: exactly singular, determinant 0. This
    # implementation has no singularity check, so a near-zero pivot from
    # rounding error (not a true zero) is divided into rather than
    # rejected — the result is huge, unusable finite values, not NaN and
    # not a valid inverse.
    var m = Matrix[3, 3]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[0, 2] = 3.0
    m[1, 0] = 4.0
    m[1, 1] = 5.0
    m[1, 2] = 6.0
    m[2, 0] = 5.0
    m[2, 1] = 7.0
    m[2, 2] = 9.0
    var inv = inverse(m)
    var max_abs = 0.0
    for i in range(3):
        for j in range(3):
            var v = abs(inv[i, j])
            if v > max_abs:
                max_abs = v
    assert_true(max_abs > 1e10)

    var prod = m @ inv
    # The product is nowhere near identity — this is not a usable inverse.
    var off = abs(prod[0, 0] - 1.0)
    assert_true(off > 0.01)


def test_copy_ctor_is_independent() raises -> None:
    var m = Matrix[2, 2]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[1, 0] = 3.0
    m[1, 1] = 4.0
    var c = Matrix[2, 2](copy=m)
    m[0, 0] = 99.0
    assert_equal(c[0, 0], 1.0)
    assert_equal(c[0, 1], 2.0)
    assert_equal(c[1, 0], 3.0)
    assert_equal(c[1, 1], 4.0)


def test_write_to_contains_type_name() raises -> None:
    var m = Matrix[2, 2]()
    m[0, 0] = 1.0
    m[0, 1] = 2.0
    m[1, 0] = 3.0
    m[1, 1] = 4.0
    var s = String(m)
    assert_true(s.startswith("Matrix[2x2]("))
    assert_true(s.endswith(")"))


def test_composition_translate_then_scale() raises -> None:
    # scale @ translate applied to (1,1):
    # translate(2,3): (1,1) → (3,4)
    # scale(2,2): (3,4) → (6,8)
    var t = translate(2.0, 3.0)
    var s = scale(2.0, 2.0)
    var composed = s @ t
    var r = apply(composed, 1.0, 1.0)
    assert_almost_equal(r[0], 6.0, atol=1e-9)
    assert_almost_equal(r[1], 8.0, atol=1e-9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
