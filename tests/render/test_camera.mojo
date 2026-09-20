# Camera tests: the matrix composition through run_headless (pixels prove the
# pipeline), plus Camera's own arithmetic in isolation.

from std.testing import TestSuite, assert_equal, assert_almost_equal

from create import *
from create.core.headless import run_headless
from create.math.point2d import Point2D


@fieldwise_init
struct IdentityCameraRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> IdentityCameraRect:
        return IdentityCameraRect(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.camera(Camera())
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 20.0, 20.0)


def test_identity_camera_matches_no_camera() raises -> None:
    # Default Camera() is identity, so this must match plain-rect rendering
    # exactly — a regression guard on the new base @ camera @ user pipeline.
    var m = run_headless[IdentityCameraRect](100, 100)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(41, 41), Color.RED)
    assert_equal(m.pixel(58, 58), Color.RED)
    assert_equal(m.pixel(38, 38), Color.BLACK)


@fieldwise_init
struct PannedCameraRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> PannedCameraRect:
        return PannedCameraRect(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.camera(Camera(Point2D(20.0, 0.0), 1.0))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 20.0, 20.0)


def test_camera_position_pans_world_content() raises -> None:
    # A rect drawn at world (0, 0) with the camera centred on world (20, 0)
    # lands 20 units left of screen centre, i.e. at pixel (30, 50).
    var m = run_headless[PannedCameraRect](100, 100)
    assert_equal(m.pixel(30, 50), Color.RED)
    assert_equal(m.pixel(50, 50), Color.BLACK)


@fieldwise_init
struct ZoomedCameraRect(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> ZoomedCameraRect:
        return ZoomedCameraRect(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.camera(Camera(Point2D(0.0, 0.0), 2.0))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        frame.rectangle(0.0, 0.0, 20.0, 20.0)


def test_camera_zoom_scales_world_content() raises -> None:
    # A 20x20 rect at 2x zoom covers 40x40 screen pixels, so a point 15px from
    # centre (inside the zoomed footprint, outside the unzoomed one) is now
    # covered.
    var m = run_headless[ZoomedCameraRect](100, 100)
    assert_equal(m.pixel(65, 50), Color.RED)


@fieldwise_init
struct OverlayIgnoresCamera(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> OverlayIgnoresCamera:
        return OverlayIgnoresCamera(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.camera(Camera(Point2D(50.0, 0.0), 1.0))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        with frame.overlay():
            frame.rectangle(0.0, 0.0, 20.0, 20.0)


def test_overlay_ignores_the_active_camera() raises -> None:
    # Despite the camera panning 50 world units, the overlaid rect still
    # lands centred on screen — overlay draws in screen space regardless.
    var m = run_headless[OverlayIgnoresCamera](100, 100)
    assert_equal(m.pixel(50, 50), Color.RED)
    assert_equal(m.pixel(0, 50), Color.BLACK)


@fieldwise_init
struct OverlayRestoresCamera(Program):
    var _unused: Int

    @staticmethod
    def create(mut ctx: Context) raises -> OverlayRestoresCamera:
        return OverlayRestoresCamera(0)

    def render(self, mut frame: Frame) raises:
        frame.background(Color.BLACK)
        frame.camera(Camera(Point2D(20.0, 0.0), 1.0))
        frame.outline(enabled=False)
        frame.fill(Color.RED)
        with frame.overlay():
            pass
        # The camera set before overlay() must still be active afterwards.
        frame.rectangle(0.0, 0.0, 20.0, 20.0)


def test_overlay_restores_the_camera_on_exit() raises -> None:
    var m = run_headless[OverlayRestoresCamera](100, 100)
    assert_equal(m.pixel(30, 50), Color.RED)
    assert_equal(m.pixel(50, 50), Color.BLACK)


def test_to_world_and_to_screen_round_trip() raises -> None:
    var cam = Camera(Point2D(10.0, -5.0), 2.0)
    var screen = Point2D(30.0, 40.0)
    var world = cam.to_world(screen)
    var back = cam.to_screen(world)
    assert_almost_equal(back.x, screen.x)
    assert_almost_equal(back.y, screen.y)


def test_to_world_accounts_for_position_and_zoom() raises -> None:
    var cam = Camera(Point2D(100.0, 0.0), 2.0)
    # Screen origin maps to the camera's own world position.
    var world = cam.to_world(Point2D(0.0, 0.0))
    assert_almost_equal(world.x, 100.0)
    assert_almost_equal(world.y, 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
