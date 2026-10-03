from std.os import remove
from std.testing import TestSuite, assert_equal, assert_raises
from create.color.color import Color
from create.render.surface import MemorySurface, Surface
from create.sprite.sprite import Sprite


def _scratch(name: String) -> String:
    """A throwaway path for a file a test writes and then deletes.

    Outside the repo deliberately: a test that leaves artefacts in the tree is
    a test that eventually gets committed by accident.
    """
    return "/tmp/mojo_create_test_" + name


def _loaded(
    mem: MemorySurface, name: String, opaque: Bool = True
) raises -> Sprite:
    """Save `mem` as a PNG, read it back as a `Sprite`, and delete the file."""
    var path = _scratch(name)
    mem.save(path, opaque)
    var back = Sprite.load(path)
    remove(path)
    return back^


def _pixel(s: Sprite, x: Int, y: Int) -> Color:
    var off = (y * s.width + x) * 4
    return Color(
        s.pixels[off], s.pixels[off + 1], s.pixels[off + 2], s.pixels[off + 3]
    )


def _write(mut s: Surface, x: Int, y: Int, c: Color):
    var off = s.offset(x, y)
    s.px[unsafe_offset=off] = c.r
    s.px[unsafe_offset=off + 1] = c.g
    s.px[unsafe_offset=off + 2] = c.b
    s.px[unsafe_offset=off + 3] = c.a


def test_a_new_surface_is_transparent_black() raises -> None:
    var mem = MemorySurface(4, 3)
    assert_equal(mem.pixel(0, 0), Color(0, 0, 0, 0))
    assert_equal(mem.pixel(3, 2), Color(0, 0, 0, 0))


def test_offset_is_row_major_rgba() raises -> None:
    var mem = MemorySurface(4, 3)
    var s = mem.surface()
    assert_equal(s.offset(0, 0), 0)
    assert_equal(s.offset(1, 0), 4)
    assert_equal(s.offset(0, 1), 16)
    assert_equal(s.offset(3, 2), 44)


def test_a_write_through_a_surface_reads_back_from_the_owner() raises -> None:
    var mem = MemorySurface(4, 3)
    var s = mem.surface()
    _write(s, 2, 1, Color(10, 20, 30, 40))
    assert_equal(mem.pixel(2, 1), Color(10, 20, 30, 40))


def test_a_write_leaves_every_other_pixel_untouched() raises -> None:
    var mem = MemorySurface(4, 3)
    var s = mem.surface()
    _write(s, 2, 1, Color.WHITE)
    for y in range(3):
        for x in range(4):
            if x == 2 and y == 1:
                continue
            assert_equal(mem.pixel(x, y), Color(0, 0, 0, 0))


def test_the_surface_reports_the_owners_dimensions() raises -> None:
    var mem = MemorySurface(7, 5)
    var s = mem.surface()
    assert_equal(s.width, 7)
    assert_equal(s.height, 5)


def test_a_saved_surface_reloads_with_the_same_pixels() raises -> None:
    var mem = MemorySurface(4, 3)
    var s = mem.surface()
    _write(s, 0, 0, Color(10, 20, 30))
    _write(s, 3, 0, Color(200, 0, 0))
    _write(s, 1, 2, Color(0, 200, 0))
    _write(s, 3, 2, Color(0, 0, 200))

    var back = _loaded(mem, "roundtrip.png")
    assert_equal(back.width, 4)
    assert_equal(back.height, 3)
    assert_equal(_pixel(back, 0, 0), Color(10, 20, 30))
    assert_equal(_pixel(back, 3, 0), Color(200, 0, 0))
    assert_equal(_pixel(back, 1, 2), Color(0, 200, 0))
    assert_equal(_pixel(back, 3, 2), Color(0, 0, 200))


def test_saving_forces_alpha_opaque_by_default() raises -> None:
    # A framebuffer's unused byte is frequently 0; an image that opens fully
    # transparent is the trap `opaque` exists to avoid.
    var mem = MemorySurface(2, 2)
    var s = mem.surface()
    _write(s, 0, 0, Color(90, 90, 90, 0))
    var back = _loaded(mem, "opaque.png")
    assert_equal(_pixel(back, 0, 0), Color(90, 90, 90, 255))


def test_saving_keeps_alpha_when_opacity_is_not_forced() raises -> None:
    var mem = MemorySurface(2, 2)
    var s = mem.surface()
    _write(s, 1, 1, Color(90, 90, 90, 128))
    var back = _loaded(mem, "alpha.png", opaque=False)
    assert_equal(_pixel(back, 1, 1), Color(90, 90, 90, 128))
    assert_equal(_pixel(back, 0, 0), Color(0, 0, 0, 0))


def test_saving_to_a_missing_directory_raises() raises -> None:
    var mem = MemorySurface(2, 2)
    with assert_raises():
        mem.save("/nonexistent-directory-for-a-test/out.png")


def test_saving_a_surface_with_no_area_raises() raises -> None:
    var mem = MemorySurface(0, 0)
    with assert_raises():
        mem.save(_scratch("empty.png"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
