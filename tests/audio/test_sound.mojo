from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from create.audio import Sound
from create.core import source_path


def _fixture(name: String) -> String:
    return source_path("../fixtures/" + name)


def test_from_pcm_byte_length() raises -> None:
    var data: List[Int16] = [0, 100, -100, 32767]
    var s = Sound.from_pcm(data, channels=2, freq=48000)
    assert_equal(len(s.pcm), len(data) * 2)
    assert_equal(s.channels, 2)
    assert_equal(s.freq, 48000)


def test_from_pcm_little_endian_packing() raises -> None:
    var data: List[Int16] = [1, -1]
    var s = Sound.from_pcm(data)
    var ptr = s.pcm.unsafe_ptr()
    # 1 == 0x0001 LE
    assert_equal(Int(ptr[unsafe_offset=0]), 1)
    assert_equal(Int(ptr[unsafe_offset=1]), 0)
    # -1 == 0xFFFF LE
    assert_equal(Int(ptr[unsafe_offset=2]), 255)
    assert_equal(Int(ptr[unsafe_offset=3]), 255)


def test_from_pcm_defaults() raises -> None:
    var data: List[Int16] = [0, 0]
    var s = Sound.from_pcm(data)
    assert_equal(s.channels, 1)
    assert_equal(s.freq, 44100)


def test_from_pcm_empty() raises -> None:
    var data = List[Int16]()
    var s = Sound.from_pcm(data)
    assert_equal(len(s.pcm), 0)


def test_from_pcm_single_sample() raises -> None:
    var data: List[Int16] = [12345]
    var s = Sound.from_pcm(data)
    assert_equal(len(s.pcm), 2)
    var ptr = s.pcm.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 57)
    assert_equal(Int(ptr[unsafe_offset=1]), 48)


def test_from_pcm_int16_min() raises -> None:
    var data: List[Int16] = [Int16.MIN]
    var s = Sound.from_pcm(data)
    var ptr = s.pcm.unsafe_ptr()
    # Int16.MIN == -32768 == 0x8000 LE
    assert_equal(Int(ptr[unsafe_offset=0]), 0)
    assert_equal(Int(ptr[unsafe_offset=1]), 128)


def test_load_wav() raises -> None:
    var s = Sound.load(_fixture("tone.wav"))
    assert_equal(s.channels, 1)
    assert_equal(s.freq, 8000)
    assert_equal(len(s.pcm), 160)
    var ptr = s.pcm.unsafe_ptr()
    assert_equal(Int(ptr[unsafe_offset=0]), 34)
    assert_equal(Int(ptr[unsafe_offset=1]), 1)


def test_load_flac() raises -> None:
    var s = Sound.load(_fixture("tone.flac"))
    assert_equal(s.channels, 1)
    assert_equal(s.freq, 8000)
    assert_equal(len(s.pcm), 160)
    var ptr = s.pcm.unsafe_ptr()
    # Lossless, so this can assert exact sample values, not a tolerance --
    # and they match tone.wav's, since both are the same source signal.
    assert_equal(Int(ptr[unsafe_offset=0]), 34)
    assert_equal(Int(ptr[unsafe_offset=1]), 1)


def test_load_dispatches_on_magic_bytes_not_extension() raises -> None:
    # tone_disguised.flac holds tone.wav's exact bytes under a `.flac` name --
    # `load` dispatches on the RIFF magic, not the extension, so this must
    # still take the WAV branch.
    var s = Sound.load(_fixture("tone_disguised.flac"))
    assert_equal(s.channels, 1)
    assert_equal(s.freq, 8000)
    assert_equal(len(s.pcm), 160)


def test_load_nonexistent_path_raises() raises -> None:
    with assert_raises():
        _ = Sound.load(_fixture("does_not_exist.wav"))


def test_load_too_short_file_raises() raises -> None:
    with assert_raises():
        _ = Sound.load(_fixture("too_short.bin"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
