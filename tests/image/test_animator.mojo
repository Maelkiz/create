from std.memory import ArcPointer
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from create.image import Image, Animation, Animator


def _animation(count: Int, fps: Float64 = 10.0) raises -> ArcPointer[Animation]:
    var frames = List[Image]()
    for i in range(count):
        frames.append(Image.solid(1, 1, UInt8(i), 0, 0))
    return ArcPointer(Animation(frames^, fps))


def test_starts_stopped_on_frame_zero() raises -> None:
    var a = Animator(_animation(4))
    assert_equal(a.frame_index, 0)
    assert_false(a.is_playing())
    a.update(10.0)
    assert_equal(a.frame_index, 0)


def test_advances_at_the_animation_rate() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.play()
    a.update(0.09)
    assert_equal(a.frame_index, 0)
    a.update(0.02)  # 0.11s total -- one frame duration passed
    assert_equal(a.frame_index, 1)


def test_loop_wraps() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    for _ in range(10):
        a.update(0.1)
    # 10 steps over 4 frames: 0 -> 10 % 4 == 2
    assert_equal(a.frame_index, 2)
    assert_true(a.is_playing())
    assert_false(a.is_finished())


def test_play_holds_the_last_frame() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.play()
    for _ in range(10):
        a.update(0.1)
    assert_equal(a.frame_index, 3)
    assert_false(a.is_playing())
    assert_true(a.is_finished())


def test_one_long_frame_matches_many_short_ones() raises -> None:
    var stepped = Animator(_animation(8, fps=10.0))
    stepped.loop()
    for _ in range(10):
        stepped.update(0.1)
    var jumped = Animator(_animation(8, fps=10.0))
    jumped.loop()
    jumped.update(1.0)
    assert_equal(stepped.frame_index, jumped.frame_index)


def test_pause_freezes_and_resume_continues() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    a.update(0.1)
    a.pause()
    assert_false(a.is_playing())
    a.update(10.0)
    assert_equal(a.frame_index, 1)
    a.resume()
    a.update(0.1)
    assert_equal(a.frame_index, 2)


def test_stop_rewinds() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    a.update(0.2)
    a.stop()
    assert_equal(a.frame_index, 0)
    assert_false(a.is_playing())
    a.update(10.0)
    assert_equal(a.frame_index, 0)


def test_resume_after_finish_does_not_restart() raises -> None:
    var a = Animator(_animation(2, fps=10.0))
    a.play()
    a.update(1.0)
    assert_true(a.is_finished())
    a.resume()
    assert_false(a.is_playing())
    assert_equal(a.frame_index, 1)


def test_use_of_the_current_animation_is_a_no_op() raises -> None:
    var anim = _animation(4, fps=10.0)
    var a = Animator(anim.copy())
    a.loop()
    a.update(0.2)
    assert_equal(a.frame_index, 2)
    # The call every frame from a movement branch -- must not rewind.
    a.use(anim.copy())
    assert_equal(a.frame_index, 2)
    assert_true(a.is_playing())


def test_loop_of_the_current_animation_is_a_no_op() raises -> None:
    var anim = _animation(4, fps=10.0)
    var a = Animator(anim.copy())
    a.loop(anim.copy())
    a.update(0.2)
    for _ in range(3):
        a.loop(anim.copy())
        assert_equal(a.frame_index, 2)
        assert_true(a.is_playing())


def test_use_of_another_animation_rewinds_and_stops() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    a.update(0.2)
    a.use(_animation(2, fps=10.0))
    assert_equal(a.frame_index, 0)
    assert_false(a.is_playing())
    assert_equal(a.animation[].count(), 2)


def test_play_with_an_animation_switches_and_starts() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.play(_animation(2, fps=10.0))
    assert_true(a.is_playing())
    assert_equal(a.animation[].count(), 2)
    a.update(0.1)
    assert_equal(a.frame_index, 1)


def test_play_restarts_the_current_animation() raises -> None:
    var anim = _animation(4, fps=10.0)
    var a = Animator(anim.copy())
    a.loop()
    a.update(0.2)
    a.play(anim.copy())
    assert_equal(a.frame_index, 0)
    assert_true(a.is_playing())


def test_single_frame_animation_finishes() raises -> None:
    var a = Animator(_animation(1, fps=10.0))
    a.play()
    a.update(0.1)
    assert_equal(a.frame_index, 0)
    assert_true(a.is_finished())


def test_writes_the_playhead() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    a.update(0.2)
    assert_equal(String(a), "Animator(frame_index=2)")


def test_a_copy_plays_independently_over_the_same_animation() raises -> None:
    var a = Animator(_animation(4, fps=10.0))
    a.loop()
    var b = a.copy()
    b.update(0.2)
    assert_equal(a.frame_index, 0)
    assert_equal(b.frame_index, 2)
    assert_true(Pointer(to=a.animation[]) == Pointer(to=b.animation[]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
