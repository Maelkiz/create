from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from create.sprite import Sprite, SpriteAnimation
from create.sprite.animation import _frame_number, _sort_frame_names


def _sheet(cols: Int, rows: Int, cell: Int) raises -> Sprite:
    """A cols x rows sheet of `cell`-sized cells, each a distinct solid red.

    Cell n is filled with R = n + 1, so a frame's identity is readable from any
    one of its pixels.
    """
    var w = cols * cell
    var h = rows * cell
    var data = List[UInt8](length=w * h * 4, fill=0)
    var ptr = data.unsafe_ptr()
    for y in range(h):
        for x in range(w):
            var index = (y // cell) * cols + (x // cell)
            var off = (y * w + x) * 4
            ptr[unsafe_offset=off] = UInt8(index + 1)
            ptr[unsafe_offset=off + 3] = 255
    return Sprite.from_rgba(w, h, data)


def _red(s: Sprite, x: Int, y: Int) -> Int:
    return Int(s._pixels.unsafe_ptr()[unsafe_offset=(y * s.width + x) * 4])


def _green(s: Sprite, x: Int, y: Int) -> Int:
    return Int(s._pixels.unsafe_ptr()[unsafe_offset=(y * s.width + x) * 4 + 1])


def _blue(s: Sprite, x: Int, y: Int) -> Int:
    return Int(s._pixels.unsafe_ptr()[unsafe_offset=(y * s.width + x) * 4 + 2])


def test_from_sheet_cuts_every_cell() raises -> None:
    var anim = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 3, 3)
    assert_equal(anim.count(), 4)
    for i in range(4):
        assert_equal(anim.frames[i].width, 3)
        assert_equal(anim.frames[i].height, 3)


def test_from_sheet_is_row_major() raises -> None:
    var anim = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 3, 3)
    for i in range(4):
        # Every pixel of frame i carries that cell's marker.
        assert_equal(_red(anim.frames[i], 0, 0), i + 1)
        assert_equal(_red(anim.frames[i], 2, 2), i + 1)


def test_from_sheet_window() raises -> None:
    var anim = SpriteAnimation.from_sheet(
        _sheet(2, 2, 3), 3, 3, start=2, count=2
    )
    assert_equal(anim.count(), 2)
    assert_equal(_red(anim.frames[0], 0, 0), 3)
    assert_equal(_red(anim.frames[1], 0, 0), 4)


def test_from_sheet_count_zero_takes_the_rest() raises -> None:
    var anim = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 3, 3, start=1)
    assert_equal(anim.count(), 3)
    assert_equal(_red(anim.frames[0], 0, 0), 2)


def test_frame_duration_is_the_inverse_of_fps() raises -> None:
    var anim = SpriteAnimation.from_sheet(_sheet(2, 1, 2), 2, 2, fps=10.0)
    assert_equal(anim.frame_duration(), 0.1)


def test_default_fps() raises -> None:
    var anim = SpriteAnimation.from_sheet(_sheet(2, 1, 2), 2, 2)
    assert_equal(anim.fps, 12.0)


def test_empty_frame_list_raises() raises -> None:
    with assert_raises(contains="at least one frame"):
        _ = SpriteAnimation(List[Sprite]())


def test_non_positive_fps_raises() raises -> None:
    var frames = List[Sprite]()
    frames.append(Sprite.solid(1, 1, 255, 255, 255))
    with assert_raises(contains="fps must be positive"):
        _ = SpriteAnimation(frames^, 0.0)


def test_indivisible_sheet_raises() raises -> None:
    with assert_raises(contains="whole number"):
        _ = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 4, 4)


def test_non_positive_frame_size_raises() raises -> None:
    with assert_raises(contains="frame size must be positive"):
        _ = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 0, 3)


def test_start_past_the_end_raises() raises -> None:
    with assert_raises(contains="outside the sheet"):
        _ = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 3, 3, start=4)


def test_count_past_the_end_raises() raises -> None:
    with assert_raises(contains="run past the sheet"):
        _ = SpriteAnimation.from_sheet(_sheet(2, 2, 3), 3, 3, start=2, count=3)


def test_from_folder_frame_count() raises -> None:
    var anim = SpriteAnimation.from_folder("tests/fixtures/anim")
    # notes.txt in the same directory is skipped.
    assert_equal(anim.count(), 3)


def test_from_folder_orders_naturally() raises -> None:
    # frame_1 is red, frame_2 green, frame_10 blue -- so the order is readable
    # from the pixels. Lexicographic order would put frame_10 second.
    var anim = SpriteAnimation.from_folder("tests/fixtures/anim")
    assert_equal(_red(anim.frames[0], 0, 0), 255)
    assert_equal(_green(anim.frames[1], 0, 0), 255)
    assert_equal(_blue(anim.frames[2], 0, 0), 255)


def test_from_folder_fps() raises -> None:
    var anim = SpriteAnimation.from_folder("tests/fixtures/anim", fps=24.0)
    assert_equal(anim.fps, 24.0)


def test_from_folder_without_images_raises() raises -> None:
    with assert_raises(contains="no BMP, PNG or JPEG files"):
        _ = SpriteAnimation.from_folder("tests/fixtures/anim_no_images")


def test_from_folder_missing_directory_raises() raises -> None:
    with assert_raises():
        _ = SpriteAnimation.from_folder("tests/fixtures/does_not_exist")


def test_frame_number_reads_the_trailing_digits() raises -> None:
    assert_equal(_frame_number("frame_10.png"), 10)
    assert_equal(_frame_number("run3.bmp"), 3)
    assert_equal(_frame_number("007.png"), 7)
    assert_equal(_frame_number("idle.png"), -1)


def test_sort_frame_names_is_natural() raises -> None:
    var names = List[String]()
    names.append("f_10.png")
    names.append("f_2.png")
    names.append("f_1.png")
    _sort_frame_names(names)
    assert_equal(names[0], "f_1.png")
    assert_equal(names[1], "f_2.png")
    assert_equal(names[2], "f_10.png")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
