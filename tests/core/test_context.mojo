from std.testing import (
    TestSuite,
    assert_equal,
    assert_almost_equal,
    assert_raises,
)
from create.render.autoscale import AutoScale
from create.math.matrix import apply
from create.core.context import Context


def _design(w: Int, h: Int, mode: Int) raises -> Context:
    var ctx = Context()
    ctx.design(w, h, mode)
    return ctx^


def _fit(w: Int, h: Int) raises -> Context:
    return _design(w, h, AutoScale.FIT)


def _extend(w: Int, h: Int) raises -> Context:
    return _design(w, h, AutoScale.EXTEND)


def test_viewport_passthrough_without_autoscale() raises -> None:
    var ctx = Context()
    ctx._set_viewport(1024, 768)
    assert_equal(ctx.width, 1024)
    assert_equal(ctx.height, 768)
    assert_equal(ctx.scale, 1.0)
    assert_equal(ctx.view.offset_x, 0.0)
    assert_equal(ctx.view.offset_y, 0.0)


def test_fit_keeps_design_dimensions() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(1600, 1200)
    assert_equal(ctx.width, 800)
    assert_equal(ctx.height, 600)
    assert_equal(ctx.left(), -400.0)
    assert_equal(ctx.top(), 300.0)


def test_fit_uniform_scale_no_letterbox() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(1600, 1200)
    assert_equal(ctx.scale, 2.0)
    assert_equal(ctx.view.offset_x, 0.0)
    assert_equal(ctx.view.offset_y, 0.0)


def test_fit_letterboxes_wider_window() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(1600, 600)
    assert_equal(ctx.scale, 1.0)
    assert_equal(ctx.view.offset_x, 400.0)
    assert_equal(ctx.view.offset_y, 0.0)


def test_fit_letterboxes_taller_window() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(800, 1200)
    assert_equal(ctx.scale, 1.0)
    assert_equal(ctx.view.offset_x, 0.0)
    assert_equal(ctx.view.offset_y, 300.0)


def test_fit_shrinks_below_design_size() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(400, 300)
    assert_equal(ctx.scale, 0.5)


def test_extend_widens_world_instead_of_letterboxing() raises -> None:
    var ctx = _extend(800, 600)
    ctx._set_viewport(1600, 600)
    assert_equal(ctx.scale, 1.0)
    assert_equal(ctx.width, 1600)
    assert_equal(ctx.height, 600)
    assert_equal(ctx.view.offset_x, 0.0)
    assert_equal(ctx.view.offset_y, 0.0)
    assert_equal(ctx.right(), 800.0)
    assert_equal(ctx.top(), 300.0)


def test_extend_heightens_world_instead_of_letterboxing() raises -> None:
    var ctx = _extend(800, 600)
    ctx._set_viewport(800, 1200)
    assert_equal(ctx.scale, 1.0)
    assert_equal(ctx.width, 800)
    assert_equal(ctx.height, 1200)
    assert_equal(ctx.view.offset_x, 0.0)
    assert_equal(ctx.view.offset_y, 0.0)


def test_extend_matches_fit_when_aspect_matches() raises -> None:
    var ctx = _extend(800, 600)
    ctx._set_viewport(1600, 1200)
    assert_equal(ctx.scale, 2.0)
    assert_equal(ctx.width, 800)
    assert_equal(ctx.height, 600)


def test_extend_scale_is_still_the_fit_factor() raises -> None:
    # Height constrains: 700/600 < 1000/800. The design height survives the
    # round-trip through the scale, and the width picks up the slack.
    var ctx = _extend(800, 600)
    ctx._set_viewport(1000, 700)
    assert_almost_equal(ctx.scale, 700.0 / 600.0)
    assert_equal(ctx.height, 600)
    assert_equal(ctx.width, 857)


def test_to_screen_centres_the_origin_without_autoscale() raises -> None:
    var ctx = Context()
    ctx._set_viewport(1024, 768)
    var c = ctx.to_screen(512.0, 384.0)
    assert_equal(c[0], 0.0)
    assert_equal(c[1], 0.0)
    # Pixel space runs y down, world space runs y up.
    var p = ctx.to_screen(120.0, 40.0)
    assert_equal(p[0], -392.0)
    assert_equal(p[1], 344.0)


def test_to_screen_maps_top_left_pixel_to_the_top_left_corner() raises -> None:
    var ctx = Context()
    ctx._set_viewport(1024, 768)
    var p = ctx.to_screen(0.0, 0.0)
    assert_almost_equal(p[0], ctx.left())
    assert_almost_equal(p[1], ctx.top())


