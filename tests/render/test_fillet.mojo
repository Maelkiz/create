from std.testing import TestSuite, assert_almost_equal, assert_true

from create.render._fillet import (
    _vertex_max_radius,
    corner_fillet,
    rect_corner_radius,
    triangle_corner_radius,
)


def test_rect_corner_radius_passes_through_when_it_fits() raises -> None:
    assert_almost_equal(rect_corner_radius(10.0, 100.0, 100.0), 10.0, atol=1e-9)


def test_rect_corner_radius_clamps_to_half_width() raises -> None:
    assert_almost_equal(rect_corner_radius(100.0, 40.0, 200.0), 20.0, atol=1e-9)


def test_rect_corner_radius_clamps_to_half_height() raises -> None:
    assert_almost_equal(rect_corner_radius(100.0, 200.0, 40.0), 20.0, atol=1e-9)


def test_rect_corner_radius_zero_stays_zero() raises -> None:
    assert_almost_equal(rect_corner_radius(0.0, 100.0, 100.0), 0.0, atol=1e-9)


def test_rect_corner_radius_negative_floors_at_zero() raises -> None:
    assert_almost_equal(rect_corner_radius(-5.0, 100.0, 100.0), 0.0, atol=1e-9)


def test_vertex_max_radius_matches_rect_at_a_right_angle() raises -> None:
    # A 90-degree vertex with legs of length 20 each bounds a fillet exactly
    # like a square rect's own `min(w, h) / 2` at that same angle.
    var r = _vertex_max_radius(0.0, 0.0, 20.0, 0.0, 0.0, 20.0)
    assert_almost_equal(r, 10.0, atol=1e-6)


def test_triangle_corner_radius_clamps_a_thin_triangle_without_dividing_by_zero() raises -> (
    None
):
    var r = triangle_corner_radius(100.0, 0.0, 0.0, 100.0, 0.5, 200.0, 0.0)
    assert_true(r >= 0.0)
    assert_true(r < 5.0)


def test_triangle_corner_radius_collinear_triple_is_zero() raises -> None:
    # Not exactly 0 — the near-pi clamp in _vertex_max_radius leaves a
    # floating-point epsilon — but negligible, which is the point: a
    # collinear triple self-gates to (effectively) no rounding.
    var r = triangle_corner_radius(50.0, 0.0, 0.0, 10.0, 0.0, 20.0, 0.0)
    assert_almost_equal(r, 0.0, atol=1e-4)


def test_corner_fillet_on_a_known_right_angle_corner() raises -> None:
    # Vertex at the origin, edges running along +x and +y — a 90-degree
    # corner with radius 5. Tangent points sit exactly `r` back along each
    # edge; the centre sits at `r * sqrt(2)` along the bisector (1, 1)/sqrt(2).
    var result = corner_fillet(0.0, 0.0, 20.0, 0.0, 0.0, 20.0, 5.0)
    var cx = result[0]
    var cy = result[1]
    var tin_x = result[2]
    var tin_y = result[3]
    var tout_x = result[4]
    var tout_y = result[5]

    assert_almost_equal(tin_x, 5.0, atol=1e-6)
    assert_almost_equal(tin_y, 0.0, atol=1e-6)
    assert_almost_equal(tout_x, 0.0, atol=1e-6)
    assert_almost_equal(tout_y, 5.0, atol=1e-6)
    assert_almost_equal(cx, 5.0, atol=1e-6)
    assert_almost_equal(cy, 5.0, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
