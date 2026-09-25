from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
)
from create.render.autoscale import AutoScale
from create.render.viewport import Viewport
from create.math.matrix import apply


def _design(w: Int, h: Int, mode: AutoScale) raises -> Viewport:
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
    var p = v.to_screen((512.0, 284.0))
    assert_almost_equal(p.x, 0.0)
    assert_almost_equal(p.y, 100.0)
    var q = v.to_screen((512.0, 484.0))
    assert_almost_equal(q.y, -100.0)


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
    var w = v.to_screen((x, y))
    var back = apply(v.base_matrix(), w.x, w.y)
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


def test_fit_shrinks_below_the_design_size() raises -> None:
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(400, 300)
    assert_almost_equal(v.scale, 0.5)
    assert_equal(v.width, 800)
    assert_equal(v.height, 600)


def test_extend_heightens_the_world_instead_of_letterboxing() raises -> None:
    var v = _design(800, 600, AutoScale.EXTEND)
    v.set_size(800, 1200)
    assert_almost_equal(v.scale, 1.0)
    assert_equal(v.width, 800)
    assert_equal(v.height, 1200)
    assert_equal(v.offset_x, 0.0)
    assert_equal(v.offset_y, 0.0)


def test_extend_matches_fit_when_the_aspect_matches() raises -> None:
    var v = _design(800, 600, AutoScale.EXTEND)
    v.set_size(1600, 1200)
    assert_almost_equal(v.scale, 2.0)
    assert_equal(v.width, 800)
    assert_equal(v.height, 600)


def test_extend_reports_the_slack_on_the_unconstrained_axis() raises -> None:
    # Height constrains: 700/600 < 1000/800. The design height survives the
    # round-trip through the scale, and the width picks up the slack.
    var v = _design(800, 600, AutoScale.EXTEND)
    v.set_size(1000, 700)
    assert_almost_equal(v.scale, 700.0 / 600.0)
    assert_equal(v.height, 600)
    assert_equal(v.width, 857)


def test_to_screen_centres_the_framebuffer_centre() raises -> None:
    var v = Viewport()
    v.set_size(1024, 768)
    var c = v.to_screen((512.0, 384.0))
    assert_equal(c.x, 0.0)
    assert_equal(c.y, 0.0)
    var p = v.to_screen((120.0, 40.0))
    assert_equal(p.x, -392.0)
    assert_equal(p.y, 344.0)


def test_to_screen_maps_the_top_left_pixel_to_the_top_left_corner() raises -> (
    None
):
    var v = Viewport()
    v.set_size(1024, 768)
    var p = v.to_screen((0.0, 0.0))
    assert_almost_equal(p.x, v.left())
    assert_almost_equal(p.y, v.top())


def test_to_screen_maps_the_window_centre_to_the_origin_under_fit() raises -> (
    None
):
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 900)
    var p = v.to_screen((800.0, 450.0))
    assert_almost_equal(p.x, 0.0)
    assert_almost_equal(p.y, 0.0)


def test_to_screen_maps_a_letterboxed_corner_to_the_design_corner() raises -> (
    None
):
    # 800x600 into 1600x600: scale 1, 400px bars either side. The inner edge of
    # the left bar is the design area's left edge.
    var v = _design(800, 600, AutoScale.FIT)
    v.set_size(1600, 600)
    var p = v.to_screen((400.0, 0.0))
    assert_almost_equal(p.x, v.left())
    assert_almost_equal(p.y, v.top())


def test_to_screen_corners_under_extend() raises -> None:
    var v = _design(800, 600, AutoScale.EXTEND)
    v.set_size(1600, 1200)
    var origin = v.to_screen((0.0, 0.0))
    assert_almost_equal(origin.x, v.left())
    assert_almost_equal(origin.y, v.top())
    var p = v.to_screen((1200.0, 800.0))
    assert_almost_equal(p.x, 200.0)
    assert_almost_equal(p.y, -100.0)


def test_autoscale_writes_its_constant_name() raises -> None:
    assert_equal(String(AutoScale.OFF), "AutoScale.OFF")
    assert_equal(String(AutoScale.EXTEND), "AutoScale.EXTEND")
    assert_equal(String(AutoScale(99)), "AutoScale(99)")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