def test_to_screen_maps_window_centre_to_origin_under_fit() raises -> None:
    var ctx = _fit(800, 600)
    ctx._set_viewport(1600, 900)
    var p = ctx.to_screen(800.0, 450.0)
    assert_almost_equal(p[0], 0.0)
    assert_almost_equal(p[1], 0.0)


def test_to_screen_maps_letterboxed_corner_to_design_corner() raises -> None:
    # 800x600 into 1600x600: scale 1, 400px bars either side. The inner edge of
    # the left bar is the design area's left edge.
    var ctx = _fit(800, 600)
    ctx._set_viewport(1600, 600)
    var p = ctx.to_screen(400.0, 0.0)
    assert_almost_equal(p[0], ctx.left())
    assert_almost_equal(p[1], ctx.top())


def test_to_screen_corners_under_extend() raises -> None:
    var ctx = _extend(800, 600)
    ctx._set_viewport(1600, 1200)
    var origin = ctx.to_screen(0.0, 0.0)
    assert_almost_equal(origin[0], ctx.left())
    assert_almost_equal(origin[1], ctx.top())
    var p = ctx.to_screen(1200.0, 800.0)
    assert_almost_equal(p[0], 200.0)
    assert_almost_equal(p[1], -100.0)


def _assert_base_round_trips(ctx: Context, x: Float64, y: Float64) raises:
    """`_base_matrix` maps screen to pixels; `to_screen` is its inverse."""
    var w = ctx.to_screen(x, y)
    var back = apply(ctx._base_matrix(), w[0], w[1])
    assert_almost_equal(back[0], x)
    assert_almost_equal(back[1], y)


def test_base_matrix_inverts_to_screen() raises -> None:
    var off = Context()
    off._set_viewport(1024, 768)
    _assert_base_round_trips(off, 0.0, 0.0)
    _assert_base_round_trips(off, 731.0, 12.0)

    var fit = _fit(800, 600)
    fit._set_viewport(1600, 600)
    _assert_base_round_trips(fit, 400.0, 0.0)
    _assert_base_round_trips(fit, 1201.0, 517.0)

    var extend = _extend(800, 600)
    extend._set_viewport(1000, 700)
    _assert_base_round_trips(extend, 0.0, 0.0)
    _assert_base_round_trips(extend, 913.0, 44.0)


def test_autoscale_ignored_before_design_size_known() raises -> None:
    var ctx = Context()
    ctx.autoscale = AutoScale.FIT
    ctx._set_viewport(1024, 768)
    assert_equal(ctx.width, 1024)
    assert_equal(ctx.scale, 1.0)


def test_design_sets_size_and_mode() raises -> None:
    var ctx = Context()
    ctx.design(800, 600)
    ctx._set_viewport(1600, 1200)
    assert_equal(ctx.autoscale, AutoScale.FIT)
    assert_equal(ctx.width, 800)
    assert_equal(ctx.height, 600)


def test_design_recomputes_viewport_immediately() raises -> None:
    # The mapping must be live before create() returns, not one frame later.
    var ctx = Context()
    ctx._set_viewport(1600, 1200)
    ctx.design(800, 600)
    assert_equal(ctx.width, 800)
    assert_equal(ctx.height, 600)
    assert_almost_equal(ctx.scale, 2.0)


def test_design_overrides_earlier_design() raises -> None:
    var ctx = Context()
    ctx.design(800, 600)
    ctx.design(1000, 500, AutoScale.EXTEND)
    ctx._set_viewport(2000, 1000)
    assert_equal(ctx.autoscale, AutoScale.EXTEND)
    assert_almost_equal(ctx.scale, 2.0)
    assert_equal(ctx.width, 1000)
    assert_equal(ctx.height, 500)


def test_framerate_zero_before_first_tick() raises -> None:
    var ctx = Context()
    assert_equal(ctx.framerate(), 0.0)


def test_framerate_is_inverse_of_delta() raises -> None:
    var ctx = Context()
    ctx.time._start(0)
    ctx.time._tick(20)
    assert_almost_equal(ctx.framerate(), 50.0)


def test_frame_cap_stores_the_target_fps() raises -> None:
    var ctx = Context()
    ctx.frame_cap(30)
    assert_equal(ctx._frame_cap_fps, 30)


def test_frame_cap_rejects_non_positive_fps() raises -> None:
    var ctx = Context()
    with assert_raises(contains="fps must be positive"):
        ctx.frame_cap(0)
    with assert_raises(contains="fps must be positive"):
        ctx.frame_cap(-5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
