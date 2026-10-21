# Requires SDL_AUDIO_DRIVER=dummy (set globally by the `test` pixi task) so
# this runs without real audio hardware.

from std.testing import TestSuite, assert_equal, assert_true, assert_false
from std.time import sleep
from create.audio import Audio, Sound


def _tone() -> Sound:
    var data = List[Int16](length=256, fill=0)
    return Sound.from_pcm(data)


def test_play_returns_valid_id() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    assert_true(audio.is_playing(id))


def test_stop_invalidates_id() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    audio.stop(id)
    assert_false(audio.is_playing(id))


def test_stop_all() raises -> None:
    var audio = Audio()
    var a = audio.play(_tone())
    var b = audio.play(_tone())
    audio.stop_all()
    assert_false(audio.is_playing(a))
    assert_false(audio.is_playing(b))


def test_pause_resume() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    audio.pause(id)
    assert_false(audio.is_playing(id))
    audio.resume(id)
    assert_true(audio.is_playing(id))


def test_stale_id_after_slot_recycle() raises -> None:
    var audio = Audio()
    var first = audio.play(_tone())
    audio.stop(first)
    var second = audio.play(_tone())
    # first's slot was recycled into second; the stale id must not alias it.
    assert_false(audio.is_playing(first))
    assert_true(audio.is_playing(second))


def test_play_loop_returns_valid_id() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone(), loop=True)
    assert_true(audio.is_playing(id))


def test_looping_voice_stays_live_across_updates() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone(), loop=True)
    for _ in range(5):
        audio.update()
    assert_true(audio.is_playing(id))


def test_stop_releases_looping_voice() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone(), loop=True)
    audio.stop(id)
    assert_false(audio.is_playing(id))


def test_stop_all_releases_looping_and_one_shot_together() raises -> None:
    var audio = Audio()
    var one_shot = audio.play(_tone())
    var looping = audio.play(_tone(), loop=True)
    audio.stop_all()
    assert_false(audio.is_playing(one_shot))
    assert_false(audio.is_playing(looping))


def test_looping_voice_shares_sound_via_refcount() raises -> None:
    var audio = Audio()
    var sound = _tone()
    assert_equal(sound._pcm.count(), 1)
    var id = audio.play(sound, loop=True)
    # `play` copies the sound into _Voice.loop_sound, sharing its samples.
    assert_equal(sound._pcm.count(), 2)
    audio.stop(id)
    assert_equal(sound._pcm.count(), 1)


def test_id_zero_is_never_valid() raises -> None:
    var audio = Audio()
    assert_false(audio.is_playing(0))
    audio.stop(0)
    audio.pause(0)
    audio.resume(0)
    audio.volume(0, 1.0)
    var id = audio.play(_tone())
    assert_false(audio.is_playing(0))
    assert_true(audio.is_playing(id))


def test_negative_id_is_invalid() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    assert_false(audio.is_playing(-1))
    audio.stop(-1)
    assert_true(audio.is_playing(id))


def test_out_of_range_id_is_invalid() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    var out_of_range = (1 << 32) | 9999  # index past the end of _voices
    assert_false(audio.is_playing(out_of_range))
    audio.stop(out_of_range)
    audio.pause(out_of_range)
    audio.resume(out_of_range)
    audio.volume(out_of_range, 1.0)
    assert_true(audio.is_playing(id))


def test_update_reaps_finished_one_shot_but_keeps_looping_voice() raises -> (
    None
):
    """The suite's only wall-clock-dependent test. Under the dummy driver a
    256-sample buffer drains in real time, so the leak `update()` is meant to
    fix can only be observed by actually waiting for it."""
    var audio = Audio()
    var one_shot = audio.play(_tone())
    var looping = audio.play(_tone(), loop=True)

    # Point 1: with no `update()` call, a finished one-shot leaks. There is no
    # public symptom to poll for while `update()` is absent, so this can only
    # be a fixed sleep past the drain, not a condition-gated wait.
    sleep(0.2)
    assert_true(audio.is_playing(one_shot))

    # Point 2: `update()` reaps it once the drain has happened. Poll rather
    # than assume one call suffices, so this stays robust on a slow machine.
    var reaped = False
    for _ in range(200):
        audio.update()
        if not audio.is_playing(one_shot):
            reaped = True
            break
        sleep(0.01)
    assert_true(reaped)

    # Point 3: the looping voice survives the same `update()` calls.
    assert_true(audio.is_playing(looping))


def test_many_concurrent_voices() raises -> None:
    var audio = Audio()
    var ids = List[Int]()
    for _ in range(16):
        ids.append(audio.play(_tone()))

    for i in range(16):
        assert_true(audio.is_playing(ids[i]))
    for i in range(16):
        for j in range(i + 1, 16):
            assert_true(ids[i] != ids[j])

    for i in range(0, 16, 2):
        audio.stop(ids[i])
    for i in range(16):
        if i % 2 == 0:
            assert_false(audio.is_playing(ids[i]))
        else:
            assert_true(audio.is_playing(ids[i]))

    var more = List[Int]()
    for _ in range(8):
        more.append(audio.play(_tone()))
    for i in range(8):
        for j in range(0, 16, 2):
            assert_true(more[i] != ids[j])


def test_voice_volume_does_not_disturb_is_playing() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    audio.volume(id, 0.3)
    assert_true(audio.is_playing(id))


def test_voice_volume_on_stale_id_is_a_no_op() raises -> None:
    var audio = Audio()
    var first = audio.play(_tone())
    audio.stop(first)
    var second = audio.play(_tone())
    audio.volume(first, 0.5)
    assert_false(audio.is_playing(first))
    assert_true(audio.is_playing(second))


def _gain(audio: Audio, id: Int) raises -> Float32:
    return audio._sdl.gain(audio._voices[Audio._decode(id)[0]].stream)


def test_volume_reads_back_its_default_and_what_was_set() raises -> None:
    var audio = Audio()
    assert_equal(audio.volume(), Float32(1.0))
    audio.volume(0.25)
    assert_equal(audio.volume(), Float32(0.25))


def test_volume_reaches_voices_already_playing() raises -> None:
    var audio = Audio()
    var one_shot = audio.play(_tone())
    var looping = audio.play(_tone(), loop=True)
    audio.volume(0.5)
    assert_equal(_gain(audio, one_shot), Float32(0.5))
    assert_equal(_gain(audio, looping), Float32(0.5))
    assert_equal(_gain(audio, audio.play(_tone())), Float32(0.5))


def test_voice_volume_is_scaled_by_the_volume() raises -> None:
    var audio = Audio()
    var id = audio.play(_tone())
    audio.volume(id, 0.5)
    audio.volume(0.5)
    assert_equal(_gain(audio, id), Float32(0.25))
    audio.volume(1.0)
    assert_equal(_gain(audio, id), Float32(0.5))


def _play_and_drop_scope() raises:
    var audio = Audio()
    _ = audio.play(_tone())
    _ = audio.play(_tone(), loop=True)
    _ = audio.play(_tone())


def test_clean_teardown_with_live_voices() raises -> None:
    # `audio` from the helper above drops at the end of its scope, exercising
    # `__deinit__` with live one-shot and looping voices still open. There is
    # little to assert since `__deinit__` swallows exceptions -- that's the
    # finding -- but a second `Audio` working afterward proves teardown
    # didn't abort the process or leave the device in a broken state.
    _play_and_drop_scope()
    var audio = Audio()
    var id = audio.play(_tone())
    assert_true(audio.is_playing(id))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
