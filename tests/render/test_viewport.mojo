from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from create.render.autoscale import AutoScale
from create.render.viewport import Viewport
from create.math.matrix import apply


def _design(w: Int, h: Int, mode: Int) raises -> Viewport:
    var v = Viewport()
    v.autoscale = mode
    v.set_design(w, h)
    return v^


def test_off_passes_the_framebuffer_size_through() raises -> None:
    var v = Viewport()
    v.set_size(1024, 768)
    assert_equal(v.width, 1024)
    assert_equal(v.height, 768)
    assert_equal(v.scale, 1.0)
    assert_equal(v.offset_x, 0.0)
    assert_equal(v.offset_y, 0.0)
    assert_true(not v.scaled())


def test_fit_keeps_the_design_size_and_scales() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 1200)
    assert_equal(v.width, 800)
    assert_equal(v.height, 600)
    assert_almost_equal(v.scale, 2.0)
    assert_equal(v.offset_x, 0.0)
    assert_equal(v.offset_y, 0.0)
    assert_true(v.scaled())


def test_fit_centres_with_pillarbox_bars() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 600)
    assert_almost_equal(v.scale, 1.0)
    assert_equal(v.offset_x, 400.0)
    assert_equal(v.offset_y, 0.0)
    # Offsets alone make the mapping non-trivial even at scale 1.
    assert_true(v.scaled())


def test_fit_centres_with_letterbox_bars() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(800, 1200)
    assert_almost_equal(v.scale, 1.0)
    assert_equal(v.offset_x, 0.0)
    assert_equal(v.offset_y, 300.0)


def test_extend_grows_the_reported_size_at_the_fit_scale() raises -> None:
    var fit = _design(800, 600, AutoScale.FIT)
    fit.set_size(1600, 600)
    var ext = _design(800, 600, AutoScale.EXTEND)
    ext.set_size(1600, 600)
    # Same uniform factor as FIT — only the leftover area differs.
    assert_almost_equal(ext.scale, fit.scale)
    assert_equal(ext.width, 1600)
    assert_equal(ext.height, 600)
    assert_equal(ext.offset_x, 0.0)
    assert_equal(ext.offset_y, 0.0)


def test_autoscale_ignored_before_a_design_size_is_known() raises -> None:
    var v = Viewport()
    v.autoscale = AutoScale.FIT
    v.set_size(1024, 768)
    assert_equal(v.width, 1024)
    assert_equal(v.scale, 1.0)


def test_edges_straddle_the_origin() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 1200)
    assert_almost_equal(v.left(), -400.0)
    assert_almost_equal(v.right(), 400.0)
    assert_almost_equal(v.bottom(), -300.0)
    assert_almost_equal(v.top(), 300.0)


def test_to_screen_inverts_the_y_axis() raises -> None:
    var v = Viewport()
    v.set_size(1024, 768)
    # A pixel above the centre row is positive world y.
    var p = v.to_screen(512.0, 284.0)
    assert_almost_equal(p[0], 0.0)
    assert_almost_equal(p[1], 100.0)
    var q = v.to_screen(512.0, 484.0)
    assert_almost_equal(q[1], -100.0)


def test_base_matrix_puts_positive_y_in_lower_rows() raises -> None:
    var v = Viewport()
    v.set_size(1024, 768)
    var top = apply(v.base_matrix(), 0.0, 100.0)
    var bottom = apply(v.base_matrix(), 0.0, -100.0)
    assert_almost_equal(top[0], 512.0)
    assert_almost_equal(top[1], 284.0)
    assert_true(top[1] < bottom[1])


def _assert_base_round_trips(v: Viewport, x: Float64, y: Float64) raises:
    """`base_matrix` maps screen to pixels; `to_screen` is its inverse."""
    var w = v.to_screen(x, y)
    var back = apply(v.base_matrix(), w[0], w[1])
    assert_almost_equal(back[0], x)
    assert_almost_equal(back[1], y)


def test_base_matrix_inverts_to_screen() raises -> None:
    var off = Viewport()
    off.set_size(1024, 768)
    _assert_base_round_trips(off, 0.0, 0.0)
    _assert_base_round_trips(off, 731.0, 12.0)

    var fit = _design(800, 600, AutoScale.FIT)
    fit.set_size(1600, 600)
    _assert_base_round_trips(fit, 400.0, 0.0)
    _assert_base_round_trips(fit, 1201.0, 517.0)

    var extend = _design(800, 600, AutoScale.EXTEND)
    extend.set_size(1000, 700)
    _assert_base_round_trips(extend, 0.0, 0.0)
    _assert_base_round_trips(extend, 913.0, 44.0)


def test_set_design_overrides_an_earlier_one() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 1200)
    v.set_design(1000, 500)
    v.set_size(2000, 1000)
    assert_almost_equal(v.scale, 2.0)
    assert_equal(v.width, 1000)
    assert_equal(v.height, 500)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
